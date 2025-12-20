package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import kotlinx.coroutines.flow.Flow

interface CompletedExecutionRepository {
    fun getAll(): Flow<List<CompletedExecution>>
    fun getByRecordId(recordId: String): Flow<List<CompletedExecution>>
    suspend fun replaceForRecord(recordId: String, executions: List<CompletedExecution>)
    suspend fun deleteByRecordId(recordId: String)
    fun getUndoable(currentTimeMillis: Long): Flow<List<CompletedExecution>>
}
