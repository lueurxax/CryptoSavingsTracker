package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.CompletionEventEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CompletionEventDao {

    @Query("SELECT * FROM completion_events ORDER BY completed_at_utc_millis DESC, sequence DESC")
    fun getAll(): Flow<List<CompletionEventEntity>>

    @Query(
        "SELECT * FROM completion_events " +
            "WHERE execution_record_id = :recordId " +
            "ORDER BY sequence ASC"
    )
    fun getByRecordId(recordId: String): Flow<List<CompletionEventEntity>>

    @Query(
        "SELECT * FROM completion_events " +
            "WHERE execution_record_id = :recordId AND undone_at_utc_millis IS NULL " +
            "ORDER BY sequence DESC LIMIT 1"
    )
    suspend fun getLatestOpenByRecordId(recordId: String): CompletionEventEntity?

    @Query(
        "SELECT COALESCE(MAX(sequence), 0) + 1 FROM completion_events WHERE execution_record_id = :recordId"
    )
    suspend fun getNextSequence(recordId: String): Int

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(event: CompletionEventEntity)

    @Query(
        "UPDATE completion_events " +
            "SET undone_at_utc_millis = :undoneAtUtcMillis, undo_reason = :undoReason " +
            "WHERE id = :eventId AND undone_at_utc_millis IS NULL"
    )
    suspend fun markUndone(eventId: String, undoneAtUtcMillis: Long, undoReason: String): Int
}
