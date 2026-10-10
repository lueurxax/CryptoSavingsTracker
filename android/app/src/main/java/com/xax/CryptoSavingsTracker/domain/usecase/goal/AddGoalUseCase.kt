package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import javax.inject.Inject

enum class ExistingGoalRetryPolicy {
    APPLY_LATEST_INPUT,
    KEEP_PERSISTED
}

/**
 * Use case for adding a new goal.
 * All fields match iOS Goal model for data parity.
 */
class AddGoalUseCase @Inject constructor(
    private val repository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler
) {
    /**
     * Add a new goal with the provided parameters
     */
    suspend operator fun invoke(
        name: String,
        currency: String,
        targetAmount: Double,
        deadline: LocalDate,
        startDate: LocalDate = LocalDate.now(),
        emoji: String? = null,
        description: String? = null,
        link: String? = null,
        reminderFrequency: ReminderFrequency? = null,
        reminderTimeMillis: Long? = null,
        firstReminderDate: LocalDate? = null,
        goalId: String,
        existingGoalRetryPolicy: ExistingGoalRetryPolicy =
            ExistingGoalRetryPolicy.APPLY_LATEST_INPUT
    ): Result<Goal> {
        // Validation
        if (name.isBlank()) {
            return Result.failure(IllegalArgumentException("Goal name cannot be empty"))
        }
        if (!targetAmount.isFinite() || targetAmount <= 0) {
            return Result.failure(
                IllegalArgumentException("Target amount must be finite and greater than 0")
            )
        }
        if (deadline.isBefore(startDate)) {
            return Result.failure(IllegalArgumentException("Deadline must be after start date"))
        }

        val normalizedReminderTimeMillis = if (reminderFrequency != null && reminderTimeMillis == null) {
            val zone = ZoneId.systemDefault()
            val baseDate = firstReminderDate ?: LocalDate.now(zone)
            baseDate.atTime(DEFAULT_REMINDER_TIME).atZone(zone).toInstant().toEpochMilli()
        } else {
            reminderTimeMillis
        }

        val normalizedFirstReminderDate = if (reminderFrequency != null && firstReminderDate == null) {
            LocalDate.now(ZoneId.systemDefault())
        } else {
            firstReminderDate
        }

        val now = System.currentTimeMillis()
        val goal = Goal(
            id = goalId,
            name = name.trim(),
            currency = currency,
            targetAmount = targetAmount,
            deadline = deadline,
            startDate = startDate,
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = emoji,
            description = description?.trim()?.takeIf { it.isNotEmpty() },
            link = link?.trim()?.takeIf { it.isNotEmpty() },
            reminderFrequency = reminderFrequency,
            reminderTimeMillis = normalizedReminderTimeMillis,
            firstReminderDate = normalizedFirstReminderDate,
            createdAt = now,
            updatedAt = now
        )

        return try {
            repository.getGoalById(goalId)?.let { existing ->
                val reconciled = when (existingGoalRetryPolicy) {
                    ExistingGoalRetryPolicy.APPLY_LATEST_INPUT -> goal.copy(
                        createdAt = existing.createdAt,
                        lifecycleStatus = existing.lifecycleStatus,
                        lifecycleStatusChangedAt = existing.lifecycleStatusChangedAt
                    ).also { repository.updateGoal(it) }
                    ExistingGoalRetryPolicy.KEEP_PERSISTED -> existing
                }
                reminderScheduler.schedule(reconciled)
                return Result.success(reconciled)
            }
            repository.insertGoal(goal)
            reminderScheduler.schedule(goal)
            Result.success(goal)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private companion object {
        val DEFAULT_REMINDER_TIME: LocalTime = LocalTime.of(9, 0)
    }
}
