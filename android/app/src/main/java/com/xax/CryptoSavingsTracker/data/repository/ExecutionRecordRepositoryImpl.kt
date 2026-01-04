package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionRecordDao
import com.xax.CryptoSavingsTracker.data.repository.ExecutionRecordMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.ExecutionRecordMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExecutionRecordRepositoryImpl @Inject constructor(
    private val executionRecordDao: ExecutionRecordDao
) : ExecutionRecordRepository {

    override fun getCurrentExecutingRecord(): Flow<ExecutionRecord?> {
        return executionRecordDao.getCurrentExecutingRecord().map { it?.toDomain() }
    }

    override fun getRecordByMonthLabel(monthLabel: String): Flow<ExecutionRecord?> {
        return executionRecordDao.getRecordByMonthLabel(monthLabel).map { it?.toDomain() }
    }

    override suspend fun getRecordByMonthLabelOnce(monthLabel: String): ExecutionRecord? {
        return executionRecordDao.getRecordByMonthLabelOnce(monthLabel)?.toDomain()
    }

    override suspend fun getRecordById(id: String): ExecutionRecord? {
        return executionRecordDao.getRecordById(id)?.toDomain()
    }

    override fun getRecordsByStatus(status: ExecutionStatus): Flow<List<ExecutionRecord>> {
        return executionRecordDao.getRecordsByStatus(status.name.lowercase()).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun upsert(record: ExecutionRecord) {
        executionRecordDao.insert(record.toEntity())
    }

    override suspend fun close(recordId: String, closedAtMillis: Long) {
        val now = System.currentTimeMillis()
        executionRecordDao.closeRecord(recordId, closedAtMillis, now)
    }

    override suspend fun reopen(recordId: String) {
        val now = System.currentTimeMillis()
        executionRecordDao.reopenRecord(recordId, now)
    }

    override suspend fun revertToDraft(recordId: String) {
        val now = System.currentTimeMillis()
        executionRecordDao.revertToDraft(recordId, now)
    }

    override suspend fun updateCanUndoUntil(recordId: String, canUndoUntilMillis: Long) {
        val now = System.currentTimeMillis()
        executionRecordDao.updateCanUndoUntil(recordId, canUndoUntilMillis, now)
    }
}
