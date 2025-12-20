package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionSnapshotEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExecutionSnapshotDao {

    @Query("SELECT * FROM execution_snapshots WHERE execution_record_id = :recordId")
    fun getSnapshotsByRecordId(recordId: String): Flow<List<ExecutionSnapshotEntity>>

    @Query("SELECT * FROM execution_snapshots WHERE execution_record_id = :recordId AND goal_id = :goalId")
    suspend fun getSnapshotByRecordAndGoal(recordId: String, goalId: String): ExecutionSnapshotEntity?

    @Query("SELECT * FROM execution_snapshots WHERE id = :id")
    suspend fun getSnapshotById(id: String): ExecutionSnapshotEntity?

    @Query("SELECT * FROM execution_snapshots WHERE goal_id = :goalId ORDER BY created_at_utc_millis DESC")
    fun getSnapshotsByGoalId(goalId: String): Flow<List<ExecutionSnapshotEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(snapshot: ExecutionSnapshotEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(snapshots: List<ExecutionSnapshotEntity>)

    @Delete
    suspend fun delete(snapshot: ExecutionSnapshotEntity)

    @Query("DELETE FROM execution_snapshots WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM execution_snapshots WHERE execution_record_id = :recordId")
    suspend fun deleteByRecordId(recordId: String)
}
