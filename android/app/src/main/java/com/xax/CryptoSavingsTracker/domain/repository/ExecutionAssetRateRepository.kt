package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import kotlinx.coroutines.flow.Flow

interface ExecutionAssetRateRepository {
    fun getByRecordId(recordId: String): Flow<List<ExecutionAssetRate>>
    suspend fun replaceForRecord(recordId: String, rates: List<ExecutionAssetRate>)
    suspend fun deleteByRecordId(recordId: String)
}
