package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for AllocationHistory operations.
 * Provides access to allocation snapshots for execution tracking.
 */
interface AllocationHistoryRepository {
    /**
     * Get all allocation history records.
     */
    fun getAll(): Flow<List<AllocationHistory>>

    /**
     * Get allocation history for a specific month.
     * @param monthLabel Format: "2025-01" for January 2025
     */
    fun getByMonthLabel(monthLabel: String): Flow<List<AllocationHistory>>

    /**
     * Get allocation history for a specific asset.
     */
    fun getByAssetId(assetId: String): Flow<List<AllocationHistory>>

    /**
     * Get allocation history for a specific goal.
     */
    fun getByGoalId(goalId: String): Flow<List<AllocationHistory>>

    /**
     * Get a specific history record by asset, goal, and month.
     */
    suspend fun getByAssetGoalMonth(assetId: String, goalId: String, monthLabel: String): AllocationHistory?

    /**
     * Insert a new allocation history record.
     */
    suspend fun insert(history: AllocationHistory)

    /**
     * Insert multiple allocation history records.
     */
    suspend fun insertAll(histories: List<AllocationHistory>)

    /**
     * Delete an allocation history record by ID.
     */
    suspend fun deleteById(id: String)

    /**
     * Delete all allocation history for a month.
     */
    suspend fun deleteByMonthLabel(monthLabel: String)
}
