package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyExecutionRecordEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExecutionRecordDao {

    @Query("SELECT * FROM monthly_execution_records ORDER BY month_label DESC")
    fun getAllRecords(): Flow<List<MonthlyExecutionRecordEntity>>

    @Query("SELECT * FROM monthly_execution_records WHERE month_label = :monthLabel")
    fun getRecordByMonthLabel(monthLabel: String): Flow<MonthlyExecutionRecordEntity?>

    @Query("SELECT * FROM monthly_execution_records WHERE month_label = :monthLabel")
    suspend fun getRecordByMonthLabelOnce(monthLabel: String): MonthlyExecutionRecordEntity?

    @Query("SELECT * FROM monthly_execution_records WHERE id = :id")
    suspend fun getRecordById(id: String): MonthlyExecutionRecordEntity?

    @Query("SELECT * FROM monthly_execution_records WHERE status = :status ORDER BY month_label DESC")
    fun getRecordsByStatus(status: String): Flow<List<MonthlyExecutionRecordEntity>>

    @Query("SELECT * FROM monthly_execution_records WHERE status = 'executing' ORDER BY month_label DESC LIMIT 1")
    fun getCurrentExecutingRecord(): Flow<MonthlyExecutionRecordEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(record: MonthlyExecutionRecordEntity)

    @Update
    suspend fun update(record: MonthlyExecutionRecordEntity)

    @Delete
    suspend fun delete(record: MonthlyExecutionRecordEntity)

    @Query("DELETE FROM monthly_execution_records WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE monthly_execution_records SET status = :status, last_modified_at_utc_millis = :modifiedAt WHERE id = :id")
    suspend fun updateStatus(id: String, status: String, modifiedAt: Long)

    @Query("UPDATE monthly_execution_records SET status = 'closed', closed_at_utc_millis = :closedAt, last_modified_at_utc_millis = :modifiedAt WHERE id = :id")
    suspend fun closeRecord(id: String, closedAt: Long, modifiedAt: Long)
}
