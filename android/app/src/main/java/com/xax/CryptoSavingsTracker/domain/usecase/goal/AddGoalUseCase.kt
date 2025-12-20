package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject

/**
 * Use case for adding a new goal.
 * All fields match iOS Goal model for data parity.
 */
class AddGoalUseCase @Inject constructor(
    private val repository: GoalRepository
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
        firstReminderDate: LocalDate? = null
    ): Result<Goal> {
        // Validation
        if (name.isBlank()) {
            return Result.failure(IllegalArgumentException("Goal name cannot be empty"))
        }
        if (targetAmount <= 0) {
            return Result.failure(IllegalArgumentException("Target amount must be greater than 0"))
        }
        if (deadline.isBefore(startDate)) {
            return Result.failure(IllegalArgumentException("Deadline must be after start date"))
        }

        val now = System.currentTimeMillis()
        val goal = Goal(
            id = UUID.randomUUID().toString(),
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
            reminderTimeMillis = reminderTimeMillis,
            firstReminderDate = firstReminderDate,
            createdAt = now,
            updatedAt = now
        )

        return try {
            repository.insertGoal(goal)
            Result.success(goal)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
