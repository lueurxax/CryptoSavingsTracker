package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Allocation
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
     * Returns the total allocated amount (sum of all allocations).
     */
    fun getAllocationsForGoalFlow(goalId: String): Flow<Double>

    /**
     * Get all allocations for a specific goal.
     * Returns individual allocation records for proper progress calculation.
     */
    suspend fun getAllocationsForGoal(goalId: String): List<Allocation>

    /**
     * Get all allocations for a specific goal as a Flow for reactive updates.
     * Returns individual allocation records for proper progress calculation.
     */
    fun getAllocationsForGoalListFlow(goalId: String): Flow<List<Allocation>>

    /**
     * Get all allocations for a specific asset.
     */
    suspend fun getAllocationsForAsset(assetId: String): List<Allocation>

    /**
     * Get allocation by asset and goal.
     */
    suspend fun getAllocationByAssetAndGoal(assetId: String, goalId: String): Allocation?

    /**
     * Get allocation by ID.
     */
    suspend fun getAllocationById(id: String): Allocation?

    /**
     * Insert or update an allocation.
     */
    suspend fun upsertAllocation(allocation: Allocation)

    /**
     * Delete an allocation by ID.
     */
    suspend fun deleteAllocation(id: String)

    /**
     * Delete all allocations for a goal.
     */
    suspend fun deleteAllocationsForGoal(goalId: String)

    /**
     * Delete all allocations for an asset.
     */
    suspend fun deleteAllocationsForAsset(assetId: String)
}
