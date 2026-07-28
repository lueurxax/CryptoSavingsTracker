package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
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
class DashboardBalanceCompletenessTest {
    @Test
    fun `asset source failure is a hard error and refresh resubscribes for fresh data`() = runTest {
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
            val goals = mockk<GetGoalProgressUseCase>()
            var assetSubscriptions = 0

            every { getAssets() } returns flow {
                assetSubscriptions += 1
                if (assetSubscriptions == 1) {
                    throw IllegalStateException("asset database offline")
                }
                emit(listOf(asset))
            }
            every { transactions.getAllTransactions() } returns flowOf(
                listOf(manualTransaction(id = "transaction-1", assetId = asset.id, amount = 5.0))
            )
            every { goals() } returns flowOf(emptyList())
            coEvery { rates.fetchRate("USD", "USD") } returns 1.0

            val viewModel = DashboardViewModel(
                getAssetsUseCase = getAssets,
                transactionRepository = transactions,
                exchangeRateRepository = rates,
                onChainBalanceRepository = mockk(relaxed = true),
                getGoalProgressUseCase = goals
            )
            advanceUntilIdle()

            val state = viewModel.uiState.value
            assertThat(state.isLoading).isFalse()
            assertThat(state.totalUsd).isNull()
            assertThat(state.portfolioLast30Days).isEmpty()
            assertThat(state.assets).isEmpty()
            assertThat(state.error?.lowercase()).contains("asset")

            viewModel.refresh()
            advanceUntilIdle()

            val recoveredState = viewModel.uiState.value
            assertThat(assetSubscriptions).isEqualTo(2)
            assertThat(recoveredState.error).isNull()
            assertThat(recoveredState.totalUsd).isEqualTo(5.0)
            assertThat(recoveredState.assets.single().asset.id).isEqualTo(asset.id)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `one unavailable addressed balance suppresses portfolio total and chart`() = runTest {
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
            val goals = mockk<GetGoalProgressUseCase>()

            every { getAssets() } returns flowOf(listOf(asset))
            every { transactions.getAllTransactions() } returns flowOf(listOf(manual))
            every { goals() } returns flowOf(emptyList())
            coEvery { rates.fetchRate("BTC", "USD") } returns 100_000.0
            coEvery { balances.getBalance(asset, forceRefresh = false) } returns
                Result.failure(IllegalStateException("provider offline"))

            val viewModel = DashboardViewModel(
                getAssetsUseCase = getAssets,
                transactionRepository = transactions,
                exchangeRateRepository = rates,
                onChainBalanceRepository = balances,
                getGoalProgressUseCase = goals
            )
            advanceUntilIdle()

            val state = viewModel.uiState.value
            assertThat(state.totalUsd).isNull()
            assertThat(state.portfolioLast30Days).isEmpty()
            assertThat(state.hasUnavailableBalances).isTrue()
            assertThat(state.financialDataIssue).contains("Refresh")
            assertThat(state.assets.single().currentBalance).isNull()
            assertThat(state.assets.single().usdValue).isNull()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `one missing exchange rate suppresses mixed portfolio total instead of publishing partial sum`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val btc = Asset(
                id = "btc",
                currency = "BTC",
                address = null,
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )
            val eur = Asset(
                id = "eur",
                currency = "EUR",
                address = null,
                chainId = null,
                createdAt = 1L,
                updatedAt = 1L
            )
            val transactionsList = listOf(
                manualTransaction(id = "btc-tx", assetId = btc.id, amount = 1.0),
                manualTransaction(id = "eur-tx", assetId = eur.id, amount = 10.0)
            )
            val getAssets = mockk<GetAssetsUseCase>()
            val transactions = mockk<TransactionRepository>()
            val rates = mockk<ExchangeRateRepository>()
            val goals = mockk<GetGoalProgressUseCase>()

            every { getAssets() } returns flowOf(listOf(btc, eur))
            every { transactions.getAllTransactions() } returns flowOf(transactionsList)
            every { goals() } returns flowOf(emptyList())
            coEvery { rates.fetchRate("BTC", "USD") } returns 100_000.0
            coEvery { rates.fetchRate("EUR", "USD") } throws IllegalStateException("rate offline")

            val viewModel = DashboardViewModel(
                getAssetsUseCase = getAssets,
                transactionRepository = transactions,
                exchangeRateRepository = rates,
                onChainBalanceRepository = mockk(relaxed = true),
                getGoalProgressUseCase = goals
            )
            advanceUntilIdle()

            val state = viewModel.uiState.value
            assertThat(state.totalUsd).isNull()
            assertThat(state.hasMissingUsdRates).isTrue()
            assertThat(state.portfolioLast30Days).isEmpty()
            assertThat(state.assets.first { it.asset.id == "btc" }.usdValue).isEqualTo(100_000.0)
            assertThat(state.assets.first { it.asset.id == "eur" }.usdValue).isNull()
        } finally {
            Dispatchers.resetMain()
        }
    }

    private fun manualTransaction(id: String, assetId: String, amount: Double) = Transaction(
        id = id,
        assetId = assetId,
        amount = amount,
        dateMillis = 1L,
        source = TransactionSource.MANUAL,
        externalId = null,
        counterparty = null,
        comment = null,
        createdAt = 1L
    )
}
