package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionWritePolicy
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import javax.inject.Inject

/**
 * Use case to update an existing transaction.
 */
class UpdateTransactionUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository
) {
    /**
     * Update a transaction
     */
    suspend operator fun invoke(transaction: Transaction) {
        val original = transactionRepository.getTransactionById(transaction.id)
            ?: throw IllegalStateException("Transaction not found")
        TransactionWritePolicy.requireMetadataOnlyUpdate(
            original = original,
            candidate = transaction
        )
        transactionRepository.updateTransaction(
            TransactionWritePolicy.normalizeForPersistence(transaction)
        )
    }
}
