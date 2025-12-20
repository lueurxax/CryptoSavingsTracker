package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import java.util.UUID
import javax.inject.Inject

/**
 * Use case to add a new transaction.
 */
class AddTransactionUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository
) {
    /**
     * Add a new transaction
     */
    suspend operator fun invoke(transaction: Transaction) {
        transactionRepository.insertTransaction(transaction)
    }

    /**
     * Add multiple transactions (for batch import)
     */
    suspend fun batch(transactions: List<Transaction>) {
        transactionRepository.insertTransactions(transactions)
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
        transactionRepository.insertTransaction(transaction)
        return transaction
    }
}
