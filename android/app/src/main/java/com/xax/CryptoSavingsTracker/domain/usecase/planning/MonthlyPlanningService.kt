package com.xax.CryptoSavingsTracker.domain.usecase.planning

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.AllocationFunding
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlin.math.min

/**
 * Service responsible for calculating monthly savings requirements.
 * Matches iOS MonthlyPlanningService behavior.
 */
@Singleton
class MonthlyPlanningService @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val assetRepository: AssetRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    @ApplicationContext private val context: Context
) {
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("monthly_planning_settings", Context.MODE_PRIVATE)
    }

    /**
     * Get the configured payment day (1-28).
     */
    var paymentDay: Int
        get() = prefs.getInt("payment_day", 1).coerceIn(1, 28)
        set(value) = prefs.edit().putInt("payment_day", value.coerceIn(1, 28)).apply()

    /**
     * Flex adjustment (0.0..1.5) stored separately from per-goal plans, matching iOS UserDefaults behavior.
     */
    var flexAdjustment: Double
        get() = prefs.getFloat("flex_adjustment", 1.0f).toDouble().coerceIn(0.0, 1.5)
        set(value) = prefs.edit().putFloat("flex_adjustment", value.toFloat().coerceIn(0.0f, 1.5f)).apply()

    /**
     * Display currency for totals in monthly planning.
     */
    var displayCurrency: String
        get() = prefs.getString("display_currency", "USD")?.trim()?.uppercase().orEmpty().ifBlank { "USD" }
        set(value) {
            val normalized = value.trim().uppercase().ifBlank { "USD" }
            prefs.edit().putString("display_currency", normalized).apply()
        }

    /**
     * Calculate monthly requirements for all active goals.
     */
    suspend fun calculateMonthlyRequirements(): List<MonthlyRequirement> {
        val goals = goalRepository.getAllGoals().first()
            .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }

        if (goals.isEmpty()) return emptyList()

        return goals.map { goal ->
            calculateRequirementForGoal(goal)
        }.sortedBy { it.goalName }
    }

    /**
     * Calculate monthly requirements as a Flow for reactive UI.
     */
    fun calculateMonthlyRequirementsFlow(): Flow<List<MonthlyRequirement>> = flow {
        emit(calculateMonthlyRequirements())
    }

    /**
     * Calculate total monthly requirement in display currency.
     */
    suspend fun calculateTotalRequired(displayCurrency: String): Double {
        val requirements = calculateMonthlyRequirements()

        var total = 0.0
        for (requirement in requirements) {
            total += convertAmount(
                amount = requirement.requiredMonthly,
                fromCurrency = requirement.currency,
                toCurrency = displayCurrency
            )
        }

        return total
    }

    suspend fun convertAmount(amount: Double, fromCurrency: String, toCurrency: String): Double {
        if (fromCurrency == toCurrency) return amount
        return try {
            val rate = exchangeRateRepository.fetchRate(fromCurrency, toCurrency)
            amount * rate
        } catch (e: Exception) {
            amount
        }
    }

    /**
     * Get monthly requirement for a single goal.
     */
    suspend fun getMonthlyRequirement(goalId: String): MonthlyRequirement? {
        val goal = goalRepository.getGoalById(goalId) ?: return null
        return calculateRequirementForGoal(goal)
    }

    /**
     * Calculate requirement for a single goal.
     */
    private suspend fun calculateRequirementForGoal(goal: Goal): MonthlyRequirement {
        // Calculate current total from allocations (using funded amount like iOS)
        val currentTotal = calculateCurrentTotal(goal)
        val remaining = max(0.0, goal.targetAmount - currentTotal)
        val monthsRemaining = max(1, calculateMonthsRemaining(LocalDate.now(), goal.deadline))
        val requiredMonthly = remaining / monthsRemaining.toDouble()
        val progress = if (goal.targetAmount > 0) min(currentTotal / goal.targetAmount, 1.0) else 0.0

        val status = determineRequirementStatus(
            remaining = remaining,
            monthsRemaining = monthsRemaining,
            requiredMonthly = requiredMonthly
        )

        return MonthlyRequirement(
            id = UUID.randomUUID().toString(),
            goalId = goal.id,
            goalName = goal.name,
            currency = goal.currency,
            targetAmount = goal.targetAmount,
            currentTotal = currentTotal,
            remainingAmount = remaining,
            monthsRemaining = monthsRemaining,
            requiredMonthly = requiredMonthly,
            progress = progress,
            deadline = goal.deadline,
            status = status
        )
    }

    /**
     * Calculate current total for a goal from allocations.
     * Uses the funded amount (min of allocation and asset balance).
     */
    private suspend fun calculateCurrentTotal(goal: Goal): Double {
        val allocations = allocationRepository.getAllocationsForGoal(goal.id)

        var total = 0.0
        for (allocation in allocations) {
            val asset = assetRepository.getAssetById(allocation.assetId)
            val assetCurrency = asset?.currency ?: goal.currency

            val manualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
            val onChainBalance = runCatching {
                if (asset != null && !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()) {
                    onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
                } else {
                    0.0
                }
            }.getOrElse { 0.0 }
            val assetBalance = manualBalance + onChainBalance

            val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
            val totalAllocatedForAsset = allAssetAllocations.sumOf { max(0.0, it.amount) }
            val fundedInAssetCurrency = AllocationFunding.fundedPortion(
                allocationAmount = allocation.amount,
                assetBalance = assetBalance,
                totalAllocatedForAsset = totalAllocatedForAsset
            )

            val fundedInGoalCurrency = if (assetCurrency.uppercase() == goal.currency.uppercase()) {
                fundedInAssetCurrency
            } else {
                runCatching {
                    exchangeRateRepository.fetchRate(assetCurrency, goal.currency)
                }.map { rate -> fundedInAssetCurrency * rate }
                    .getOrDefault(0.0)
            }
            total += fundedInGoalCurrency
        }

        return total
    }

    /**
     * Calculate how many payment periods remain until the deadline.
     * Uses the payment day from settings.
     */
    private fun calculateMonthsRemaining(startDate: LocalDate, endDate: LocalDate): Int {
        val payDay = paymentDay

        // Find the next payment date from startDate
        var paymentDate = startDate.withDayOfMonth(min(payDay, startDate.lengthOfMonth()))

        // If payment date this month has passed, start from next month
        if (!paymentDate.isAfter(startDate)) {
            paymentDate = paymentDate.plusMonths(1)
            paymentDate = paymentDate.withDayOfMonth(min(payDay, paymentDate.lengthOfMonth()))
        }

        // Count payment dates until we pass the deadline
        var count = 0
        while (paymentDate.isBefore(endDate)) {
            count++
            paymentDate = paymentDate.plusMonths(1)
            paymentDate = paymentDate.withDayOfMonth(min(payDay, paymentDate.lengthOfMonth()))
        }

        // Ensure at least 1 payment period
        return max(1, count)
    }

    /**
     * Determine the status based on requirement calculations.
     */
    private fun determineRequirementStatus(
        remaining: Double,
        monthsRemaining: Int,
        requiredMonthly: Double
    ): RequirementStatus {
        // Goal is complete
        if (remaining <= 0) {
            return RequirementStatus.COMPLETED
        }

        // Very high monthly requirement (over 10k)
        if (requiredMonthly > 10000) {
            return RequirementStatus.CRITICAL
        }

        // High monthly requirement (over 5k) or very short time
        if (requiredMonthly > 5000 || monthsRemaining <= 1) {
            return RequirementStatus.ATTENTION
        }

        // Normal requirement
        return RequirementStatus.ON_TRACK
    }
}
