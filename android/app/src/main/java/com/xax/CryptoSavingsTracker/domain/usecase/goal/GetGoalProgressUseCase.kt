package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.math.max
import kotlin.math.min

/**
 * Data class representing a goal with its progress information.
 * Progress is calculated as fundedAmount / targetAmount, where fundedAmount
 * is the sum of min(allocation.amount, assetManualBalance) for each allocation.
 * This matches iOS behavior exactly.
 */
data class GoalWithProgress(
    val goal: Goal,
    val allocatedAmount: Double,  // Total allocated (sum of allocations)
    val fundedAmount: Double,     // Actual funded amount (min of allocation vs balance)
    val progress: Double          // 0.0 to 1.0 (capped at 1.0)
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
 * Progress formula matches iOS exactly:
 * - For each allocation: min(max(0, allocation.amount), asset.manualBalance)
 * - Sum all funded portions
 * - Progress = fundedTotal / targetAmount (capped at 1.0)
 *
 * This ensures progress reflects actual available funds, not just allocations.
 */
class GetGoalProgressUseCase @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository
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
        var totalAllocated = 0.0
        var totalFunded = 0.0

        for (allocation in allocations) {
            totalAllocated += allocation.amount

            // Get the asset's manual balance (sum of manual transactions)
            val assetManualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)

            // Funded portion is min of allocation and actual balance (clamped to >= 0)
            // This matches iOS: min(max(0, allocation.amountValue), asset.manualBalance)
            val fundedPortion = min(max(0.0, allocation.amount), assetManualBalance)
            totalFunded += fundedPortion
        }

        // Progress is capped at 1.0 (100%) to match iOS behavior
        val progress = if (goal.targetAmount > 0) {
            min(totalFunded / goal.targetAmount, 1.0)
        } else {
            0.0
        }

        return GoalWithProgress(
            goal = goal,
            allocatedAmount = totalAllocated,
            fundedAmount = totalFunded,
            progress = progress
        )
    }
}
