package com.xax.CryptoSavingsTracker.domain.model

/**
 * Immutable record of a completed goal execution.
 */
data class CompletedExecution(
    val id: String,
    val executionRecordId: String,
    val goalId: String,
    val goalName: String,
    val currency: String,
    val requiredAmount: Double,
    val actualAmount: Double,
    val completedAtMillis: Long,
    val canUndoUntilMillis: Long,
    val createdAtMillis: Long
)

