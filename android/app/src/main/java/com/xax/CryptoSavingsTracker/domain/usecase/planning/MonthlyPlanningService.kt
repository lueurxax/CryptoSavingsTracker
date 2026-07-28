package com.xax.CryptoSavingsTracker.domain.usecase.planning

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateQuote
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.AllocationFunding
import com.xax.CryptoSavingsTracker.domain.util.PlanningCalendarUtc
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlin.math.min

enum class MonthlyPlanningIssueReason {
    MISSING_ASSET,
    ON_CHAIN_BALANCE_UNAVAILABLE,
    STALE_ON_CHAIN_BALANCE,
    INVALID_ON_CHAIN_BALANCE,
    EXCHANGE_RATE_UNAVAILABLE
}

data class MonthlyPlanningIssue(
    val reason: MonthlyPlanningIssueReason,
    val goalId: String,
    val assetId: String
)

data class MonthlyPlanningFundingEvidence(
    val goalId: String,
    val allocation: Allocation,
    val allAssetAllocations: List<Allocation>,
    val asset: Asset?,
    val manualTransactions: List<Transaction>,
    val onChainBalance: OnChainBalance?,
    val conversionQuote: ExchangeRateQuote?
)

data class MonthlyPlanningSnapshot(
    val goals: List<Goal>,
    val requirements: List<MonthlyRequirement>,
    val fundingEvidence: List<MonthlyPlanningFundingEvidence>,
    val paymentDay: Int,
    val flexAdjustment: Double,
    val displayCurrency: String,
    val issues: List<MonthlyPlanningIssue>,
    val undoGracePeriodHours: Int = 24
) {
    val isComplete: Boolean
        get() = issues.isEmpty()

    fun requireComplete() {
        check(isComplete) {
            val reasons = issues.joinToString { issue ->
                "${issue.reason.name.lowercase()}:${issue.assetId}"
            }
            "Monthly planning data is incomplete ($reasons); refresh balances and rates, then retry"
        }
    }
}

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
        get() = prefs.getFloat("flex_adjustment", 1.0f)
            .takeIf(Float::isFinite)
            ?.toDouble()
            ?.coerceIn(0.0, 1.5)
            ?: 1.0
        set(value) {
            require(value.isFinite()) {
                "Flex adjustment must be finite"
            }
            prefs.edit()
                .putFloat("flex_adjustment", value.coerceIn(0.0, 1.5).toFloat())
                .apply()
        }

    /**
     * Display currency for totals in monthly planning.
     */
    var displayCurrency: String
        get() = prefs.getString("display_currency", "USD")?.trim()?.uppercase().orEmpty().ifBlank { "USD" }
        set(value) {
            val normalized = value.trim().uppercase().ifBlank { "USD" }
            prefs.edit().putString("display_currency", normalized).apply()
        }

    val undoGracePeriodHours: Int
        get() = prefs.getInt(
            "MonthlyPlanning.UndoGracePeriodHours",
            24
        ).coerceIn(0, 168)

    /**
     * Calculate monthly requirements for all active goals.
     */
    suspend fun calculateMonthlyRequirements(): List<MonthlyRequirement> {
        val snapshot = calculateSnapshot(requireImmutableInputs = false)
        snapshot.requireComplete()
        return snapshot.requirements
    }

    /**
     * Captures the source data used to create an immutable execution snapshot.
     *
     * Unlike the display-oriented API, this result preserves balance freshness,
     * conversion provenance, and every allocation/manual-transaction input.
     */
    suspend fun calculateExecutionSnapshot(): MonthlyPlanningSnapshot {
        return calculateSnapshot(requireImmutableInputs = true)
    }

    private suspend fun calculateSnapshot(
        requireImmutableInputs: Boolean
    ): MonthlyPlanningSnapshot {
        val goals = goalRepository.getAllGoals().first()
            .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            .sortedWith(compareBy<Goal>({ it.name }, { it.id }))
        val capturedPaymentDay = paymentDay
        val capturedFlexAdjustment = flexAdjustment
        val capturedDisplayCurrency = displayCurrency
        val capturedUndoGracePeriodHours = undoGracePeriodHours

        if (goals.isEmpty()) {
            return MonthlyPlanningSnapshot(
                goals = emptyList(),
                requirements = emptyList(),
                fundingEvidence = emptyList(),
                paymentDay = capturedPaymentDay,
                flexAdjustment = capturedFlexAdjustment,
                displayCurrency = capturedDisplayCurrency,
                issues = emptyList(),
                undoGracePeriodHours = capturedUndoGracePeriodHours
            )
        }

        val transactions = transactionRepository.getAllTransactions().first()
        val issues = mutableListOf<MonthlyPlanningIssue>()
        val fundingEvidence = mutableListOf<MonthlyPlanningFundingEvidence>()
        val requirements = goals.map { goal ->
            calculateRequirementForGoal(
                goal = goal,
                paymentDay = capturedPaymentDay,
                transactions = transactions,
                requireImmutableInputs = requireImmutableInputs,
                issues = issues,
                fundingEvidence = fundingEvidence
            )
        }

        return MonthlyPlanningSnapshot(
            goals = goals,
            requirements = requirements,
            fundingEvidence = fundingEvidence.sortedWith(
                compareBy<MonthlyPlanningFundingEvidence>(
                    { it.goalId },
                    { it.allocation.assetId },
                    { it.allocation.id }
                )
            ),
            paymentDay = capturedPaymentDay,
            flexAdjustment = capturedFlexAdjustment,
            displayCurrency = capturedDisplayCurrency,
            issues = issues.distinct().sortedWith(
                compareBy<MonthlyPlanningIssue>({ it.goalId }, { it.assetId }, { it.reason.name })
            ),
            undoGracePeriodHours = capturedUndoGracePeriodHours
        )
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
        check(amount.isFinite() && amount >= 0.0) {
            "Amount for $fromCurrency → $toCurrency is invalid"
        }
        if (fromCurrency.equals(toCurrency, ignoreCase = true)) return amount
        val rate = try {
            val rate = exchangeRateRepository.fetchRate(fromCurrency, toCurrency)
            check(rate.isFinite() && rate > 0.0) {
                "Exchange rate $fromCurrency → $toCurrency is invalid; refresh rates and retry"
            }
            rate
        } catch (e: Exception) {
            throw IllegalStateException(
                "Exchange rate $fromCurrency → $toCurrency is unavailable; refresh rates and retry",
                e
            )
        }
        val converted = amount * rate
        check(
            converted.isFinite() &&
                (amount == 0.0 || converted > 0.0)
        ) {
            "Converted amount for $fromCurrency → $toCurrency is invalid; refresh rates and retry"
        }
        return converted
    }

    /**
     * Get monthly requirement for a single goal.
     */
    suspend fun getMonthlyRequirement(goalId: String): MonthlyRequirement? {
        val goal = goalRepository.getGoalById(goalId) ?: return null
        val transactions = transactionRepository.getAllTransactions().first()
        val issues = mutableListOf<MonthlyPlanningIssue>()
        val requirement = calculateRequirementForGoal(
            goal = goal,
            paymentDay = paymentDay,
            transactions = transactions,
            requireImmutableInputs = false,
            issues = issues,
            fundingEvidence = mutableListOf()
        )
        check(issues.isEmpty()) {
            "Monthly planning data is incomplete; refresh balances and rates, then retry"
        }
        return requirement
    }

    /**
     * Calculate requirement for a single goal.
     */
    private suspend fun calculateRequirementForGoal(
        goal: Goal,
        paymentDay: Int,
        transactions: List<Transaction>,
        requireImmutableInputs: Boolean,
        issues: MutableList<MonthlyPlanningIssue>,
        fundingEvidence: MutableList<MonthlyPlanningFundingEvidence>
    ): MonthlyRequirement {
        // Calculate current total from allocations (using funded amount like iOS)
        val currentTotal = calculateCurrentTotal(
            goal = goal,
            transactions = transactions,
            requireImmutableInputs = requireImmutableInputs,
            issues = issues,
            fundingEvidence = fundingEvidence
        )
        val remaining = max(0.0, goal.targetAmount - currentTotal)
        val monthsRemaining = max(
            1,
            calculateMonthsRemaining(
                startDate = PlanningCalendarUtc.today(),
                endDate = goal.deadline,
                paymentDay = paymentDay
            )
        )
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
    private suspend fun calculateCurrentTotal(
        goal: Goal,
        transactions: List<Transaction>,
        requireImmutableInputs: Boolean,
        issues: MutableList<MonthlyPlanningIssue>,
        fundingEvidence: MutableList<MonthlyPlanningFundingEvidence>
    ): Double {
        val allocations = allocationRepository.getAllocationsForGoal(goal.id)
            .sortedWith(compareBy<Allocation>({ it.assetId }, { it.id }))

        var total = 0.0
        for (allocation in allocations) {
            val asset = assetRepository.getAssetById(allocation.assetId)
            if (asset == null) {
                issues += MonthlyPlanningIssue(
                    reason = MonthlyPlanningIssueReason.MISSING_ASSET,
                    goalId = goal.id,
                    assetId = allocation.assetId
                )
            }
            val assetCurrency = asset?.currency ?: goal.currency
            val manualTransactions = transactions
                .asSequence()
                .filter {
                    it.assetId == allocation.assetId && it.source == TransactionSource.MANUAL
                }
                .sortedWith(compareBy<Transaction>({ it.dateMillis }, { it.createdAt }, { it.id }))
                .toList()
            val manualBalance = manualTransactions.sumOf { it.amount }

            val balanceResult = if (asset?.address.isNullOrBlank()) {
                null
            } else {
                val balanceResult = runCatching {
                    onChainBalanceRepository.getBalance(
                        checkNotNull(asset),
                        forceRefresh = false
                    ).getOrThrow()
                }
                balanceResult
            }
            val onChainBalance = balanceResult?.getOrNull()
            val balanceResolution = if (asset == null) {
                null
            } else {
                AssetBalanceCompletenessResolver.resolveSnapshot(
                    asset = asset,
                    manualBalance = manualBalance,
                    providerBalance = onChainBalance
                )
            }
            if (asset != null && !asset.address.isNullOrBlank()) {
                when {
                    balanceResult?.isFailure != false -> {
                        issues += MonthlyPlanningIssue(
                            reason = MonthlyPlanningIssueReason.ON_CHAIN_BALANCE_UNAVAILABLE,
                            goalId = goal.id,
                            assetId = allocation.assetId
                        )
                    }
                    onChainBalance?.isStale == true -> {
                        issues += MonthlyPlanningIssue(
                            reason = MonthlyPlanningIssueReason.STALE_ON_CHAIN_BALANCE,
                            goalId = goal.id,
                            assetId = allocation.assetId
                        )
                    }
                    balanceResolution?.totalBalanceOrNull == null -> {
                        issues += MonthlyPlanningIssue(
                            reason = MonthlyPlanningIssueReason.INVALID_ON_CHAIN_BALANCE,
                            goalId = goal.id,
                            assetId = allocation.assetId
                        )
                    }
                }
            }
            val assetBalance = balanceResolution?.totalBalanceOrNull ?: 0.0

            val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
                .sortedWith(compareBy<Allocation>({ it.goalId }, { it.id }))
            val totalAllocatedForAsset = allAssetAllocations.sumOf { max(0.0, it.amount) }
            val fundedInAssetCurrency = AllocationFunding.fundedPortion(
                allocationAmount = allocation.amount,
                assetBalance = assetBalance,
                totalAllocatedForAsset = totalAllocatedForAsset
            )

            val conversionQuote = if (assetCurrency.equals(goal.currency, ignoreCase = true)) {
                ExchangeRateQuote(rate = 1.0, fetchedAtMillis = 0L)
            } else {
                runCatching {
                    if (requireImmutableInputs) {
                        exchangeRateRepository.fetchRateForImmutableSnapshot(
                            from = assetCurrency,
                            to = goal.currency,
                            maximumAgeMillis = MAXIMUM_EXECUTION_INPUT_AGE_MILLIS
                        )
                    } else {
                        ExchangeRateQuote(
                            rate = exchangeRateRepository.fetchRate(assetCurrency, goal.currency),
                            fetchedAtMillis = 0L
                        )
                    }
                }.getOrElse {
                    issues += MonthlyPlanningIssue(
                        reason = MonthlyPlanningIssueReason.EXCHANGE_RATE_UNAVAILABLE,
                        goalId = goal.id,
                        assetId = allocation.assetId
                    )
                    null
                }
            }
            if (conversionQuote != null && (!conversionQuote.rate.isFinite() || conversionQuote.rate <= 0.0)) {
                issues += MonthlyPlanningIssue(
                    reason = MonthlyPlanningIssueReason.EXCHANGE_RATE_UNAVAILABLE,
                    goalId = goal.id,
                    assetId = allocation.assetId
                )
            }

            fundingEvidence += MonthlyPlanningFundingEvidence(
                goalId = goal.id,
                allocation = allocation,
                allAssetAllocations = allAssetAllocations,
                asset = asset,
                manualTransactions = manualTransactions,
                onChainBalance = onChainBalance,
                conversionQuote = conversionQuote
            )

            val fundedInGoalCurrency =
                fundedInAssetCurrency * (conversionQuote?.rate?.takeIf { it.isFinite() && it > 0.0 } ?: 0.0)
            total += fundedInGoalCurrency
        }

        return total
    }

    /**
     * Calculate how many payment periods remain until the deadline.
     * Uses the payment day from settings.
     */
    private fun calculateMonthsRemaining(
        startDate: LocalDate,
        endDate: LocalDate,
        paymentDay: Int
    ): Int {
        return PlanningCalendarUtc.paymentPeriodsRemaining(
            startDate = startDate,
            endDate = endDate,
            paymentDay = paymentDay
        )
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

    private companion object {
        const val MAXIMUM_EXECUTION_INPUT_AGE_MILLIS = 5 * 60 * 1000L
    }
}
