package com.xax.CryptoSavingsTracker.domain.model

/**
 * Domain model representing a historical snapshot of an allocation.
 * Records allocation amount changes over time for execution tracking.
 */
data class AllocationHistory(
    val id: String,
    val assetId: String,
    val goalId: String,
    val amount: Double,
    val monthLabel: String,      // Format: "2025-01" for January 2025
    val timestamp: Long,         // When the snapshot was taken (UTC millis)
    val createdAt: Long          // Creation time for tie-breaking
)
