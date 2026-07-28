package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DashboardForceRefreshTest {
    private val mainDispatcher = StandardTestDispatcher()

    @BeforeEach
    fun setUpMainDispatcher() {
        Dispatchers.setMain(mainDispatcher)
    }

    @AfterEach
    fun resetMainDispatcher() {
        Dispatchers.resetMain()
    }

    @Test
    fun `explicit refresh forces balances and invalidates FX cache exactly once`() = runTest {
        val asset = addressedAsset()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()
        val rateCalls = AtomicInteger(0)

        coEvery { balances.getBalance(asset, forceRefresh = false) } returns
            Result.success(providerBalance(asset, 1.0))
        coEvery { balances.getBalance(asset, forceRefresh = true) } returns
            Result.success(providerBalance(asset, 2.0))
        coEvery { rates.fetchRate("BTC", "USD") } answers {
            if (rateCalls.incrementAndGet() == 1) 10.0 else 20.0
        }
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(asset, balances, rates)
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.totalUsd).isEqualTo(10.0)

        viewModel.refresh()
        advanceUntilIdle()

        assertThat(viewModel.uiState.value.totalUsd).isEqualTo(40.0)
        coVerify(exactly = 1) { rates.clearCache() }
        coVerify(exactly = 1) { balances.getBalance(asset, forceRefresh = true) }
        assertThat(rateCalls.get()).isEqualTo(2)
    }

    @Test
    fun `later explicit refresh can complete while an uncancellable older refresh is pending`() = runTest {
        val asset = addressedAsset()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()
        val forcedCalls = AtomicInteger(0)
        val firstStarted = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()
        val firstResult = CompletableDeferred<OnChainBalance>()
        val secondResult = CompletableDeferred<OnChainBalance>()

        coEvery { balances.getBalance(asset, forceRefresh = false) } returns
            Result.success(providerBalance(asset, 0.0))
        coEvery { balances.getBalance(asset, forceRefresh = true) } coAnswers {
            when (forcedCalls.incrementAndGet()) {
                1 -> withContext(NonCancellable) {
                    firstStarted.complete(Unit)
                    Result.success(firstResult.await())
                }
                2 -> {
                    secondStarted.complete(Unit)
                    Result.success(secondResult.await())
                }
                else -> error("Unexpected forced balance request")
            }
        }
        coEvery { rates.fetchRate("BTC", "USD") } returns 1.0
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(asset, balances, rates)
        advanceUntilIdle()

        try {
            viewModel.refresh()
            runCurrent()
            assertThat(firstStarted.isCompleted).isTrue()

            viewModel.refresh()
            runCurrent()
            assertThat(secondStarted.isCompleted).isTrue()

            secondResult.complete(providerBalance(asset, 20.0))
            runCurrent()
            assertThat(viewModel.uiState.value.totalUsd).isEqualTo(20.0)

            firstResult.complete(providerBalance(asset, 10.0))
            advanceUntilIdle()
            assertThat(viewModel.uiState.value.totalUsd).isEqualTo(20.0)
        } finally {
            firstResult.complete(providerBalance(asset, 10.0))
            secondResult.complete(providerBalance(asset, 20.0))
            runCurrent()
        }
    }

    @Test
    fun `reactive input recompute reuses balance and FX caches`() = runTest {
        val asset = addressedAsset()
        val transactionFlow = MutableStateFlow<List<Transaction>>(emptyList())
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()

        coEvery { balances.getBalance(asset, forceRefresh = false) } returns
            Result.success(providerBalance(asset, 1.0))
        coEvery { rates.fetchRate("BTC", "USD") } returns 10.0
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(
            asset = asset,
            balances = balances,
            rates = rates,
            transactionFlow = transactionFlow
        )
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.totalUsd).isEqualTo(10.0)

        transactionFlow.value = listOf(manualTransaction(asset.id, amount = 1.0))
        advanceUntilIdle()

        assertThat(viewModel.uiState.value.totalUsd).isEqualTo(20.0)
        coVerify(exactly = 2) { balances.getBalance(asset, forceRefresh = false) }
        coVerify(exactly = 0) { balances.getBalance(asset, forceRefresh = true) }
        coVerify(exactly = 0) { rates.clearCache() }
    }

    private fun viewModel(
        asset: Asset,
        balances: OnChainBalanceRepository,
        rates: ExchangeRateRepository,
        transactionFlow: MutableStateFlow<List<Transaction>> = MutableStateFlow(emptyList())
    ): DashboardViewModel {
        val getAssets = mockk<GetAssetsUseCase>()
        val transactions = mockk<TransactionRepository>()
        val goals = mockk<GetGoalProgressUseCase>()
        every { getAssets() } returns MutableStateFlow(listOf(asset))
        every { transactions.getAllTransactions() } returns transactionFlow
        every { goals() } returns MutableStateFlow(emptyList())
        return DashboardViewModel(
            getAssetsUseCase = getAssets,
            transactionRepository = transactions,
            exchangeRateRepository = rates,
            onChainBalanceRepository = balances,
            getGoalProgressUseCase = goals
        )
    }

    private fun addressedAsset() = Asset(
        id = "asset-1",
        currency = "BTC",
        address = "bc1qwallet",
        chainId = "bitcoin",
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun providerBalance(asset: Asset, balance: Double) = OnChainBalance(
        assetId = asset.id,
        chainId = checkNotNull(asset.chainId),
        address = checkNotNull(asset.address),
        currency = asset.currency,
        balance = balance,
        fetchedAtMillis = System.currentTimeMillis(),
        isStale = false
    )

    private fun manualTransaction(assetId: String, amount: Double) = Transaction(
        id = "transaction-1",
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
