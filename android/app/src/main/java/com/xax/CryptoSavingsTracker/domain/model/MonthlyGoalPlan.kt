package com.xax.CryptoSavingsTracker.domain.model

/**
 * Per-goal monthly plan persisted in Room.
 * Mirrors iOS MonthlyPlan (one row per goal per month).
 */
data class MonthlyGoalPlan(
    val id: String,
    val goalId: String,
    val monthLabel: String,
    val requiredMonthly: Double,
    val remainingAmount: Double,
    val monthsRemaining: Int,
    val currency: String,
    val status: RequirementStatus,
    val state: MonthlyGoalPlanState,
    val customAmount: Double?,
    val isProtected: Boolean,
    val isSkipped: Boolean,
    val createdAtUtcMillis: Long,
    val lastModifiedAtUtcMillis: Long
) {
    val effectiveAmount: Double
        get() = if (isSkipped) 0.0 else (customAmount ?: requiredMonthly)
}

enum class MonthlyGoalPlanState(val rawValue: String) {
    DRAFT("draft"),
    EXECUTING("executing"),
    COMPLETED("completed");

    companion object {
        fun fromString(value: String?): MonthlyGoalPlanState = when (value?.lowercase()) {
            "executing" -> EXECUTING
            "completed" -> COMPLETED
            else -> DRAFT
        }
    }
}

