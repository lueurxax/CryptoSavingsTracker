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
    val createdAtMillis: Long,
    val updatedAtMillis: Long
)

