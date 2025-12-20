package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case to get all transactions for an asset.
 */
class GetTransactionsUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository
) {
    /**
     * Get all transactions for a specific asset
     */
    operator fun invoke(assetId: String): Flow<List<Transaction>> {
        return transactionRepository.getTransactionsByAssetId(assetId)
    }

    /**
     * Get all transactions across all assets
     */
    fun all(): Flow<List<Transaction>> {
        return transactionRepository.getAllTransactions()
    }

    /**
     * Get transactions in a date range
     */
    fun inRange(assetId: String, startMillis: Long, endMillis: Long): Flow<List<Transaction>> {
        return transactionRepository.getTransactionsInRange(assetId, startMillis, endMillis)
    }
}
