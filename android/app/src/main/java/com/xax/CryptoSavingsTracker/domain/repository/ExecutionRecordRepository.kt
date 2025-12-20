package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import kotlinx.coroutines.flow.Flow

interface ExecutionRecordRepository {
    fun getCurrentExecutingRecord(): Flow<ExecutionRecord?>
    fun getRecordByMonthLabel(monthLabel: String): Flow<ExecutionRecord?>
    suspend fun getRecordByMonthLabelOnce(monthLabel: String): ExecutionRecord?
    suspend fun getRecordById(id: String): ExecutionRecord?
    fun getRecordsByStatus(status: ExecutionStatus): Flow<List<ExecutionRecord>>
    suspend fun upsert(record: ExecutionRecord)
    suspend fun close(recordId: String, closedAtMillis: Long)
    suspend fun reopen(recordId: String)
}
