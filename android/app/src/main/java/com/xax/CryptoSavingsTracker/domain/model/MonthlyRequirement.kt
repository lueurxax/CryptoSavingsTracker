package com.xax.CryptoSavingsTracker.domain.model

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Represents the monthly savings requirement for a goal.
 * Matches iOS MonthlyRequirement structure.
 */
data class MonthlyRequirement(
    val id: String,
    val goalId: String,
    val goalName: String,
    val currency: String,
    val targetAmount: Double,
    val currentTotal: Double,
    val remainingAmount: Double,
    val monthsRemaining: Int,
    val requiredMonthly: Double,
    val progress: Double,
    val deadline: LocalDate,
    val status: RequirementStatus
) {
    /**
     * Time remaining description
     */
    val timeRemainingDescription: String
        get() = when {
            monthsRemaining <= 0 -> "Overdue"
            monthsRemaining == 1 -> "1 month left"
            else -> "$monthsRemaining months left"
        }

    /**
     * Days remaining until deadline
     */
    val daysRemaining: Int
        get() = maxOf(0, ChronoUnit.DAYS.between(LocalDate.now(), deadline).toInt())

    /**
     * Whether the goal has been achieved
     */
    val isAchieved: Boolean
        get() = currentTotal >= targetAmount

    /**
     * Formatted required monthly amount
     */
    fun formattedRequiredMonthly(): String {
        return "$currency ${String.format("%,.0f", requiredMonthly)}"
    }

    /**
     * Formatted remaining amount
     */
    fun formattedRemainingAmount(): String {
        return "$currency ${String.format("%,.0f", remainingAmount)}"
    }
}

/**
 * Status of a monthly requirement.
 * Matches iOS RequirementStatus enum.
 */
enum class RequirementStatus(val displayName: String) {
    COMPLETED("Completed"),
    ON_TRACK("On Track"),
    ATTENTION("Needs Attention"),
    CRITICAL("Critical");

    companion object {
        fun fromRawValue(value: String): RequirementStatus {
            return when (value.lowercase()) {
                "completed" -> COMPLETED
                "on_track" -> ON_TRACK
                "attention" -> ATTENTION
                "critical" -> CRITICAL
                else -> ON_TRACK
            }
        }
    }
}
