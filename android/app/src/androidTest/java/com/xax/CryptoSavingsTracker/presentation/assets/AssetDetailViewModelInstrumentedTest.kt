package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionsUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AssetDetailViewModelInstrumentedTest {
    @Test
    fun currentBalance_includesOnChainBalance_whenPresent() = runBlocking {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        val assetRepository = TestAssetRepository(listOf(asset))
        val transactionRepository = TestTransactionRepository()
        val exchangeRateRepository = TestExchangeRateRepository(rate = 100_000.0)
        val onChainBalanceRepository = TestOnChainBalanceRepository(balance = 0.004106)

        val viewModel = AssetDetailViewModel(
            savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
            getAssetByIdUseCase = GetAssetByIdUseCase(assetRepository),
            getTransactionsUseCase = GetTransactionsUseCase(transactionRepository),
            exchangeRateRepository = exchangeRateRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            deleteAssetUseCase = DeleteAssetUseCase(assetRepository)
        )

        val state = withTimeout(2_000) {
            viewModel.uiState
                .filter { it.asset != null && it.currentBalance > 0.0 }
                .first()
        }

        assertEquals(0.004106, state.currentBalance, 0.0000001)
        assertEquals(410.60, state.currentBalanceUsd ?: 0.0, 0.05)
    }

    @Test
    fun currentBalance_sumsManualAndOnChain() = runBlocking {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        val assetRepository = TestAssetRepository(listOf(asset))
        val transactionRepository = TestTransactionRepository()
        transactionRepository.setTransactions(
            listOf(
                Transaction(
                    id = "tx-1",
                    assetId = asset.id,
                    amount = 0.5,
                    dateMillis = 1L,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = 1L
                )
            )
        )

        val viewModel = AssetDetailViewModel(
            savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
            getAssetByIdUseCase = GetAssetByIdUseCase(assetRepository),
            getTransactionsUseCase = GetTransactionsUseCase(transactionRepository),
            exchangeRateRepository = TestExchangeRateRepository(rate = 1.0),
            onChainBalanceRepository = TestOnChainBalanceRepository(balance = 2.0),
            deleteAssetUseCase = DeleteAssetUseCase(assetRepository)
        )

        val state = withTimeout(2_000) {
            viewModel.uiState
                .filter { it.asset != null && it.currentBalance >= 2.5 }
                .first()
        }

        assertEquals(0.5, state.manualBalance, 0.0000001)
        assertEquals(2.5, state.currentBalance, 0.0000001)
    }

    private class TestAssetRepository(initialAssets: List<Asset>) : AssetRepository {
        private val assets = MutableStateFlow(initialAssets.associateBy { it.id })

        override fun getAllAssets(): Flow<List<Asset>> = assets.map { it.values.toList() }

        override fun getAssetsByCurrency(currency: String): Flow<List<Asset>> =
            assets.map { it.values.filter { asset -> asset.currency.equals(currency, ignoreCase = true) } }

        override suspend fun getAssetById(id: String): Asset? = assets.value[id]

        override fun getAssetByIdFlow(id: String): Flow<Asset?> = assets.map { it[id] }

        override suspend fun getAssetByAddress(address: String): Asset? = assets.value.values.firstOrNull { it.address == address }

        override suspend fun insertAsset(asset: Asset) {
            assets.value = assets.value + (asset.id to asset)
        }

        override suspend fun updateAsset(asset: Asset) {
            assets.value = assets.value + (asset.id to asset)
        }

        override suspend fun deleteAsset(id: String) {
            assets.value = assets.value - id
        }

        override suspend fun deleteAsset(asset: Asset) {
            deleteAsset(asset.id)
        }

        override suspend fun getAssetCount(): Int = assets.value.size
    }

    private class TestTransactionRepository : TransactionRepository {
        private val allTransactions = MutableStateFlow<List<Transaction>>(emptyList())

        fun setTransactions(items: List<Transaction>) {
            allTransactions.value = items
        }

        override fun getAllTransactions(): Flow<List<Transaction>> = allTransactions

        override fun getTransactionsByAssetId(assetId: String): Flow<List<Transaction>> =
            allTransactions.map { it.filter { tx -> tx.assetId == assetId } }

        override suspend fun getTransactionById(id: String): Transaction? = allTransactions.value.firstOrNull { it.id == id }

        override fun getTransactionByIdFlow(id: String): Flow<Transaction?> =
            allTransactions.map { it.firstOrNull { tx -> tx.id == id } }

        override suspend fun getTransactionByExternalId(externalId: String): Transaction? =
            allTransactions.value.firstOrNull { it.externalId == externalId }

        override fun getTransactionsInRange(assetId: String, startMillis: Long, endMillis: Long): Flow<List<Transaction>> =
            getTransactionsByAssetId(assetId).map { txs -> txs.filter { it.dateMillis in startMillis..endMillis } }

        override suspend fun getTotalAmountForAsset(assetId: String): Double =
            allTransactions.value.filter { it.assetId == assetId }.sumOf { it.amount }

        override suspend fun getManualBalanceForAsset(assetId: String): Double =
            allTransactions.value.filter { it.assetId == assetId && it.source == TransactionSource.MANUAL }.sumOf { it.amount }

        override suspend fun getTotalAmountForAssetSince(assetId: String, startMillis: Long): Double =
            allTransactions.value.filter { it.assetId == assetId && it.dateMillis >= startMillis }.sumOf { it.amount }

        override suspend fun insertTransaction(transaction: Transaction) {
            allTransactions.value = allTransactions.value + transaction
        }

        override suspend fun insertTransactions(transactions: List<Transaction>) {
            allTransactions.value = allTransactions.value + transactions
        }

        override suspend fun updateTransaction(transaction: Transaction) {
            allTransactions.value = allTransactions.value.map { if (it.id == transaction.id) transaction else it }
        }

        override suspend fun deleteTransaction(id: String) {
            allTransactions.value = allTransactions.value.filterNot { it.id == id }
        }

        override suspend fun deleteTransaction(transaction: Transaction) {
            deleteTransaction(transaction.id)
        }

        override suspend fun getTransactionCountForAsset(assetId: String): Int =
            allTransactions.value.count { it.assetId == assetId }
    }

    private class TestOnChainBalanceRepository(private val balance: Double) : OnChainBalanceRepository {
        override suspend fun getBalance(asset: Asset, forceRefresh: Boolean): Result<OnChainBalance> {
            return Result.success(
                OnChainBalance(
                    assetId = asset.id,
                    chainId = asset.chainId ?: "unknown",
                    address = asset.address ?: "unknown",
                    currency = asset.currency,
                    balance = balance,
                    fetchedAtMillis = System.currentTimeMillis(),
                    isStale = false
                )
            )
        }

        override suspend fun clearCache() = Unit
    }

    private class TestExchangeRateRepository(private val rate: Double) : ExchangeRateRepository {
        override suspend fun fetchRate(from: String, to: String): Double = rate
        override fun hasValidConfiguration(): Boolean = true
        override suspend fun clearCache() = Unit
    }
}

