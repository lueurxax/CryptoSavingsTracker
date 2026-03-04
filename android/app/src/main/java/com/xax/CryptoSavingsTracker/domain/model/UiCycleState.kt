package com.xax.CryptoSavingsTracker.domain.model

sealed interface UiCycleState {
    data class Planning(val monthLabel: String, val source: PlanningSource) : UiCycleState
    data class Executing(
        val monthLabel: String,
        val canFinish: Boolean,
        val canUndoStart: Boolean
    ) : UiCycleState
    data class Closed(val monthLabel: String, val canUndoCompletion: Boolean) : UiCycleState
    data class Conflict(val monthLabel: String?, val reason: CycleConflictReason) : UiCycleState
}

enum class PlanningSource {
    CURRENT_MONTH,
    NEXT_MONTH_AFTER_CLOSED
}

enum class CycleConflictReason {
    DUPLICATE_ACTIVE_RECORDS,
    INVALID_MONTH_LABEL,
    FUTURE_RECORD
}
