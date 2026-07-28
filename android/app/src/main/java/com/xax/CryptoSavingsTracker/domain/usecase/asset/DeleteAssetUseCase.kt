package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Use case for deleting an asset
 */
class DeleteAssetUseCase @Inject constructor(
    private val repository: AssetRepository,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    /**
     * Delete an asset by ID
     */
    suspend operator fun invoke(assetId: String): Result<Unit> = runCatching {
        guardedDelete(assetId) {
            repository.deleteAsset(assetId)
        }
    }

    /**
     * Delete an asset
     */
    suspend fun delete(asset: Asset): Result<Unit> = runCatching {
        guardedDelete(asset.id) {
            repository.deleteAsset(asset)
        }
    }

    private suspend fun guardedDelete(
        assetId: String,
        delete: suspend () -> Unit
    ) {
        transactionRunner.run {
            val nowMillis = System.currentTimeMillis()
            val reversibleRecords = executionRecordRepository.getAllRecords().first().filter { record ->
                record.status == ExecutionStatus.EXECUTING ||
                    (record.status == ExecutionStatus.CLOSED && record.canUndo(nowMillis))
            }

            val hasReversibleDependency = reversibleRecords.any { record ->
                val hasCapturedRate = executionAssetRateRepository
                    .getByRecordId(record.id)
                    .first()
                    .any { rate -> rate.assetId == assetId }
                if (hasCapturedRate) {
                    true
                } else if (record.legacyRateSnapshotPending) {
                    val goalIds = executionSnapshotRepository
                        .getByRecordId(record.id)
                        .first()
                        .mapTo(hashSetOf()) { it.goalId }
                    allocationHistoryRepository
                        .getByAssetId(assetId)
                        .first()
                        .any { it.goalId in goalIds }
                } else {
                    false
                }
            }
            check(!hasReversibleDependency) {
                "Asset cannot be deleted while it is needed by a reversible execution"
            }
            delete()
        }
    }
}
