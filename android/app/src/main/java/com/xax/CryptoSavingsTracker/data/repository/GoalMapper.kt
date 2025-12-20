package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.converter.DateTimeUtils.toEpochDayInt
import com.xax.CryptoSavingsTracker.data.local.database.converter.DateTimeUtils.toLocalDate
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency

/**
 * Mapper functions to convert between GoalEntity (data layer) and Goal (domain layer)
 */
object GoalMapper {

    fun GoalEntity.toDomain(): Goal {
        return Goal(
            id = id,
            name = name,
            currency = currency,
            targetAmount = targetAmount,
            deadline = deadlineEpochDay.toLocalDate(),
            startDate = startDateEpochDay.toLocalDate(),
            lifecycleStatus = GoalLifecycleStatus.fromString(lifecycleStatus),
            reminderEnabled = reminderFrequency != null,
            reminderFrequency = ReminderFrequency.fromString(reminderFrequency),
            notes = description,
            createdAt = createdAtUtcMillis,
            updatedAt = lastModifiedAtUtcMillis
        )
    }

    fun Goal.toEntity(): GoalEntity {
        return GoalEntity(
            id = id,
            name = name,
            currency = currency,
            targetAmount = targetAmount,
            deadlineEpochDay = deadline.toEpochDayInt(),
            startDateEpochDay = startDate.toEpochDayInt(),
            lifecycleStatus = lifecycleStatus.name.lowercase(),
            reminderFrequency = if (reminderEnabled) reminderFrequency?.name?.lowercase() else null,
            description = notes,
            createdAtUtcMillis = createdAt,
            lastModifiedAtUtcMillis = updatedAt
        )
    }

    fun List<GoalEntity>.toDomainList(): List<Goal> {
        return map { it.toDomain() }
    }
}
