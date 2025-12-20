package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionSnapshotDao
import com.xax.CryptoSavingsTracker.data.repository.ExecutionSnapshotMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.ExecutionSnapshotMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExecutionSnapshotRepositoryImpl @Inject constructor(
    private val executionSnapshotDao: ExecutionSnapshotDao
) : ExecutionSnapshotRepository {

    override fun getByRecordId(recordId: String): Flow<List<ExecutionSnapshot>> {
        return executionSnapshotDao.getSnapshotsByRecordId(recordId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun replaceForRecord(recordId: String, snapshots: List<ExecutionSnapshot>) {
        executionSnapshotDao.deleteByRecordId(recordId)
        executionSnapshotDao.insertAll(snapshots.map { it.toEntity() })
    }

    override suspend fun deleteByRecordId(recordId: String) {
        executionSnapshotDao.deleteByRecordId(recordId)
    }
}

