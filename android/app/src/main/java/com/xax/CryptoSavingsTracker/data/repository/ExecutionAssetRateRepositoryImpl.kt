package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionAssetRateDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionAssetRateEntity
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExecutionAssetRateRepositoryImpl @Inject constructor(
    private val executionAssetRateDao: ExecutionAssetRateDao
) : ExecutionAssetRateRepository {
    override fun getByRecordId(recordId: String): Flow<List<ExecutionAssetRate>> {
        return executionAssetRateDao.getByRecordId(recordId).map { rows ->
            rows.map { row ->
                ExecutionAssetRate(
                    assetId = row.assetId,
                    snapshotCurrency = row.snapshotCurrency,
                    rate = row.rate,
                    capturedAtMillis = row.capturedAtUtcMillis
                )
            }
        }
    }

    override suspend fun replaceForRecord(recordId: String, rates: List<ExecutionAssetRate>) {
        executionAssetRateDao.deleteByRecordId(recordId)
        if (rates.isNotEmpty()) {
            executionAssetRateDao.insertAll(
                rates.map { rate ->
                    ExecutionAssetRateEntity(
                        executionRecordId = recordId,
                        assetId = rate.assetId,
                        snapshotCurrency = rate.snapshotCurrency.uppercase(),
                        rate = rate.rate,
                        capturedAtUtcMillis = rate.capturedAtMillis
                    )
                }
            )
        }
    }

    override suspend fun deleteByRecordId(recordId: String) {
        executionAssetRateDao.deleteByRecordId(recordId)
    }
}
