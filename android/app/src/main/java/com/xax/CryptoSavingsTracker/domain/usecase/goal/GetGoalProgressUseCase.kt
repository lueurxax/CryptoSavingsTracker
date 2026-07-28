package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.AllocationFunding
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.mapLatest
import javax.inject.Inject
import kotlin.math.max

/**
 * Data class representing a goal with its progress information.
 * Progress is calculated as fundedAmount / targetAmount, where fundedAmount
 * is the sum of each allocation's funded portion converted into the goal currency.
 * Funded portion uses best-known asset balance (manual + cached on-chain when available),
 * then distributes balance proportionally across allocations (iOS parity).
 */
data class GoalWithProgress(
    val goal: Goal,
    val allocatedAmount: Double?,  // Null when one or more required exchange rates are unavailable
    val fundedAmount: Double?,     // Null when a required balance or exchange rate is unavailable
    val progress: Double?,         // Null when fundedAmount is unavailable
    val financialDataIssue: String? = null
) {
    val progressPercent: Int?
        get() = progress?.let { (it * 100).toInt().coerceIn(0, 100) }
    val progressPercentExact: Double?
        get() = progress?.times(100)

    // Convenience constructor for backwards compatibility
    constructor(goal: Goal, allocatedAmount: Double, progress: Double) : this(
        goal = goal,
        allocatedAmount = allocatedAmount,
        fundedAmount = allocatedAmount,
        progress = progress,
        financialDataIssue = null
    )
}

/**
 * Use case to get goals with their progress calculated from allocations.
 *
 * Progress formula (iOS parity):
 * - Compute best-known asset balance (manual + cached on-chain if applicable)
 * - Under/over-funded assets distribute balance proportionally across targets
 * - Convert each allocation's allocated + funded values into the goal currency
 * - Progress = fundedTotalInGoalCurrency / targetAmount (capped at 1.0)
 *
 * This ensures progress reflects actual available funds, not just allocations.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GetGoalProgressUseCase @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val assetRepository: AssetRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) {
    /**
     * Get all goals with their progress.
     */
    operator fun invoke(): Flow<List<GoalWithProgress>> {
        return combine(
            goalRepository.getAllGoals(),
            financialDataInvalidations()
        ) { goals, _ ->
            goals
        }.mapLatest { goals ->
            goals.map { goal ->
                calculateGoalProgress(goal)
            }
        }
    }

    /**
     * Get progress for a single goal.
     */
    suspend fun getProgress(goalId: String): GoalWithProgress? {
        val goal = goalRepository.getGoalById(goalId) ?: return null
        return calculateGoalProgress(goal)
    }

    /**
     * Get progress for a single goal as a Flow for reactive updates.
     */
    fun getProgressFlow(goalId: String): Flow<GoalWithProgress?> {
        return combine(
            goalRepository.getGoalByIdFlow(goalId),
            allocationRepository.getAllocationsForGoalListFlow(goalId),
            financialDataInvalidations()
        ) { goal, allocations, _ ->
            goal to allocations
        }.mapLatest { (goal, allocations) ->
            if (goal == null) {
                null
            } else {
                calculateGoalProgressFromAllocations(goal, allocations)
            }
        }.catch { error ->
            if (error is CancellationException) throw error
            val goal = goalRepository.getGoalById(goalId) ?: throw error
            emit(
                GoalWithProgress(
                    goal = goal,
                    allocatedAmount = null,
                    fundedAmount = null,
                    progress = null,
                    financialDataIssue = "Goal financial data source is unavailable. " +
                        "Refresh data and retry."
                )
            )
        }
    }

    private fun financialDataInvalidations(): Flow<Unit> {
        return combine(
            allocationRepository.getAllAllocationsFlow(),
            transactionRepository.getAllTransactions(),
            assetRepository.getAllAssets(),
            onChainBalanceRepository.observeBalanceInvalidations(),
            exchangeRateRepository.observeRateInvalidations()
        ) { _, _, _, _, _ ->
            Unit
        }
    }

    /**
     * Calculate progress for a goal using the iOS formula:
     * fundedTotal = sum of min(allocation.amount, assetManualBalance) for each allocation
     * progress = min(fundedTotal / targetAmount, 1.0)
     */
    private suspend fun calculateGoalProgress(goal: Goal): GoalWithProgress {
        val allocations = allocationRepository.getAllocationsForGoal(goal.id)
        return calculateGoalProgressFromAllocations(goal, allocations)
    }

    /**
     * Calculate progress from a list of allocations.
     * This is the core iOS-matching logic.
     */
    private suspend fun calculateGoalProgressFromAllocations(
        goal: Goal,
        allocations: List<Allocation>
    ): GoalWithProgress {
        var totalAllocatedInGoalCurrency = 0.0
        var totalFundedInGoalCurrency = 0.0
        var allocatedAmountComplete = true
        var fundedAmountComplete = true
        val financialIssues = linkedSetOf<String>()

        for (allocation in allocations) {
            val asset = assetRepository.getAssetById(allocation.assetId)
            if (asset == null) {
                allocatedAmountComplete = false
                fundedAmountComplete = false
                financialIssues +=
                    "Asset for allocation ${allocation.id} is unavailable. Restore the asset and retry."
                continue
            }
            val assetCurrency = asset.currency

            val assetManualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
            val balanceResolution = AssetBalanceCompletenessResolver.resolve(
                asset = asset,
                manualBalance = assetManualBalance,
                repository = onChainBalanceRepository,
                forceRefresh = false
            )
            val assetBalance = balanceResolution.totalBalanceOrNull

            val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
            val totalAllocatedForAsset = allAssetAllocations.sumOf { max(0.0, it.amount) }

            val allocatedValue = convertToGoalCurrency(
                amount = allocation.amount,
                fromCurrency = assetCurrency,
                goalCurrency = goal.currency
            )
            if (allocatedValue == null) {
                allocatedAmountComplete = false
                fundedAmountComplete = false
                financialIssues += exchangeRateIssue(assetCurrency, goal.currency)
                continue
            }
            totalAllocatedInGoalCurrency += allocatedValue

            if (assetBalance == null) {
                fundedAmountComplete = false
                financialIssues += balanceResolution.issueOrNull
                    ?: "Asset balance is unavailable. Refresh wallet balances and retry."
                continue
            }

            // Under/over-funded assets distribute balance proportionally across targets.
            val fundedPortion = AllocationFunding.fundedPortion(
                allocationAmount = allocation.amount,
                assetBalance = assetBalance,
                totalAllocatedForAsset = totalAllocatedForAsset
            )
            val fundedValue = convertToGoalCurrency(
                amount = fundedPortion,
                fromCurrency = assetCurrency,
                goalCurrency = goal.currency
            )
            if (fundedValue == null) {
                fundedAmountComplete = false
                financialIssues += exchangeRateIssue(assetCurrency, goal.currency)
                continue
            }
            totalFundedInGoalCurrency += fundedValue
        }

        val allocatedAmount = totalAllocatedInGoalCurrency.takeIf { allocatedAmountComplete }
        val fundedAmount = totalFundedInGoalCurrency.takeIf { fundedAmountComplete }
        val progress = fundedAmount?.let(goal::progressFromFunded)

        return GoalWithProgress(
            goal = goal,
            allocatedAmount = allocatedAmount,
            fundedAmount = fundedAmount,
            progress = progress,
            financialDataIssue = financialIssues.takeIf { it.isNotEmpty() }?.joinToString(" ")
        )
    }

    private suspend fun convertToGoalCurrency(
        amount: Double,
        fromCurrency: String,
        goalCurrency: String
    ): Double? {
        if (fromCurrency.equals(goalCurrency, ignoreCase = true)) return amount
        val rate = runCatching { exchangeRateRepository.fetchRate(fromCurrency, goalCurrency) }.getOrNull()
        return rate
            ?.takeIf { it.isFinite() && it > 0.0 }
            ?.let { amount * it }
            ?.takeIf(Double::isFinite)
    }

    private fun exchangeRateIssue(fromCurrency: String, goalCurrency: String): String {
        return "Exchange rate $fromCurrency → $goalCurrency is unavailable. Refresh rates and retry."
    }
}
