package com.xax.CryptoSavingsTracker.domain.model

import java.time.LocalDate

/**
 * Domain model representing a savings goal.
 * This is the clean architecture domain entity, separate from the Room entity.
 * All fields match iOS Goal model for data parity.
 */
data class Goal(
    val id: String,
    val name: String,
    val currency: String,
    val targetAmount: Double,
    val deadline: LocalDate,
    val startDate: LocalDate,
    val lifecycleStatus: GoalLifecycleStatus,
    val lifecycleStatusChangedAt: Long?,
    val emoji: String?,
    val description: String?,
    val link: String?,
    val reminderFrequency: ReminderFrequency?,
    val reminderTimeMillis: Long?,
    val firstReminderDate: LocalDate?,
    val createdAt: Long,
    val updatedAt: Long
) {
    /**
     * Whether reminders are enabled (matches iOS isReminderEnabled)
     */
    val isReminderEnabled: Boolean
        get() = reminderFrequency != null && reminderTimeMillis != null

    /**
     * Calculate progress percentage based on current value
     */
    fun progressPercentage(currentValue: Double): Double {
        if (targetAmount <= 0) return 0.0
        return (currentValue / targetAmount * 100).coerceIn(0.0, 100.0)
    }

    /**
     * Progress from a funded total (0.0 to 1.0), capped at 1.0.
     * Mirrors iOS Goal.progress behavior.
     */
    fun progressFromFunded(fundedAmount: Double): Double {
        if (targetAmount <= 0) return 0.0
        return (fundedAmount / targetAmount).coerceIn(0.0, 1.0)
    }

    /**
     * Progress percent (0..100) based on funded amount.
     */
    fun progressPercentFromFunded(fundedAmount: Double): Int {
        return (progressFromFunded(fundedAmount) * 100).toInt().coerceIn(0, 100)
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
 * Goal lifecycle status matching iOS GoalLifecycleStatus exactly.
 * Uses lowercase names to match iOS rawValue strings.
 */
enum class GoalLifecycleStatus(val rawValue: String) {
    ACTIVE("active"),
    CANCELLED("cancelled"),
    FINISHED("finished"),
    DELETED("deleted");

    companion object {
        fun fromString(value: String): GoalLifecycleStatus {
            return entries.find { it.rawValue.equals(value, ignoreCase = true) } ?: ACTIVE
        }
    }

    fun displayName(): String = when (this) {
        ACTIVE -> "Active"
        CANCELLED -> "Cancelled"
        FINISHED -> "Finished"
        DELETED -> "Deleted"
    }
}

/**
 * Reminder frequency options matching iOS ReminderFrequency exactly.
 * iOS only has: weekly, biweekly, monthly (no daily option).
 */
enum class ReminderFrequency(val rawValue: String) {
    WEEKLY("weekly"),
    BIWEEKLY("biweekly"),
    MONTHLY("monthly");

    companion object {
        fun fromString(value: String?): ReminderFrequency? {
            if (value == null) return null
            return entries.find { it.rawValue.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true) }
        }
    }

    fun displayName(): String = when (this) {
        WEEKLY -> "Weekly"
        BIWEEKLY -> "Bi-weekly"
        MONTHLY -> "Monthly"
    }
}
