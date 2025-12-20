package com.xax.CryptoSavingsTracker.domain.model

import java.time.LocalDate

/**
 * Domain model representing a savings goal.
 * This is the clean architecture domain entity, separate from the Room entity.
 */
data class Goal(
    val id: String,
    val name: String,
    val currency: String,
    val targetAmount: Double,
    val deadline: LocalDate,
    val startDate: LocalDate,
    val lifecycleStatus: GoalLifecycleStatus,
    val reminderEnabled: Boolean,
    val reminderFrequency: ReminderFrequency?,
    val notes: String?,
    val createdAt: Long,
    val updatedAt: Long
) {
    /**
     * Calculate progress percentage based on current value
     */
    fun progressPercentage(currentValue: Double): Double {
        if (targetAmount <= 0) return 0.0
        return (currentValue / targetAmount * 100).coerceIn(0.0, 100.0)
    }

    /**
     * Calculate days remaining until deadline
     */
    fun daysRemaining(): Long {
        return java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), deadline)
    }

    /**
     * Check if goal is overdue
     */
    fun isOverdue(): Boolean {
        return LocalDate.now().isAfter(deadline) && lifecycleStatus == GoalLifecycleStatus.ACTIVE
    }

    /**
     * Calculate months remaining until deadline
     */
    fun monthsRemaining(): Int {
        val now = LocalDate.now()
        return if (deadline.isAfter(now)) {
            java.time.Period.between(now, deadline).toTotalMonths().toInt()
        } else {
            0
        }
    }
}

/**
 * Goal lifecycle status matching iOS GoalLifecycleStatus
 */
enum class GoalLifecycleStatus {
    ACTIVE,
    PAUSED,
    COMPLETED,
    CANCELLED;

    companion object {
        fun fromString(value: String): GoalLifecycleStatus {
            return entries.find { it.name.equals(value, ignoreCase = true) } ?: ACTIVE
        }
    }
}

/**
 * Reminder frequency options matching iOS ReminderFrequency
 */
enum class ReminderFrequency {
    DAILY,
    WEEKLY,
    BIWEEKLY,
    MONTHLY;

    companion object {
        fun fromString(value: String?): ReminderFrequency? {
            if (value == null) return null
            return entries.find { it.name.equals(value, ignoreCase = true) }
        }
    }

    fun displayName(): String = when (this) {
        DAILY -> "Daily"
        WEEKLY -> "Weekly"
        BIWEEKLY -> "Every 2 Weeks"
        MONTHLY -> "Monthly"
    }
}
