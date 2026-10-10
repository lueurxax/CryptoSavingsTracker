package com.xax.CryptoSavingsTracker.domain.model

/**
 * Immutable conversion rate captured when an execution record starts.
 *
 * A rate is keyed by the source asset and the currency of an execution goal
 * snapshot, so progress remains stable while the record is executing.
 */
data class ExecutionAssetRate(
    val assetId: String,
    val snapshotCurrency: String,
    val rate: Double,
    val capturedAtMillis: Long = System.currentTimeMillis()
)
