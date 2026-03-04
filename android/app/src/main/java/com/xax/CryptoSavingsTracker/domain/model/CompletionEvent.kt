package com.xax.CryptoSavingsTracker.domain.model

/**
 * Append-only completion event for execution history.
 * A completion may later be marked as undone, but the event remains in history.
 */
data class CompletionEvent(
    val id: String,
    val executionRecordId: String,
    val monthLabel: String,
    val sequence: Int,
    val sourceDiscriminator: String,
    val completedAtMillis: Long,
    val completionSnapshotRef: String?,
    val createdAtMillis: Long,
    val undoneAtMillis: Long? = null,
    val undoReason: String? = null
)
