package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.hasSameProviderIdentityAs
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Use case for updating an existing asset
 */
class UpdateAssetUseCase @Inject constructor(
    private val repository: AssetRepository,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner,
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository
) {
    /**
     * Update an asset with new values
     */
    suspend operator fun invoke(asset: Asset): Result<Asset> = runCatching {
        val normalized = AddressedAssetRoutePolicy.normalize(
            currency = asset.currency,
            address = asset.address,
            chainId = asset.chainId
        )
        val normalizedAsset = asset.copy(
            currency = normalized.currency,
            address = normalized.address,
            chainId = normalized.chainId
        )

        transactionRunner.run {
            val storedAsset = checkNotNull(repository.getAssetById(normalizedAsset.id)) {
                "Asset no longer exists"
            }
            val providerIdentityChanged =
                !storedAsset.hasSameProviderIdentityAs(normalizedAsset)
            if (providerIdentityChanged) {
                val hasDependentFinancialGraph =
                    transactionRepository.getTransactionCountForAsset(normalizedAsset.id) > 0 ||
                        allocationRepository
                            .getAllocationsForAsset(normalizedAsset.id)
                            .isNotEmpty() ||
                        allocationHistoryRepository
                            .getByAssetId(normalizedAsset.id)
                            .first()
                            .isNotEmpty()
                check(!hasDependentFinancialGraph) {
                    "Asset currency, network, or address cannot be changed after dependent financial activity exists"
                }

                val nowMillis = System.currentTimeMillis()
                val reversibleRecords = executionRecordRepository.getAllRecords().first().filter { record ->
                    record.status == ExecutionStatus.EXECUTING ||
                        (record.status == ExecutionStatus.CLOSED && record.canUndo(nowMillis))
                }
                val isSnapshotted = reversibleRecords.any { it.legacyRateSnapshotPending } ||
                    reversibleRecords.any { record ->
                        executionAssetRateRepository
                            .getByRecordId(record.id)
                            .first()
                            .any { it.assetId == normalizedAsset.id }
                    }
                check(!isSnapshotted) {
                    "Asset provider identity cannot be changed during a reversible execution"
                }
            }

            if (normalizedAsset.address != null) {
                val existingAsset = repository.getAssetByOnChainIdentity(
                    address = normalizedAsset.address,
                    chainId = checkNotNull(normalizedAsset.chainId),
                    currency = normalizedAsset.currency
                )
                if (existingAsset != null && existingAsset.id != normalizedAsset.id) {
                    throw IllegalArgumentException(
                        "This wallet is already tracked for ${normalizedAsset.currency} " +
                            "on ${normalizedAsset.chainId}"
                    )
                }
            }

            val updatedAsset = normalizedAsset.copy(updatedAt = System.currentTimeMillis())
            repository.updateAsset(updatedAsset)
            updatedAsset
        }
    }
}
