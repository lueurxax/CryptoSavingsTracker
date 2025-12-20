package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case to get a transaction by ID.
 */
class GetTransactionByIdUseCase @Inject constructor(
    private val transactionRepository: TransactionRepository
) {
    /**
     * Get a transaction by ID (suspend)
     */
    suspend operator fun invoke(id: String): Transaction? {
        return transactionRepository.getTransactionById(id)
    }

    /**
     * Get a transaction by ID as a Flow
     */
    fun asFlow(id: String): Flow<Transaction?> {
        return transactionRepository.getTransactionByIdFlow(id)
    }

    /**
     * Get a transaction by external ID (for on-chain transactions)
     */
    suspend fun byExternalId(externalId: String): Transaction? {
        return transactionRepository.getTransactionByExternalId(externalId)
    }
}
