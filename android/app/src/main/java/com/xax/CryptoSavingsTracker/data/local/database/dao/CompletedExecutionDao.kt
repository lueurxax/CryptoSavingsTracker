package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.CompletedExecutionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CompletedExecutionDao {

    @Query("SELECT * FROM completed_executions ORDER BY completed_at_utc_millis DESC")
    fun getAllCompletedExecutions(): Flow<List<CompletedExecutionEntity>>

    @Query("SELECT * FROM completed_executions WHERE execution_record_id = :recordId ORDER BY completed_at_utc_millis DESC")
    fun getByRecordId(recordId: String): Flow<List<CompletedExecutionEntity>>

    @Query("SELECT * FROM completed_executions WHERE goal_id = :goalId ORDER BY completed_at_utc_millis DESC")
    fun getByGoalId(goalId: String): Flow<List<CompletedExecutionEntity>>

    @Query("SELECT * FROM completed_executions WHERE id = :id")
    suspend fun getById(id: String): CompletedExecutionEntity?

    @Query("SELECT * FROM completed_executions WHERE can_undo_until_utc_millis > :currentTimeMillis ORDER BY completed_at_utc_millis DESC")
    fun getUndoableExecutions(currentTimeMillis: Long): Flow<List<CompletedExecutionEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(execution: CompletedExecutionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(executions: List<CompletedExecutionEntity>)

    @Delete
    suspend fun delete(execution: CompletedExecutionEntity)

    @Query("DELETE FROM completed_executions WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM completed_executions WHERE execution_record_id = :recordId")
    suspend fun deleteByRecordId(recordId: String)
}
