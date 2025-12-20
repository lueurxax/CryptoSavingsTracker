package com.xax.CryptoSavingsTracker.domain.model

/**
 * Snapshot of a goal at execution start.
 */
data class ExecutionSnapshot(
    val id: String,
    val executionRecordId: String,
    val goalId: String,
    val goalName: String,
    val currency: String,
    val targetAmount: Double,
    val currentTotalAtStart: Double,
    val requiredAmount: Double,
    val isProtected: Boolean,
    val isSkipped: Boolean,
    val customAmount: Double?,
    val createdAtMillis: Long
)

