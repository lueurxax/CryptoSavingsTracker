package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AssetProviderIdentity
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.model.TransactionWritePolicy
import com.xax.CryptoSavingsTracker.domain.model.providerIdentity
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import java.util.UUID
import javax.inject.Inject
import kotlin.math.abs

/**
 * Use case to add a new transaction.
 */
class AddTransactionUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService,
    private val assetRepository: AssetRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    /**
     * Add a new transaction
     */
    suspend operator fun invoke(transaction: Transaction) {
        val normalizedTransaction = TransactionWritePolicy.normalizeForPersistence(transaction)
        val autoAllocation = resolveAutoAllocationCandidate(
            assetId = normalizedTransaction.assetId,
            transactionAmount = normalizedTransaction.amount,
            transactionDateMillis = normalizedTransaction.dateMillis
        )

        transactionRunner.run {
            if (autoAllocation != null) {
                verifyAutoAllocationPreconditions(
                    assetId = normalizedTransaction.assetId,
                    candidate = autoAllocation
                )
            }

            transactionRepository.insertTransaction(normalizedTransaction)

            if (autoAllocation != null) {
                applyAutoAllocation(
                    allocation = autoAllocation.allocation,
                    newTargetAmount = autoAllocation.newTargetAmount,
                    timestampMillis = normalizedTransaction.dateMillis
                )
            }
        }
    }

    /**
     * Add multiple transactions (for batch import)
     */
    suspend fun batch(transactions: List<Transaction>) {
        for (transaction in transactions) {
            invoke(transaction)
        }
    }

    /**
     * Create and add a new transaction with generated ID
     */
    suspend fun create(
        assetId: String,
        amount: Double,
        dateMillis: Long,
        source: TransactionSource = TransactionSource.MANUAL,
        externalId: String? = null,
        counterparty: String? = null,
        comment: String? = null
    ): Transaction {
        val now = System.currentTimeMillis()
        val transaction = TransactionWritePolicy.normalizeForPersistence(
            Transaction(
                id = UUID.randomUUID().toString(),
                assetId = assetId,
                amount = amount,
                dateMillis = dateMillis,
                source = source,
                externalId = externalId,
                counterparty = counterparty,
                comment = comment,
                createdAt = now
            ),
            nowMillis = now
        )
        invoke(transaction)
        return transaction
    }

    private data class AutoAllocationCandidate(
        val providerIdentity: AssetProviderIdentity,
        val allocation: Allocation,
        val manualBalanceBefore: Double,
        val newTargetAmount: Double
    )

    /**
     * Rule 1 (CONTRIBUTION_TRACKING_REDESIGN.md):
     * If the asset is 100% allocated to exactly one goal (no unallocated portion),
     * then a new transaction automatically adjusts that allocation target so the asset remains fully allocated.
     */
    private suspend fun resolveAutoAllocationCandidate(
        assetId: String,
        transactionAmount: Double,
        transactionDateMillis: Long
    ): AutoAllocationCandidate? {
        val asset = assetRepository.getAssetById(assetId) ?: return null
        val allocations = allocationRepository.getAllocationsForAsset(assetId).filter { it.amount > 0.0 }
        if (allocations.size != 1) return null
        val allocation = allocations.single()
        if (
            allocationHistoryService.hasEvidenceNewerThan(
                assetId = allocation.assetId,
                goalId = allocation.goalId,
                timestampMillis = transactionDateMillis
            )
        ) {
            return null
        }

        val manualBefore = transactionRepository.getManualBalanceForAsset(assetId)
        val balanceBefore = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = manualBefore,
            repository = onChainBalanceRepository,
            forceRefresh = false
        ).requireTotalBalance()

        val totalAllocated = allocations.sumOf { it.amount }
        val isFullyAllocated = abs(balanceBefore - totalAllocated) <= 0.0000001
        if (!isFullyAllocated) return null

        val newTargetAmount = allocation.amount + transactionAmount
        require(newTargetAmount.isFinite()) {
            "Automatic allocation amount overflow"
        }
        return AutoAllocationCandidate(
            providerIdentity = asset.providerIdentity(),
            allocation = allocation,
            manualBalanceBefore = manualBefore,
            newTargetAmount = newTargetAmount
        )
    }

    private suspend fun verifyAutoAllocationPreconditions(
        assetId: String,
        candidate: AutoAllocationCandidate
    ) {
        val currentAsset = assetRepository.getAssetById(assetId)
        check(currentAsset != null && currentAsset.providerIdentity() == candidate.providerIdentity) {
            "Asset provider identity changed while preparing the transaction"
        }

        val currentAllocations = allocationRepository
            .getAllocationsForAsset(assetId)
            .filter { it.amount > 0.0 }
        check(
            currentAllocations.size == 1 &&
                currentAllocations.single() == candidate.allocation
        ) {
            "Asset allocation changed while preparing the transaction"
        }

        val currentManualBalance = transactionRepository.getManualBalanceForAsset(assetId)
        check(currentManualBalance.toBits() == candidate.manualBalanceBefore.toBits()) {
            "Asset manual balance changed while preparing the transaction"
        }
    }

    private suspend fun applyAutoAllocation(
        allocation: Allocation,
        newTargetAmount: Double,
        timestampMillis: Long
    ) {
        if (newTargetAmount > 0.0) {
            val now = System.currentTimeMillis()
            val existing = checkNotNull(
                allocationRepository.getAllocationById(allocation.id)
            ) {
                "Asset allocation changed while committing the transaction"
            }
            check(existing == allocation) {
                "Asset allocation changed while committing the transaction"
            }
            val updated = allocation.copy(
                amount = newTargetAmount,
                lastModifiedAt = now
            )
            allocationRepository.upsertAllocation(updated)
            allocationHistoryService.createSnapshot(updated, timestampMillis = timestampMillis)
        } else {
            val existing = allocationRepository.getAllocationById(allocation.id)
            check(existing == allocation) {
                "Asset allocation changed while committing the transaction"
            }
            allocationRepository.deleteAllocation(allocation.id)
            allocationHistoryService.createDeletionSnapshot(
                assetId = allocation.assetId,
                goalId = allocation.goalId,
                timestampMillis = timestampMillis
            )
        }
    }

}
