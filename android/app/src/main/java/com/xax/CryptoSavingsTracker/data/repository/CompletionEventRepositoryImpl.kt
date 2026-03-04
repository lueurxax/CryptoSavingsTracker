package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.CompletionEventDao
import com.xax.CryptoSavingsTracker.data.repository.CompletionEventMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.CompletionEventMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CompletionEventRepositoryImpl @Inject constructor(
    private val completionEventDao: CompletionEventDao
) : CompletionEventRepository {

    override fun getAll(): Flow<List<CompletionEvent>> {
        return completionEventDao.getAll().map { entities -> entities.map { it.toDomain() } }
    }

    override fun getByRecordId(recordId: String): Flow<List<CompletionEvent>> {
        return completionEventDao.getByRecordId(recordId).map { entities -> entities.map { it.toDomain() } }
    }

    override suspend fun getLatestOpenByRecordId(recordId: String): CompletionEvent? {
        return completionEventDao.getLatestOpenByRecordId(recordId)?.toDomain()
    }

    override suspend fun getNextSequence(recordId: String): Int {
        return completionEventDao.getNextSequence(recordId)
    }

    override suspend fun insert(event: CompletionEvent) {
        completionEventDao.insert(event.toEntity())
    }

    override suspend fun markUndone(eventId: String, undoneAtMillis: Long, undoReason: String): Int {
        return completionEventDao.markUndone(eventId, undoneAtMillis, undoReason)
    }
}
