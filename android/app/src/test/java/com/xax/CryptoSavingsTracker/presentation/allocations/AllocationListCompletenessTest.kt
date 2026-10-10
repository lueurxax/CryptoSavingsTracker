package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.DeleteAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.GetAllocationsForGoalUseCase
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AllocationListCompletenessTest {
    @Test
    fun `deposit changes recompute funded total without an allocation edit`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
            val goal = goal(currency = "USD")
            val asset = Asset("usd", "USD", null, null, 1L, 1L)
            val allocation = Allocation("allocation-1", asset.id, goal.id, 100.0, 1L, 1L)
            val goalFlow = MutableStateFlow<Goal?>(goal)
            val assetsFlow = MutableStateFlow(listOf(asset))
            val allocationsFlow = MutableStateFlow(listOf(allocation))
            val transactionsFlow = MutableStateFlow(
                listOf(manualTransaction(amount = 50.0, assetId = asset.id))
            )
            val getAllocations = mockk<GetAllocationsForGoalUseCase>()
            val goals = mockk<GoalRepository>()
            val assets = mockk<AssetRepository>()
            val allocationRepository = mockk<AllocationRepository>()
            val transactions = mockk<TransactionRepository>()
            val balances = mockk<OnChainBalanceRepository>()
            val rates = mockk<ExchangeRateRepository>()

            every { getAllocations(goal.id) } returns allocationsFlow
            every { goals.getGoalByIdFlow(goal.id) } returns goalFlow
            coEvery { goals.getGoalById(goal.id) } returns goal
            every { assets.getAllAssets() } returns assetsFlow
            coEvery { assets.getAssetById(asset.id) } returns asset
            every { allocationRepository.getAllAllocationsFlow() } returns allocationsFlow
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
            every { transactions.getAllTransactions() } returns transactionsFlow
            coEvery { transactions.getManualBalanceForAsset(asset.id) } answers {
                transactionsFlow.value.sumOf { it.amount }
            }
            every { balances.observeBalanceInvalidations() } returns flowOf(0L)
            every { rates.observeRateInvalidations() } returns flowOf(0L)

            val viewModel = AllocationListViewModel(
                savedStateHandle = SavedStateHandle(mapOf("goalId" to goal.id)),
                getAllocationsForGoalUseCase = getAllocations,
                deleteAllocationUseCase = mockk(relaxed = true),
                goalRepository = goals,
                assetRepository = assets,
                allocationRepository = allocationRepository,
                transactionRepository = transactions,
                onChainBalanceRepository = balances,
                exchangeRateRepository = rates
            )
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.uiState.collect { }
            }
            advanceUntilIdle()
            assertThat(viewModel.uiState.value.totalFunded).isEqualTo(50.0)

            transactionsFlow.value = listOf(manualTransaction(amount = 80.0, assetId = asset.id))
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.totalFunded).isEqualTo(80.0)
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `goal currency change wins over an older suspended conversion`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
            val usdGoal = goal(currency = "USD")
            val gbpGoal = usdGoal.copy(currency = "GBP", updatedAt = 2L)
            val asset = Asset("eur", "EUR", null, null, 1L, 1L)
            val allocation = Allocation("allocation-1", asset.id, usdGoal.id, 100.0, 1L, 1L)
            val goalFlow = MutableStateFlow<Goal?>(usdGoal)
            val assetsFlow = MutableStateFlow(listOf(asset))
            val allocationsFlow = MutableStateFlow(listOf(allocation))
            val transactionsFlow = MutableStateFlow(
                listOf(manualTransaction(amount = 100.0, assetId = asset.id))
            )
            val usdConversionStarted = CompletableDeferred<Unit>()
            val releaseUsdConversion = CompletableDeferred<Double>()
            val getAllocations = mockk<GetAllocationsForGoalUseCase>()
            val goals = mockk<GoalRepository>()
            val assets = mockk<AssetRepository>()
            val allocationRepository = mockk<AllocationRepository>()
            val transactions = mockk<TransactionRepository>()
            val balances = mockk<OnChainBalanceRepository>()
            val rates = mockk<ExchangeRateRepository>()

            every { getAllocations(usdGoal.id) } returns allocationsFlow
            every { goals.getGoalByIdFlow(usdGoal.id) } returns goalFlow
            coEvery { goals.getGoalById(usdGoal.id) } returns usdGoal
            every { assets.getAllAssets() } returns assetsFlow
            coEvery { assets.getAssetById(asset.id) } returns asset
            every { allocationRepository.getAllAllocationsFlow() } returns allocationsFlow
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
            every { transactions.getAllTransactions() } returns transactionsFlow
            coEvery { transactions.getManualBalanceForAsset(asset.id) } returns 100.0
            every { balances.observeBalanceInvalidations() } returns flowOf(0L)
            every { rates.observeRateInvalidations() } returns flowOf(0L)
            coEvery { rates.fetchRate("EUR", "USD") } coAnswers {
                usdConversionStarted.complete(Unit)
                withContext(NonCancellable) { releaseUsdConversion.await() }
            }
            coEvery { rates.fetchRate("EUR", "GBP") } returns 2.0

            val viewModel = AllocationListViewModel(
                savedStateHandle = SavedStateHandle(mapOf("goalId" to usdGoal.id)),
                getAllocationsForGoalUseCase = getAllocations,
                deleteAllocationUseCase = mockk(relaxed = true),
                goalRepository = goals,
                assetRepository = assets,
                allocationRepository = allocationRepository,
                transactionRepository = transactions,
                onChainBalanceRepository = balances,
                exchangeRateRepository = rates
            )
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.uiState.collect { }
            }
            runCurrent()
            usdConversionStarted.await()

            goalFlow.value = gbpGoal
            runCurrent()

            assertThat(viewModel.uiState.value.goal?.currency).isEqualTo("GBP")
            assertThat(viewModel.uiState.value.totalAllocated).isEqualTo(200.0)
            assertThat(viewModel.uiState.value.totalFunded).isEqualTo(200.0)

            releaseUsdConversion.complete(10.0)
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.goal?.currency).isEqualTo("GBP")
            assertThat(viewModel.uiState.value.totalAllocated).isEqualTo(200.0)
            assertThat(viewModel.uiState.value.totalFunded).isEqualTo(200.0)
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `missing conversion makes allocation totals unavailable instead of partial`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = Goal(
                id = "goal-1",
                name = "Goal",
                currency = "USD",
                targetAmount = 1_000.0,
                deadline = LocalDate.now().plusDays(30),
                startDate = LocalDate.now(),
                lifecycleStatus = GoalLifecycleStatus.ACTIVE,
                lifecycleStatusChangedAt = null,
                emoji = null,
                description = null,
                link = null,
                reminderFrequency = null,
                reminderTimeMillis = null,
                firstReminderDate = null,
                createdAt = 1L,
                updatedAt = 1L
            )
            val usd = Asset("usd", "USD", null, null, 1L, 1L)
            val btc = Asset("btc", "BTC", null, "bitcoin", 1L, 1L)
            val usdAllocation = Allocation("usd-a", usd.id, goal.id, 100.0, 1L, 1L)
            val btcAllocation = Allocation("btc-a", btc.id, goal.id, 1.0, 1L, 1L)
            val allocations = listOf(usdAllocation, btcAllocation)
            val getAllocations = mockk<GetAllocationsForGoalUseCase>()
            val goals = mockk<GoalRepository>()
            val assets = mockk<AssetRepository>()
            val allocationRepository = mockk<AllocationRepository>()
            val transactions = mockk<TransactionRepository>()
            val balances = mockk<OnChainBalanceRepository>()
            val rates = mockk<ExchangeRateRepository>()

            every { getAllocations(goal.id) } returns flowOf(allocations)
            every { goals.getGoalByIdFlow(goal.id) } returns flowOf(goal)
            coEvery { goals.getGoalById(goal.id) } returns goal
            every { assets.getAllAssets() } returns flowOf(listOf(usd, btc))
            coEvery { assets.getAssetById(usd.id) } returns usd
            coEvery { assets.getAssetById(btc.id) } returns btc
            every { allocationRepository.getAllAllocationsFlow() } returns flowOf(allocations)
            every { transactions.getAllTransactions() } returns flowOf(
                listOf(
                    manualTransaction(amount = 100.0, assetId = usd.id),
                    manualTransaction(amount = 1.0, assetId = btc.id)
                )
            )
            coEvery { transactions.getManualBalanceForAsset(usd.id) } returns 100.0
            coEvery { transactions.getManualBalanceForAsset(btc.id) } returns 1.0
            coEvery { allocationRepository.getAllocationsForAsset(usd.id) } returns listOf(usdAllocation)
            coEvery { allocationRepository.getAllocationsForAsset(btc.id) } returns listOf(btcAllocation)
            every { balances.observeBalanceInvalidations() } returns flowOf(0L)
            every { rates.observeRateInvalidations() } returns flowOf(0L)
            coEvery { rates.fetchRate("BTC", "USD") } throws IllegalStateException("rate offline")

            val viewModel = AllocationListViewModel(
                savedStateHandle = SavedStateHandle(mapOf("goalId" to goal.id)),
                getAllocationsForGoalUseCase = getAllocations,
                deleteAllocationUseCase = mockk<DeleteAllocationUseCase>(relaxed = true),
                goalRepository = goals,
                assetRepository = assets,
                allocationRepository = allocationRepository,
                transactionRepository = transactions,
                onChainBalanceRepository = balances,
                exchangeRateRepository = rates
            )
                backgroundScope.launch(UnconfinedTestDispatcher(scheduler)) {
                    viewModel.uiState.collect { }
                }
                advanceUntilIdle()

                val state = viewModel.uiState.value
                assertThat(state.allocations).hasSize(2)
                assertThat(state.totalAllocated).isNull()
                assertThat(state.totalFunded).isNull()
                assertThat(state.hasMissingExchangeRates).isTrue()
                assertThat(state.financialDataIssue).contains("Exchange rate BTC")
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    private fun goal(currency: String) = Goal(
        id = "goal-1",
        name = "Goal",
        currency = currency,
        targetAmount = 1_000.0,
        deadline = LocalDate.now().plusDays(30),
        startDate = LocalDate.now(),
        lifecycleStatus = GoalLifecycleStatus.ACTIVE,
        lifecycleStatusChangedAt = null,
        emoji = null,
        description = null,
        link = null,
        reminderFrequency = null,
        reminderTimeMillis = null,
        firstReminderDate = null,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun manualTransaction(amount: Double, assetId: String) = Transaction(
        id = "transaction-$amount",
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
