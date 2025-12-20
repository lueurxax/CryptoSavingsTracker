package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import javax.inject.Inject

/**
 * Use case to delete a transaction.
 */
class DeleteTransactionUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository
) {
    /**
     * Delete a transaction by ID
     */
    suspend operator fun invoke(id: String) {
        transactionRepository.deleteTransaction(id)
    }

    /**
     * Delete a transaction object
     */
    suspend fun delete(transaction: Transaction) {
        transactionRepository.deleteTransaction(transaction)
    }
}
