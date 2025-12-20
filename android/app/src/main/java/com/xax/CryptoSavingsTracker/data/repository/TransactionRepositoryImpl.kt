package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.TransactionDao
import com.xax.CryptoSavingsTracker.data.repository.TransactionMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.TransactionMapper.toDomainList
import com.xax.CryptoSavingsTracker.data.repository.TransactionMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of TransactionRepository using Room database.
 */
@Singleton
class TransactionRepositoryImpl @Inject constructor(
    private val transactionDao: TransactionDao
) : TransactionRepository {

    override fun getAllTransactions(): Flow<List<Transaction>> {
        return transactionDao.getAllTransactions().map { entities ->
            entities.toDomainList()
        }
    }

    override fun getTransactionsByAssetId(assetId: String): Flow<List<Transaction>> {
        return transactionDao.getTransactionsByAssetId(assetId).map { entities ->
            entities.toDomainList()
        }
    }

    override suspend fun getTransactionById(id: String): Transaction? {
        return transactionDao.getTransactionByIdOnce(id)?.toDomain()
    }

    override fun getTransactionByIdFlow(id: String): Flow<Transaction?> {
        return transactionDao.getTransactionById(id).map { entity ->
            entity?.toDomain()
        }
    }

    override suspend fun getTransactionByExternalId(externalId: String): Transaction? {
        return transactionDao.getTransactionByExternalId(externalId)?.toDomain()
    }

    override fun getTransactionsInRange(
        assetId: String,
        startMillis: Long,
        endMillis: Long
    ): Flow<List<Transaction>> {
        return transactionDao.getTransactionsInRange(assetId, startMillis, endMillis).map { entities ->
            entities.toDomainList()
        }
    }

    override suspend fun getTotalAmountForAsset(assetId: String): Double {
        return transactionDao.getTotalAmountForAsset(assetId) ?: 0.0
    }

    override suspend fun getManualBalanceForAsset(assetId: String): Double {
        return transactionDao.getManualBalanceForAsset(assetId) ?: 0.0
    }

    override suspend fun getTotalAmountForAssetSince(assetId: String, startMillis: Long): Double {
        return transactionDao.getTotalAmountForAssetSince(assetId, startMillis) ?: 0.0
    }

    override suspend fun insertTransaction(transaction: Transaction) {
        transactionDao.insert(transaction.toEntity())
    }

    override suspend fun insertTransactions(transactions: List<Transaction>) {
        transactionDao.insertAll(transactions.map { it.toEntity() })
    }

    override suspend fun updateTransaction(transaction: Transaction) {
        transactionDao.update(transaction.toEntity())
    }

    override suspend fun deleteTransaction(id: String) {
        transactionDao.deleteById(id)
    }

    override suspend fun deleteTransaction(transaction: Transaction) {
        transactionDao.delete(transaction.toEntity())
    }

    override suspend fun getTransactionCountForAsset(assetId: String): Int {
        return transactionDao.getTransactionCountForAsset(assetId)
    }
}
