package com.xax.CryptoSavingsTracker.domain.repository

import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for Allocation operations.
 * Provides access to asset-goal allocation data for progress calculation.
 */
interface AllocationRepository {
    /**
     * Get total amount allocated to a goal across all assets.
     * This is used for progress calculation.
     */
    suspend fun getTotalAllocatedForGoal(goalId: String): Double

    /**
     * Get total amount allocated from an asset across all goals.
     */
    suspend fun getTotalAllocatedForAsset(assetId: String): Double

    /**
     * Get allocations for a specific goal as a Flow for reactive updates.
     */
    fun getAllocationsForGoalFlow(goalId: String): Flow<Double>
}
