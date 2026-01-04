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
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
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
    val allocatedAmount: Double,  // Total allocated value in goal currency
    val fundedAmount: Double,     // Total funded value in goal currency
    val progress: Double          // 0.0 to 1.0 (capped at 1.0), based on fundedAmount
) {
    val progressPercent: Int get() = (progress * 100).toInt().coerceIn(0, 100)
    val progressPercentExact: Double get() = progress * 100

    // Convenience constructor for backwards compatibility
    constructor(goal: Goal, allocatedAmount: Double, progress: Double) : this(
        goal = goal,
        allocatedAmount = allocatedAmount,
        fundedAmount = allocatedAmount,
        progress = progress
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
        return goalRepository.getAllGoals().map { goals ->
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
            allocationRepository.getAllocationsForGoalListFlow(goalId)
        ) { goal, allocations ->
            if (goal == null) {
                null
            } else {
                calculateGoalProgressFromAllocations(goal, allocations)
            }
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

        for (allocation in allocations) {
            val asset = assetRepository.getAssetById(allocation.assetId)
            val assetCurrency = asset?.currency ?: goal.currency

            val assetManualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
            val onChainBalance = runCatching {
                if (asset != null && !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()) {
                    onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
                } else {
                    0.0
                }
            }.getOrElse { 0.0 }
            val assetBalance = assetManualBalance + onChainBalance

            val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
            val totalAllocatedForAsset = allAssetAllocations.sumOf { max(0.0, it.amount) }

            // Under/over-funded assets distribute balance proportionally across targets.
            val fundedPortion = AllocationFunding.fundedPortion(
                allocationAmount = allocation.amount,
                assetBalance = assetBalance,
                totalAllocatedForAsset = totalAllocatedForAsset
            )

            val allocatedValue = convertToGoalCurrency(
                amount = allocation.amount,
                fromCurrency = assetCurrency,
                goalCurrency = goal.currency
            ) ?: continue
            val fundedValue = convertToGoalCurrency(
                amount = fundedPortion,
                fromCurrency = assetCurrency,
                goalCurrency = goal.currency
            ) ?: continue

            totalAllocatedInGoalCurrency += allocatedValue
            totalFundedInGoalCurrency += fundedValue
        }

        val progress = goal.progressFromFunded(totalFundedInGoalCurrency)

        return GoalWithProgress(
            goal = goal,
            allocatedAmount = totalAllocatedInGoalCurrency,
            fundedAmount = totalFundedInGoalCurrency,
            progress = progress
        )
    }

    private suspend fun convertToGoalCurrency(
        amount: Double,
        fromCurrency: String,
        goalCurrency: String
    ): Double? {
        if (fromCurrency.equals(goalCurrency, ignoreCase = true)) return amount
        val rate = runCatching { exchangeRateRepository.fetchRate(fromCurrency, goalCurrency) }.getOrNull()
        return rate?.let { amount * it }
    }
}
