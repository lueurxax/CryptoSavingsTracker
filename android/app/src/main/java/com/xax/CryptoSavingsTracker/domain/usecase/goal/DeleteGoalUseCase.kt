package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Use case for deleting a goal
 */
class DeleteGoalUseCase @Inject constructor(
    private val repository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    /**
     * Delete a goal by ID
     */
    suspend operator fun invoke(goalId: String): Result<Unit> = runCatching {
        guardedDelete(goalId) {
            repository.deleteGoal(goalId)
        }
        reminderScheduler.cancel(goalId)
    }

    /**
     * Delete a goal
     */
    suspend fun delete(goal: Goal): Result<Unit> = runCatching {
        guardedDelete(goal.id) {
            repository.deleteGoal(goal)
        }
        reminderScheduler.cancel(goal.id)
    }

    private suspend fun guardedDelete(
        goalId: String,
        delete: suspend () -> Unit
    ) {
        transactionRunner.run {
            val hasExecutionEvidence =
                executionSnapshotRepository.getByGoalId(goalId).first().isNotEmpty() ||
                    completedExecutionRepository.getByGoalId(goalId).first().isNotEmpty()
            check(!hasExecutionEvidence) {
                "Goal cannot be deleted because execution history depends on it"
            }
            delete()
        }
    }
}
