package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainTransactionRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionsUseCase
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AssetDetailLatestRequestWinsTest {
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
    fun `forced provider refresh wins when initial request completes last`() = runTest {
        val asset = addressedAsset()
        val initialStarted = CompletableDeferred<Unit>()
        val forcedStarted = CompletableDeferred<Unit>()
        val initialResult = CompletableDeferred<Result<OnChainBalance>>()
        val forcedResult = CompletableDeferred<Result<OnChainBalance>>()
        val balances = mockk<OnChainBalanceRepository>()

        coEvery { balances.getBalance(asset, forceRefresh = false) } coAnswers {
            initialStarted.complete(Unit)
            initialResult.await()
        }
        coEvery { balances.getBalance(asset, forceRefresh = true) } coAnswers {
            forcedStarted.complete(Unit)
            forcedResult.await()
        }

        val viewModel = viewModel(
            asset = asset,
            transactions = emptyList(),
            balances = balances,
            rates = immediateRates(1.0)
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        runCurrent()
        initialStarted.await()

        viewModel.refreshOnChainBalance()
        runCurrent()
        forcedStarted.await()

        forcedResult.complete(Result.success(providerBalance(asset, balance = 20.0)))
        runCurrent()
        assertThat(viewModel.uiState.value.onChainBalance?.balance).isEqualTo(20.0)

        initialResult.complete(Result.success(providerBalance(asset, balance = 10.0)))
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.onChainBalance?.balance).isEqualTo(20.0)
        assertThat(state.currentBalance).isEqualTo(20.0)
        assertThat(state.currentBalanceUsd).isEqualTo(20.0)
        assertThat(state.isOnChainLoading).isFalse()
        assertThat(state.onChainError).isNull()
    }

    @Test
    fun `forced USD refresh wins when cached quote completes last`() = runTest {
        val asset = manualAsset()
        val transaction = manualTransaction(asset.id, amount = 2.0)
        val initialStarted = CompletableDeferred<Unit>()
        val forcedStarted = CompletableDeferred<Unit>()
        val initialRate = CompletableDeferred<Double>()
        val forcedRate = CompletableDeferred<Double>()
        val calls = AtomicInteger(0)
        val rates = mockk<ExchangeRateRepository>()

        coEvery { rates.fetchRate("BTC", "USD") } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> {
                    initialStarted.complete(Unit)
                    initialRate.await()
                }
                2 -> {
                    forcedStarted.complete(Unit)
                    forcedRate.await()
                }
                else -> error("Unexpected rate request")
            }
        }
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(
            asset = asset,
            transactions = listOf(transaction),
            balances = mockk(relaxed = true),
            rates = rates
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        runCurrent()
        initialStarted.await()

        viewModel.refreshUsdBalance()
        runCurrent()
        forcedStarted.await()

        forcedRate.complete(20.0)
        runCurrent()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isEqualTo(40.0)

        initialRate.complete(10.0)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.currentBalanceUsd).isEqualTo(40.0)
        assertThat(state.isUsdLoading).isFalse()
        assertThat(state.usdError).isNull()
    }

    @Test
    fun `reactive emission cannot supersede an in flight forced USD refresh`() = runTest {
        val asset = manualAsset()
        val transaction = manualTransaction(asset.id, amount = 2.0)
        val transactionFlow = MutableStateFlow<List<Transaction>>(listOf(transaction))
        val forcedStarted = CompletableDeferred<Unit>()
        val forcedRate = CompletableDeferred<Double>()
        val calls = AtomicInteger(0)
        val rates = mockk<ExchangeRateRepository>()

        coEvery { rates.fetchRate("BTC", "USD") } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> 10.0
                2 -> {
                    forcedStarted.complete(Unit)
                    forcedRate.await()
                }
                3 -> 10.0
                else -> error("Unexpected rate request")
            }
        }
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(
            asset = asset,
            transactions = listOf(transaction),
            transactionFlow = transactionFlow,
            balances = mockk(relaxed = true),
            rates = rates
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isEqualTo(20.0)

        viewModel.refreshUsdBalance()
        runCurrent()
        forcedStarted.await()

        transactionFlow.value = listOf(transaction, onChainTransaction(asset.id))
        runCurrent()

        forcedRate.complete(20.0)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.currentBalanceUsd).isEqualTo(40.0)
        assertThat(state.isUsdLoading).isFalse()
        assertThat(state.usdError).isNull()
        assertThat(calls.get()).isEqualTo(2)
    }

    @Test
    fun `changed balance waits for an in flight forced USD refresh`() = runTest {
        val asset = manualAsset()
        val firstTransaction = manualTransaction(asset.id, amount = 2.0)
        val transactionFlow = MutableStateFlow<List<Transaction>>(listOf(firstTransaction))
        val forcedStarted = CompletableDeferred<Unit>()
        val forcedRate = CompletableDeferred<Double>()
        val calls = AtomicInteger(0)
        val rates = mockk<ExchangeRateRepository>()

        coEvery { rates.fetchRate("BTC", "USD") } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> 10.0
                2 -> {
                    forcedStarted.complete(Unit)
                    forcedRate.await()
                }
                3 -> 20.0
                else -> error("Unexpected rate request")
            }
        }
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(
            asset = asset,
            transactions = listOf(firstTransaction),
            transactionFlow = transactionFlow,
            balances = mockk(relaxed = true),
            rates = rates
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isEqualTo(20.0)

        viewModel.refreshUsdBalance()
        runCurrent()
        forcedStarted.await()

        transactionFlow.value = listOf(
            firstTransaction,
            manualTransaction(asset.id, amount = 1.0).copy(id = "transaction-2")
        )
        runCurrent()
        assertThat(calls.get()).isEqualTo(2)

        forcedRate.complete(20.0)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.currentBalanceUsd).isEqualTo(60.0)
        assertThat(state.isUsdLoading).isFalse()
        assertThat(state.usdError).isNull()
        assertThat(calls.get()).isEqualTo(3)
    }

    @Test
    fun `changed balance with failed replacement rate invalidates previous USD value`() = runTest {
        val asset = manualAsset()
        val transactionFlow = MutableStateFlow<List<Transaction>>(
            listOf(manualTransaction(asset.id, amount = 2.0))
        )
        val replacementStarted = CompletableDeferred<Unit>()
        val replacementResult = CompletableDeferred<Result<Double>>()
        val calls = AtomicInteger(0)
        val rates = mockk<ExchangeRateRepository>()

        coEvery { rates.fetchRate("BTC", "USD") } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> 10.0
                2 -> {
                    replacementStarted.complete(Unit)
                    replacementResult.await().getOrThrow()
                }
                else -> error("Unexpected rate request")
            }
        }
        coEvery { rates.clearCache() } returns Unit

        val viewModel = viewModel(
            asset = asset,
            transactions = transactionFlow.value,
            transactionFlow = transactionFlow,
            balances = mockk(relaxed = true),
            rates = rates
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isEqualTo(20.0)

        transactionFlow.value = listOf(manualTransaction(asset.id, amount = 3.0))
        runCurrent()
        replacementStarted.await()

        assertThat(viewModel.uiState.value.currentBalance).isEqualTo(3.0)
        assertThat(viewModel.uiState.value.currentBalanceUsd).isNull()
        assertThat(viewModel.uiState.value.isUsdLoading).isTrue()

        replacementResult.complete(Result.failure(IllegalStateException("replacement rate unavailable")))
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.currentBalance).isEqualTo(3.0)
        assertThat(state.currentBalanceUsd).isNull()
        assertThat(state.usdError).contains("replacement rate unavailable")
        assertThat(state.isUsdLoading).isFalse()
        assertThat(calls.get()).isEqualTo(2)
    }

    @Test
    fun `transaction emission cannot let cached balance supersede an in flight forced refresh`() =
        runTest {
            val asset = addressedAsset()
            val transactionFlow = MutableStateFlow<List<Transaction>>(emptyList())
            val forcedStarted = CompletableDeferred<Unit>()
            val forcedResult = CompletableDeferred<Result<OnChainBalance>>()
            val balances = mockk<OnChainBalanceRepository>()

            coEvery { balances.getBalance(asset, forceRefresh = false) } returns
                Result.success(providerBalance(asset, balance = 10.0))
            coEvery { balances.getBalance(asset, forceRefresh = true) } coAnswers {
                forcedStarted.complete(Unit)
                forcedResult.await()
            }

            val viewModel = viewModel(
                asset = asset,
                transactions = emptyList(),
                transactionFlow = transactionFlow,
                balances = balances,
                rates = immediateRates(1.0)
            )
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.uiState.collect()
            }
            advanceUntilIdle()
            assertThat(viewModel.uiState.value.onChainBalance?.balance).isEqualTo(10.0)

            viewModel.refreshOnChainBalance()
            runCurrent()
            forcedStarted.await()

            transactionFlow.value = listOf(onChainTransaction(asset.id))
            runCurrent()
            assertThat(viewModel.uiState.value.onChainBalance?.balance).isEqualTo(10.0)

            forcedResult.complete(Result.success(providerBalance(asset, balance = 20.0)))
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.onChainBalance?.balance).isEqualTo(20.0)
            assertThat(viewModel.uiState.value.currentBalance).isEqualTo(20.0)
        }

    @Test
    fun `USD result cannot repopulate after provider balance becomes unavailable`() = runTest {
        val asset = addressedAsset()
        val rateStarted = CompletableDeferred<Unit>()
        val rateResult = CompletableDeferred<Double>()
        val rates = mockk<ExchangeRateRepository>()
        val balances = mockk<OnChainBalanceRepository>()

        coEvery { rates.fetchRate("BTC", "USD") } coAnswers {
            rateStarted.complete(Unit)
            rateResult.await()
        }
        coEvery { rates.clearCache() } returns Unit
        coEvery { balances.getBalance(asset, forceRefresh = false) } returns
            Result.success(providerBalance(asset, balance = 2.0))
        coEvery { balances.getBalance(asset, forceRefresh = true) } returns
            Result.success(providerBalance(asset, balance = 2.0).copy(isStale = true))

        val viewModel = viewModel(
            asset = asset,
            transactions = emptyList(),
            balances = balances,
            rates = rates
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        runCurrent()
        rateStarted.await()

        viewModel.refreshOnChainBalance()
        runCurrent()
        assertThat(viewModel.uiState.value.currentBalance).isNull()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isNull()

        rateResult.complete(10.0)
        advanceUntilIdle()

        assertThat(viewModel.uiState.value.currentBalance).isNull()
        assertThat(viewModel.uiState.value.currentBalanceUsd).isNull()
        assertThat(viewModel.uiState.value.isUsdLoading).isFalse()
    }

    @Test
    fun `failed forced balance refresh invalidates previously displayed balance and USD value`() =
        runTest {
            val asset = addressedAsset()
            val balances = mockk<OnChainBalanceRepository>()
            coEvery { balances.getBalance(asset, forceRefresh = false) } returns
                Result.success(providerBalance(asset, balance = 2.0))
            coEvery { balances.getBalance(asset, forceRefresh = true) } returns
                Result.failure(IllegalStateException("provider unavailable"))

            val viewModel = viewModel(
                asset = asset,
                transactions = emptyList(),
                balances = balances,
                rates = immediateRates(10.0)
            )
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.uiState.collect()
            }
            advanceUntilIdle()
            assertThat(viewModel.uiState.value.currentBalance).isEqualTo(2.0)
            assertThat(viewModel.uiState.value.currentBalanceUsd).isEqualTo(20.0)

            viewModel.refreshOnChainBalance()
            advanceUntilIdle()

            val state = viewModel.uiState.value
            assertThat(state.onChainBalance).isNull()
            assertThat(state.currentBalance).isNull()
            assertThat(state.currentBalanceUsd).isNull()
            assertThat(state.onChainError).contains("provider unavailable")
            assertThat(state.isOnChainLoading).isFalse()
        }

    @Test
    fun `new provider transaction refresh wins when old provider failure completes last`() = runTest {
        val oldAsset = addressedAsset()
        val newAsset = oldAsset.copy(address = "bc1qnewwallet", updatedAt = 2L)
        val assetFlow = MutableStateFlow<Asset?>(oldAsset)
        val oldStarted = CompletableDeferred<Unit>()
        val newStarted = CompletableDeferred<Unit>()
        val oldResult = CompletableDeferred<Result<Int>>()
        val newResult = CompletableDeferred<Result<Int>>()
        val onChainTransactions = mockk<OnChainTransactionRepository>()
        val balances = mockk<OnChainBalanceRepository>()

        coEvery {
            onChainTransactions.refresh(asset = oldAsset, limit = 20, forceRefresh = false)
        } coAnswers {
            oldStarted.complete(Unit)
            oldResult.await()
        }
        coEvery {
            onChainTransactions.refresh(asset = newAsset, limit = 20, forceRefresh = false)
        } coAnswers {
            newStarted.complete(Unit)
            newResult.await()
        }
        coEvery { balances.getBalance(oldAsset, forceRefresh = false) } returns
            Result.success(providerBalance(oldAsset, balance = 1.0))
        coEvery { balances.getBalance(newAsset, forceRefresh = false) } returns
            Result.success(providerBalance(newAsset, balance = 2.0))

        val viewModel = viewModel(
            asset = oldAsset,
            assetFlow = assetFlow,
            transactions = emptyList(),
            balances = balances,
            rates = immediateRates(1.0),
            onChainTransactions = onChainTransactions
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect()
        }
        runCurrent()
        oldStarted.await()

        assetFlow.value = newAsset
        runCurrent()
        newStarted.await()

        newResult.complete(Result.success(1))
        runCurrent()
        assertThat(viewModel.uiState.value.onChainTransactionsError).isNull()
        assertThat(viewModel.uiState.value.isOnChainTransactionsLoading).isFalse()

        oldResult.complete(Result.failure(IllegalStateException("stale provider failure")))
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertThat(state.asset).isEqualTo(newAsset)
        assertThat(state.onChainTransactionsError).isNull()
        assertThat(state.isOnChainTransactionsLoading).isFalse()
    }

    private fun viewModel(
        asset: Asset,
        assetFlow: MutableStateFlow<Asset?> = MutableStateFlow(asset),
        transactions: List<Transaction>,
        transactionFlow: MutableStateFlow<List<Transaction>> = MutableStateFlow(transactions),
        balances: OnChainBalanceRepository,
        rates: ExchangeRateRepository,
        onChainTransactions: OnChainTransactionRepository = mockk<OnChainTransactionRepository>().also {
            coEvery { it.refresh(any(), any(), any()) } returns Result.success(0)
        }
    ): AssetDetailViewModel {
        val assets = mockk<AssetRepository>()
        val transactionRepository = mockk<TransactionRepository>()

        every { assets.getAssetByIdFlow(asset.id) } returns assetFlow
        every { transactionRepository.getTransactionsByAssetId(asset.id) } returns
            transactionFlow

        return AssetDetailViewModel(
            savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
            getAssetByIdUseCase = GetAssetByIdUseCase(assets),
            getTransactionsUseCase = GetTransactionsUseCase(transactionRepository),
            exchangeRateRepository = rates,
            onChainBalanceRepository = balances,
            onChainTransactionRepository = onChainTransactions,
            deleteAssetUseCase = mockk<DeleteAssetUseCase>(relaxed = true)
        )
    }

    private fun immediateRates(rate: Double): ExchangeRateRepository {
        return mockk<ExchangeRateRepository>().also { repository ->
            coEvery { repository.fetchRate(any(), any()) } returns rate
            coEvery { repository.clearCache() } returns Unit
        }
    }

    private fun providerBalance(asset: Asset, balance: Double) = OnChainBalance(
        assetId = asset.id,
        chainId = checkNotNull(asset.chainId),
        address = checkNotNull(asset.address),
        currency = asset.currency,
        balance = balance,
        fetchedAtMillis = System.currentTimeMillis(),
        isStale = false
    )

    private fun addressedAsset() = Asset(
        id = "asset-1",
        currency = "BTC",
        address = "bc1qwallet",
        chainId = "bitcoin",
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun manualAsset() = Asset(
        id = "asset-1",
        currency = "BTC",
        address = null,
        chainId = null,
        createdAt = 1L,
        updatedAt = 1L
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

    private fun onChainTransaction(assetId: String) = Transaction(
        id = "on-chain-transaction-1",
        assetId = assetId,
        amount = 1.0,
        dateMillis = 2L,
        source = TransactionSource.ON_CHAIN,
        externalId = "provider-transaction-1",
        counterparty = null,
        comment = null,
        createdAt = 2L
    )
}
