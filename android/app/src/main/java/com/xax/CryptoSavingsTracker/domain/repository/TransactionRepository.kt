package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Transaction
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for Transaction operations.
 */
interface TransactionRepository {
    /**
     * Get all transactions as a Flow for reactive updates
     */
    fun getAllTransactions(): Flow<List<Transaction>>

    /**
     * Get transactions for a specific asset
     */
    fun getTransactionsByAssetId(assetId: String): Flow<List<Transaction>>

    /**
     * Get a single transaction by ID
     */
    suspend fun getTransactionById(id: String): Transaction?

    /**
     * Get a single transaction by ID as a Flow
     */
    fun getTransactionByIdFlow(id: String): Flow<Transaction?>

    /**
     * Get transaction by external ID (for on-chain transactions)
     */
    suspend fun getTransactionByExternalId(externalId: String): Transaction?

    /**
     * Get transactions in a date range
     */
    fun getTransactionsInRange(
        assetId: String,
        startMillis: Long,
        endMillis: Long
    ): Flow<List<Transaction>>

    /**
     * Get total amount for an asset
     */
    suspend fun getTotalAmountForAsset(assetId: String): Double

    /**
     * Get manual balance for an asset (sum of manual transactions only).
     * Matches iOS Asset.manualBalance calculation.
     */
    suspend fun getManualBalanceForAsset(assetId: String): Double

    /**
     * Get total amount for an asset since a given date
     */
    suspend fun getTotalAmountForAssetSince(assetId: String, startMillis: Long): Double

    /**
     * Insert a new transaction
     */
    suspend fun insertTransaction(transaction: Transaction)

    /**
     * Insert multiple transactions
     */
    suspend fun insertTransactions(transactions: List<Transaction>)

    /**
     * Update an existing transaction
     */
    suspend fun updateTransaction(transaction: Transaction)

    /**
     * Delete a transaction by ID
     */
    suspend fun deleteTransaction(id: String)

    /**
     * Delete a transaction
     */
    suspend fun deleteTransaction(transaction: Transaction)

    /**
     * Get transaction count for an asset
     */
    suspend fun getTransactionCountForAsset(assetId: String): Int
}
