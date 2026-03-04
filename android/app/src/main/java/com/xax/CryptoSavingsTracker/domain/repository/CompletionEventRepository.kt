package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import kotlinx.coroutines.flow.Flow

interface CompletionEventRepository {
    fun getAll(): Flow<List<CompletionEvent>>
    fun getByRecordId(recordId: String): Flow<List<CompletionEvent>>
    suspend fun getLatestOpenByRecordId(recordId: String): CompletionEvent?
    suspend fun getNextSequence(recordId: String): Int
    suspend fun insert(event: CompletionEvent)
    suspend fun markUndone(eventId: String, undoneAtMillis: Long, undoReason: String): Int
}
