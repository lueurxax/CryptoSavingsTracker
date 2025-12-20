package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import javax.inject.Inject

/**
 * Use case for updating an existing goal
 */
class UpdateGoalUseCase @Inject constructor(
    private val repository: GoalRepository
) {
    /**
     * Update a goal with new values
     */
    suspend operator fun invoke(goal: Goal): Result<Goal> {
        // Validation
        if (goal.name.isBlank()) {
            return Result.failure(IllegalArgumentException("Goal name cannot be empty"))
        }
        if (goal.targetAmount <= 0) {
            return Result.failure(IllegalArgumentException("Target amount must be greater than 0"))
        }
        if (goal.deadline.isBefore(goal.startDate)) {
            return Result.failure(IllegalArgumentException("Deadline must be after start date"))
        }

        val updatedGoal = goal.copy(updatedAt = System.currentTimeMillis())

        return try {
            repository.updateGoal(updatedGoal)
            Result.success(updatedGoal)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Update goal status
     */
    suspend fun updateStatus(goalId: String, status: GoalLifecycleStatus): Result<Unit> {
        return try {
            repository.updateGoalStatus(goalId, status)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
