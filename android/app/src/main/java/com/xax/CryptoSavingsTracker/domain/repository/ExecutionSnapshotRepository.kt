package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import kotlinx.coroutines.flow.Flow

interface ExecutionSnapshotRepository {
    fun getByRecordId(recordId: String): Flow<List<ExecutionSnapshot>>
    suspend fun replaceForRecord(recordId: String, snapshots: List<ExecutionSnapshot>)
    suspend fun deleteByRecordId(recordId: String)
}

