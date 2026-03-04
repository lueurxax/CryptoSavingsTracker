package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.CompletedExecutionDao
import com.xax.CryptoSavingsTracker.data.repository.CompletedExecutionMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.CompletedExecutionMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CompletedExecutionRepositoryImpl @Inject constructor(
    private val completedExecutionDao: CompletedExecutionDao
) : CompletedExecutionRepository {

    override fun getAll(): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getAllCompletedExecutions().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getByRecordId(recordId: String): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getByRecordId(recordId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getActiveByRecordId(recordId: String): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getActiveByRecordId(recordId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getByCompletionEventId(completionEventId: String): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getByCompletionEventId(completionEventId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun getActiveByCompletionEventId(completionEventId: String): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getActiveByCompletionEventId(completionEventId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun append(executions: List<CompletedExecution>) {
        completedExecutionDao.insertAll(executions.map { it.toEntity() })
    }

    override suspend fun deleteByRecordId(recordId: String) {
        completedExecutionDao.deleteByRecordId(recordId)
    }

    override suspend fun markUndoneByRecordId(recordId: String, undoneAtMillis: Long, undoReason: String) {
        completedExecutionDao.markUndoneByRecordId(recordId, undoneAtMillis, undoReason)
    }

    override suspend fun markUndoneByCompletionEventId(
        completionEventId: String,
        undoneAtMillis: Long,
        undoReason: String
    ) {
        completedExecutionDao.markUndoneByCompletionEventId(completionEventId, undoneAtMillis, undoReason)
    }

    override fun getUndoable(currentTimeMillis: Long): Flow<List<CompletedExecution>> {
        return completedExecutionDao.getUndoableExecutions(currentTimeMillis).map { entities ->
            entities.map { it.toDomain() }
        }
    }
}
