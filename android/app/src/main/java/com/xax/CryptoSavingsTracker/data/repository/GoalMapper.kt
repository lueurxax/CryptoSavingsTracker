package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.converter.DateTimeUtils.toEpochDayInt
import com.xax.CryptoSavingsTracker.data.local.database.converter.DateTimeUtils.toLocalDate
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency

/**
 * Mapper functions to convert between GoalEntity (data layer) and Goal (domain layer).
 * Maps ALL fields to prevent data loss on roundtrip.
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
            lifecycleStatusChangedAt = lifecycleStatusChangedAtUtcMillis,
            emoji = emoji,
            description = description,
            link = link,
            reminderFrequency = ReminderFrequency.fromString(reminderFrequency),
            reminderTimeMillis = reminderTimeUtcMillis,
            firstReminderDate = firstReminderEpochDay?.toLocalDate(),
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
            lifecycleStatus = lifecycleStatus.rawValue,
            lifecycleStatusChangedAtUtcMillis = lifecycleStatusChangedAt,
            emoji = emoji,
            description = description,
            link = link,
            reminderFrequency = reminderFrequency?.name?.lowercase(),
            reminderTimeUtcMillis = reminderTimeMillis,
            firstReminderEpochDay = firstReminderDate?.toEpochDayInt(),
            createdAtUtcMillis = createdAt,
            lastModifiedAtUtcMillis = updatedAt
        )
    }

    fun List<GoalEntity>.toDomainList(): List<Goal> {
        return map { it.toDomain() }
    }
}
