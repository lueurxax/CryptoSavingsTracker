package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import java.util.UUID
import javax.inject.Inject
import kotlin.math.abs

/**
 * Use case to add a new transaction.
 */
class AddTransactionUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService
) {
    /**
     * Add a new transaction
     */
    suspend operator fun invoke(transaction: Transaction) {
        val autoAllocation = resolveAutoAllocationCandidate(
            assetId = transaction.assetId,
            transactionAmount = transaction.amount
        )

        transactionRepository.insertTransaction(transaction)

        if (autoAllocation != null) {
            applyAutoAllocation(
                allocationId = autoAllocation.allocationId,
                assetId = transaction.assetId,
                goalId = autoAllocation.goalId,
                newTargetAmount = autoAllocation.newTargetAmount,
                timestampMillis = transaction.dateMillis
            )
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
        val transaction = Transaction(
            id = UUID.randomUUID().toString(),
            assetId = assetId,
            amount = amount,
            dateMillis = dateMillis,
            source = source,
            externalId = externalId,
            counterparty = counterparty,
            comment = comment,
            createdAt = now
        )
        invoke(transaction)
        return transaction
    }

    private data class AutoAllocationCandidate(
        val allocationId: String,
        val goalId: String,
        val newTargetAmount: Double
    )

    /**
     * Rule 1 (CONTRIBUTION_TRACKING_REDESIGN.md):
     * If the asset is 100% allocated to exactly one goal (no unallocated portion),
     * then a new transaction automatically adjusts that allocation target so the asset remains fully allocated.
     */
    private suspend fun resolveAutoAllocationCandidate(
        assetId: String,
        transactionAmount: Double
    ): AutoAllocationCandidate? {
        val balanceBefore = transactionRepository.getManualBalanceForAsset(assetId)
        val allocations = allocationRepository.getAllocationsForAsset(assetId).filter { it.amount > 0.0 }
        if (allocations.size != 1) return null

        val totalAllocated = allocations.sumOf { it.amount }
        val isFullyAllocated = abs(balanceBefore - totalAllocated) <= 0.0000001
        if (!isFullyAllocated) return null

        val allocation = allocations.first()
        return AutoAllocationCandidate(
            allocationId = allocation.id,
            goalId = allocation.goalId,
            newTargetAmount = allocation.amount + transactionAmount
        )
    }

    private suspend fun applyAutoAllocation(
        allocationId: String,
        assetId: String,
        goalId: String,
        newTargetAmount: Double,
        timestampMillis: Long
    ) {
        if (newTargetAmount > 0.0) {
            val now = System.currentTimeMillis()
            val existing = allocationRepository.getAllocationById(allocationId) ?: return
            val updated = existing.copy(
                amount = newTargetAmount,
                lastModifiedAt = now
            )
            allocationRepository.upsertAllocation(updated)
            allocationHistoryService.createSnapshot(updated, timestampMillis = timestampMillis)
        } else {
            allocationRepository.deleteAllocation(allocationId)
            allocationHistoryService.createDeletionSnapshot(assetId = assetId, goalId = goalId, timestampMillis = timestampMillis)
        }
    }
}
