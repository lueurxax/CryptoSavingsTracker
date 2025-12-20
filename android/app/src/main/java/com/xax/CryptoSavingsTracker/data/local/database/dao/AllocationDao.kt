package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AllocationDao {

    @Query("SELECT * FROM asset_allocations")
    fun getAllAllocations(): Flow<List<AssetAllocationEntity>>

    @Query("SELECT * FROM asset_allocations WHERE asset_id = :assetId")
    fun getAllocationsByAssetId(assetId: String): Flow<List<AssetAllocationEntity>>

    @Query("SELECT * FROM asset_allocations WHERE goal_id = :goalId")
    fun getAllocationsByGoalId(goalId: String): Flow<List<AssetAllocationEntity>>

    @Query("SELECT * FROM asset_allocations WHERE asset_id = :assetId AND goal_id = :goalId")
    suspend fun getAllocationByAssetAndGoal(assetId: String, goalId: String): AssetAllocationEntity?

    @Query("SELECT * FROM asset_allocations WHERE id = :id")
    suspend fun getAllocationById(id: String): AssetAllocationEntity?

    @Query("SELECT SUM(amount) FROM asset_allocations WHERE asset_id = :assetId")
    suspend fun getTotalAllocatedForAsset(assetId: String): Double?

    @Query("SELECT SUM(amount) FROM asset_allocations WHERE goal_id = :goalId")
    suspend fun getTotalAllocatedForGoal(goalId: String): Double?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(allocation: AssetAllocationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(allocations: List<AssetAllocationEntity>)

    @Update
    suspend fun update(allocation: AssetAllocationEntity)

    @Delete
    suspend fun delete(allocation: AssetAllocationEntity)

    @Query("DELETE FROM asset_allocations WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM asset_allocations WHERE asset_id = :assetId")
    suspend fun deleteByAssetId(assetId: String)

    @Query("DELETE FROM asset_allocations WHERE goal_id = :goalId")
    suspend fun deleteByGoalId(goalId: String)
}
