package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import javax.inject.Inject

/**
 * Use case for deleting a goal
 */
class DeleteGoalUseCase @Inject constructor(
    private val repository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler
) {
    /**
     * Delete a goal by ID
     */
    suspend operator fun invoke(goalId: String): Result<Unit> {
        return try {
            reminderScheduler.cancel(goalId)
            repository.deleteGoal(goalId)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Delete a goal
     */
    suspend fun delete(goal: Goal): Result<Unit> {
        return try {
            reminderScheduler.cancel(goal.id)
            repository.deleteGoal(goal)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
