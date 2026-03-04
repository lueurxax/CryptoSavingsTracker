package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import kotlinx.coroutines.flow.Flow

interface CompletedExecutionRepository {
    fun getAll(): Flow<List<CompletedExecution>>
    fun getByRecordId(recordId: String): Flow<List<CompletedExecution>>
    fun getActiveByRecordId(recordId: String): Flow<List<CompletedExecution>>
    fun getByCompletionEventId(completionEventId: String): Flow<List<CompletedExecution>>
    fun getActiveByCompletionEventId(completionEventId: String): Flow<List<CompletedExecution>>
    suspend fun append(executions: List<CompletedExecution>)
    suspend fun deleteByRecordId(recordId: String)
    suspend fun markUndoneByRecordId(recordId: String, undoneAtMillis: Long, undoReason: String)
    suspend fun markUndoneByCompletionEventId(completionEventId: String, undoneAtMillis: Long, undoReason: String)
    fun getUndoable(currentTimeMillis: Long): Flow<List<CompletedExecution>>
}
