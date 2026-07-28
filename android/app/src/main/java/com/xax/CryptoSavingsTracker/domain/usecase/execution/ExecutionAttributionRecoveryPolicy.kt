package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Allows a bounded escape hatch for legacy executions that the current
 * fail-closed attribution contract can no longer complete safely.
 */
class ExecutionAttributionRecoveryPolicy @Inject constructor(
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository
) {
    suspend fun requiresExpiredUndoRecovery(record: ExecutionRecord): Boolean {
        val startedAtMillis = record.startedAtMillis ?: return true
        if (startedAtMillis <= 0L) return true
        val snapshots = executionSnapshotRepository.getByRecordId(record.id).first()
        if (snapshots.isEmpty()) return true

        val currentAllocations = allocationRepository.getAllAllocationsFlow().first()
        val allocationHistory = allocationHistoryRepository.getAll().first()
        val assets = assetRepository.getAllAssets().first()
        val transactions = transactionRepository.getAllTransactions().first()
        val nowMillis = System.currentTimeMillis()

        return try {
            val requiredAssetIds = ExecutionAttributionScopeValidator.requiredAssetIds(
                goalIds = snapshots.mapTo(hashSetOf()) { it.goalId },
                currentAllocations = currentAllocations,
                allocationHistory = allocationHistory,
                startedAtMillis = startedAtMillis,
                nowMillis = nowMillis
            )
            ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
                requiredAssetIds = requiredAssetIds,
                knownAssetIds = assets.mapTo(hashSetOf()) { it.id },
                addressedAssetIds = assets
                    .asSequence()
                    .filter { !it.address.isNullOrBlank() }
                    .mapTo(hashSetOf()) { it.id },
                onChainTransactionAssetIds = transactions
                    .asSequence()
                    .filter { it.source == TransactionSource.ON_CHAIN }
                    .mapTo(hashSetOf()) { it.assetId }
            )
            ExecutionAttributionScopeValidator.requireCompleteRateMatrix(
                requiredAssetIds = requiredAssetIds,
                snapshotCurrencies = snapshots.mapTo(hashSetOf()) { it.currency.uppercase() },
                assetRates = executionAssetRateRepository.getByRecordId(record.id).first()
            )
            false
        } catch (_: UnprovenExecutionContributionAttributionException) {
            true
        } catch (_: MissingExecutionAssetRateException) {
            true
        }
    }
}
