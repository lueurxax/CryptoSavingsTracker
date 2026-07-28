package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
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
    val goals: List<ExecutionGoalProgress>,
    val assetRates: List<ExecutionAssetRate> = emptyList(),
    val isProgressAvailable: Boolean = true
) {
    /** Shared currency for directly comparable totals, or null for mixed-currency sessions. */
    val totalsCurrency: String?
        get() = goals
            .asSequence()
            .filter { !it.snapshot.isSkipped }
            .map { it.snapshot.currency.uppercase() }
            .distinct()
            .toList()
            .singleOrNull()

    /** Total planned amount only when every included goal uses one real currency. */
    val totalPlanned: Double?
        get() = totalsCurrency?.let {
            goals.filter { !it.snapshot.isSkipped }.sumOf { goal -> goal.plannedAmount }
        }

    /** Total contributed amount only when every included goal uses one real currency. */
    val totalContributed: Double?
        get() = totalsCurrency?.let {
            goals.filter { !it.snapshot.isSkipped }.sumOf { goal -> goal.contributed }
        }

    /** Number of goals that are fulfilled */
    val fulfilledCount: Int
        get() = goals.count { it.isFulfilled }

    /**
     * Overall progress percentage as an equal-weighted mean of dimensionless
     * per-goal completion ratios. Monetary values in different currencies are
     * never added together.
     */
    val overallProgress: Double
        get() {
            val comparableGoals = goals.filter {
                !it.snapshot.isSkipped &&
                    it.plannedAmount.isFinite() &&
                    it.plannedAmount > 0.0
            }
            if (comparableGoals.isEmpty()) return 0.0
            return comparableGoals
                .map { goal ->
                    (goal.contributed / goal.plannedAmount)
                        .takeIf { it.isFinite() }
                        ?.coerceIn(0.0, 1.0)
                        ?: 0.0
                }
                .average() * 100.0
        }

    /** Goals that are not yet fulfilled (active) */
    val activeGoals: List<ExecutionGoalProgress>
        get() = goals.filter { !it.isFulfilled && !it.snapshot.isSkipped }

    /** Goals that are fulfilled (completed) */
    val completedGoals: List<ExecutionGoalProgress>
        get() = goals.filter { it.isFulfilled }
}
