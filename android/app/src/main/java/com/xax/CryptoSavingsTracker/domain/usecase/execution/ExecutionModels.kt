package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot

/**
 * Progress tracking for a single goal during execution.
 * Matches iOS approach of showing contributed vs planned amounts.
 */
data class ExecutionGoalProgress(
    val snapshot: ExecutionSnapshot,
    /** Amount contributed to this goal since execution started (sum of transaction deltas) */
    val contributed: Double,
    /** Planned amount for this goal this month (from monthly plan/required amount) */
    val plannedAmount: Double,
    /** Whether contributed >= plannedAmount */
    val isFulfilled: Boolean
) {
    /** Progress percentage (0-100) */
    val progressPercent: Int
        get() = if (plannedAmount > 0) {
            ((contributed / plannedAmount) * 100).toInt().coerceIn(0, 100)
        } else 0
}

/**
 * Active execution session with all goal progress.
 */
data class ExecutionSession(
    val record: ExecutionRecord,
    val goals: List<ExecutionGoalProgress>
) {
    /** Total planned amount across all goals */
    val totalPlanned: Double
        get() = goals.sumOf { it.plannedAmount }

    /** Total contributed amount across all goals */
    val totalContributed: Double
        get() = goals.sumOf { it.contributed }

    /** Number of goals that are fulfilled */
    val fulfilledCount: Int
        get() = goals.count { it.isFulfilled }

    /** Overall progress percentage */
    val overallProgress: Double
        get() = if (totalPlanned > 0) {
            (totalContributed / totalPlanned) * 100
        } else 0.0

    /** Goals that are not yet fulfilled (active) */
    val activeGoals: List<ExecutionGoalProgress>
        get() = goals.filter { !it.isFulfilled && !it.snapshot.isSkipped }

    /** Goals that are fulfilled (completed) */
    val completedGoals: List<ExecutionGoalProgress>
        get() = goals.filter { it.isFulfilled }
}
