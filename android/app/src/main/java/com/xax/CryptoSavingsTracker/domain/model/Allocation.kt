package com.xax.CryptoSavingsTracker.domain.model

/**
 * Domain model representing an allocation of an asset to a goal.
 * An allocation specifies how much of a particular asset is earmarked for a goal.
 */
data class Allocation(
    val id: String,
    val assetId: String,
    val goalId: String,
    val amount: Double,
    val createdAt: Long,
    val lastModifiedAt: Long
)
