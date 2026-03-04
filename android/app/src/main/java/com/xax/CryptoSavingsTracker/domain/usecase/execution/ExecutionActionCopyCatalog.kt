package com.xax.CryptoSavingsTracker.domain.usecase.execution

object ExecutionActionCopyCatalog {
    fun startBlockedMissingPlan(): String =
        "Complete planning first before starting tracking."

    fun startBlockedAlreadyExecuting(month: String): String =
        "Tracking is already active for $month."

    fun startBlockedClosedMonth(): String =
        "This month is already closed."

    fun finishBlockedNoExecuting(): String =
        "No active month is being tracked."

    fun undoStartExpired(month: String): String =
        "Undo period ended for $month."

    fun undoCompletionExpired(month: String): String =
        "Undo period ended for $month."

    fun recordConflict(): String =
        "Monthly state is out of sync. Please refresh."
}
