package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import javax.inject.Inject

/**
 * Use case for updating an existing goal
 */
class UpdateGoalUseCase @Inject constructor(
    private val repository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler
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

        val normalized = normalizeReminderDefaults(goal)
        val updatedGoal = normalized.copy(updatedAt = System.currentTimeMillis())

        return try {
            repository.updateGoal(updatedGoal)
            if (updatedGoal.lifecycleStatus == GoalLifecycleStatus.ACTIVE) {
                reminderScheduler.schedule(updatedGoal)
            } else {
                reminderScheduler.cancel(updatedGoal.id)
            }
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
            val updated = repository.getGoalById(goalId)
            if (status == GoalLifecycleStatus.ACTIVE && updated != null) {
                reminderScheduler.schedule(normalizeReminderDefaults(updated))
            } else {
                reminderScheduler.cancel(goalId)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun normalizeReminderDefaults(goal: Goal): Goal {
        val reminderFrequency = goal.reminderFrequency ?: return goal.copy(
            reminderTimeMillis = null,
            firstReminderDate = null
        )

        val zone = ZoneId.systemDefault()
        val firstDate = goal.firstReminderDate ?: LocalDate.now(zone)
        val reminderTimeMillis = goal.reminderTimeMillis ?: firstDate
            .atTime(DEFAULT_REMINDER_TIME)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()

        return goal.copy(
            reminderFrequency = reminderFrequency,
            reminderTimeMillis = reminderTimeMillis,
            firstReminderDate = goal.firstReminderDate ?: firstDate
        )
    }

    private companion object {
        val DEFAULT_REMINDER_TIME: LocalTime = LocalTime.of(9, 0)
    }
}
