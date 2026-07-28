package com.xax.CryptoSavingsTracker.domain.model

/**
 * Monthly execution record tracking the execution state for a month.
 */
data class ExecutionRecord(
    val id: String,
    val planId: String,
    val monthLabel: String,
    val status: ExecutionStatus,
    val startedAtMillis: Long?,
    val closedAtMillis: Long?,
    val canUndoUntilMillis: Long?,
    val createdAtMillis: Long,
    val updatedAtMillis: Long,
    /** True for a schema-v5 record that may still be resumed but has no rate rows. */
    val legacyRateSnapshotPending: Boolean = false
) {
    /**
     * Check if the execution can still be undone (within grace period).
     */
    fun canUndo(nowMillis: Long = System.currentTimeMillis()): Boolean {
        val undoDeadline = canUndoUntilMillis ?: return false
        return nowMillis < undoDeadline
    }
}
