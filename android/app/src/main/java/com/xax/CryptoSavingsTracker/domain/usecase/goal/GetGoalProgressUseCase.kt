package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import javax.inject.Inject

/**
 * Data class representing a goal with its progress information.
 * Progress is calculated as allocatedAmount / targetAmount.
 */
data class GoalWithProgress(
    val goal: Goal,
    val allocatedAmount: Double,
    val progress: Double // 0.0 to 1.0+ (can exceed 1.0 if over-funded)
) {
    val progressPercent: Int get() = (progress * 100).toInt().coerceIn(0, 100)
    val progressPercentExact: Double get() = progress * 100
}

/**
 * Use case to get goals with their progress calculated from allocations.
 * Progress formula matches iOS: allocatedAmount / targetAmount
 */
class GetGoalProgressUseCase @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository
) {
    /**
     * Get all goals with their progress.
     */
    operator fun invoke(): Flow<List<GoalWithProgress>> {
        return goalRepository.getAllGoals().map { goals ->
            goals.map { goal ->
                val allocated = allocationRepository.getTotalAllocatedForGoal(goal.id)
                GoalWithProgress(
                    goal = goal,
                    allocatedAmount = allocated,
                    progress = if (goal.targetAmount > 0) allocated / goal.targetAmount else 0.0
                )
            }
        }
    }

    /**
     * Get progress for a single goal.
     */
    suspend fun getProgress(goalId: String): GoalWithProgress? {
        val goal = goalRepository.getGoalById(goalId) ?: return null
        val allocated = allocationRepository.getTotalAllocatedForGoal(goalId)
        return GoalWithProgress(
            goal = goal,
            allocatedAmount = allocated,
            progress = if (goal.targetAmount > 0) allocated / goal.targetAmount else 0.0
        )
    }

    /**
     * Get progress for a single goal as a Flow for reactive updates.
     */
    fun getProgressFlow(goalId: String): Flow<GoalWithProgress?> {
        return combine(
            goalRepository.getGoalByIdFlow(goalId),
            allocationRepository.getAllocationsForGoalFlow(goalId)
        ) { goal, allocated ->
            goal?.let {
                GoalWithProgress(
                    goal = it,
                    allocatedAmount = allocated,
                    progress = if (it.targetAmount > 0) allocated / it.targetAmount else 0.0
                )
            }
        }
    }
}
