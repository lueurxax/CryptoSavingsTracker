package com.xax.CryptoSavingsTracker.presentation.assets

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AssetListBalanceCompletenessTest {
    @Test
    fun `asset source failure remains hard and retry resubscribes for fresh data`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val asset = Asset(
                id = "asset-1",
                currency = "USD",
                address = null,
                chainId = null,
                createdAt = 1L,
                updatedAt = 1L
            )
            val getAssets = mockk<GetAssetsUseCase>()
            val transactions = mockk<TransactionRepository>()
            val rates = mockk<ExchangeRateRepository>()
            var assetSubscriptions = 0

            every { getAssets() } returns flow {
                assetSubscriptions += 1
                if (assetSubscriptions == 1) {
                    throw IllegalStateException("asset database offline")
                }
                emit(listOf(asset))
            }
            every { transactions.getAllTransactions() } returns flowOf(
                listOf(
                    Transaction(
                        id = "transaction-1",
                        assetId = asset.id,
                        amount = 5.0,
                        dateMillis = 1L,
                        source = TransactionSource.MANUAL,
                        externalId = null,
                        counterparty = null,
                        comment = null,
                        createdAt = 1L
                    )
                )
            )
            coEvery { rates.fetchRate("USD", "USD") } returns 1.0

            val viewModel = AssetListViewModel(
                getAssetsUseCase = getAssets,
                transactionRepository = transactions,
                exchangeRateRepository = rates,
                onChainBalanceRepository = mockk(relaxed = true),
                deleteAssetUseCase = mockk(relaxed = true)
            )
            advanceUntilIdle()

            val failedState = viewModel.uiState.value
            assertThat(failedState.isLoading).isFalse()
            assertThat(failedState.assets).isEmpty()
            assertThat(failedState.error?.lowercase()).contains("asset")
            assertThat(failedState.sourceFailure?.lowercase()).contains("asset")

            viewModel.clearError()
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.error?.lowercase()).contains("asset")

            viewModel.retry()
            advanceUntilIdle()

            val recoveredState = viewModel.uiState.value
            assertThat(assetSubscriptions).isEqualTo(2)
            assertThat(recoveredState.error).isNull()
            assertThat(recoveredState.assets.single().totalBalance).isEqualTo(5.0)
            assertThat(recoveredState.assets.single().usdValue).isEqualTo(5.0)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `addressed provider failure does not publish manual only total or USD value`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val asset = Asset(
                id = "asset-1",
                currency = "BTC",
                address = "bc1qwallet",
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )
            val manual = Transaction(
                id = "transaction-1",
                assetId = asset.id,
                amount = 5.0,
                dateMillis = 1L,
                source = TransactionSource.MANUAL,
                externalId = null,
                counterparty = null,
                comment = null,
                createdAt = 1L
            )
            val getAssets = mockk<GetAssetsUseCase>()
            val transactions = mockk<TransactionRepository>()
            val rates = mockk<ExchangeRateRepository>()
            val balances = mockk<OnChainBalanceRepository>()

            every { getAssets() } returns flowOf(listOf(asset))
            every { transactions.getAllTransactions() } returns flowOf(listOf(manual))
            coEvery { rates.fetchRate("BTC", "USD") } returns 100_000.0
            coEvery { balances.getBalance(asset, forceRefresh = false) } returns
                Result.failure(IllegalStateException("provider offline"))

            val viewModel = AssetListViewModel(
                getAssetsUseCase = getAssets,
                transactionRepository = transactions,
                exchangeRateRepository = rates,
                onChainBalanceRepository = balances,
                deleteAssetUseCase = mockk<DeleteAssetUseCase>(relaxed = true)
            )
            advanceUntilIdle()

            val item = viewModel.uiState.value.assets.single()
            assertThat(item.manualBalance).isEqualTo(5.0)
            assertThat(item.totalBalance).isNull()
            assertThat(item.usdValue).isNull()
            assertThat(item.balanceIssue).contains("Refresh")
        } finally {
            Dispatchers.resetMain()
        }
    }
}
