package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.AllocationHistoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AllocationHistoryDao {

    @Query("SELECT * FROM allocation_history ORDER BY timestamp_utc_millis DESC")
    fun getAll(): Flow<List<AllocationHistoryEntity>>

    @Query("SELECT * FROM allocation_history WHERE month_label = :monthLabel ORDER BY timestamp_utc_millis ASC")
    fun getByMonthLabel(monthLabel: String): Flow<List<AllocationHistoryEntity>>

    @Query("SELECT * FROM allocation_history WHERE asset_id = :assetId ORDER BY timestamp_utc_millis DESC")
    fun getByAssetId(assetId: String): Flow<List<AllocationHistoryEntity>>

    @Query("SELECT * FROM allocation_history WHERE goal_id = :goalId ORDER BY timestamp_utc_millis DESC")
    fun getByGoalId(goalId: String): Flow<List<AllocationHistoryEntity>>

    @Query("SELECT * FROM allocation_history WHERE asset_id = :assetId AND goal_id = :goalId AND month_label = :monthLabel")
    suspend fun getByAssetGoalMonth(assetId: String, goalId: String, monthLabel: String): AllocationHistoryEntity?

    @Query("SELECT * FROM allocation_history WHERE id = :id")
    suspend fun getById(id: String): AllocationHistoryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(history: AllocationHistoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(histories: List<AllocationHistoryEntity>)

    @Delete
    suspend fun delete(history: AllocationHistoryEntity)

    @Query("DELETE FROM allocation_history WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM allocation_history WHERE month_label = :monthLabel")
    suspend fun deleteByMonthLabel(monthLabel: String)
}
