package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GetGoalProgressReactiveInvalidationTest {
    @Test
    fun `goal row mutation invalidates observed goal progress`() = runTest {
        val initialGoal = goal()
        val goalFlow = MutableStateFlow(initialGoal)
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()

        every { goalRepository.getGoalByIdFlow(initialGoal.id) } returns goalFlow
        every { allocationRepository.getAllAllocationsFlow() } returns
            MutableStateFlow(emptyList())
        every { allocationRepository.getAllocationsForGoalListFlow(initialGoal.id) } returns
            MutableStateFlow(emptyList())
        every { transactionRepository.getAllTransactions() } returns MutableStateFlow(emptyList())
        every { assetRepository.getAllAssets() } returns MutableStateFlow(emptyList())
        every { balances.observeBalanceInvalidations() } returns flowOf(0L)
        every { rates.observeRateInvalidations() } returns flowOf(0L)

        val useCase = GetGoalProgressUseCase(
            goalRepository,
            allocationRepository,
            transactionRepository,
            assetRepository,
            balances,
            rates
        )
        val emissions = mutableListOf<GoalWithProgress?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            useCase.getProgressFlow(initialGoal.id).take(2).toList(emissions)
        }
        runCurrent()
        assertThat(emissions.single()?.goal?.name).isEqualTo("Goal")

        goalFlow.value = initialGoal.copy(name = "Updated goal", updatedAt = 2L)
        runCurrent()

        assertThat(emissions).hasSize(2)
        assertThat(emissions.last()?.goal?.name).isEqualTo("Updated goal")
    }

    @Test
    fun `manual transaction mutation invalidates an observed goal without a goal row change`() = runTest {
        val goal = goal()
        val asset = asset()
        val allocation = allocation(goal, asset)
        val transactionFlow = MutableStateFlow<List<Transaction>>(emptyList())
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()

        every { goalRepository.getGoalByIdFlow(goal.id) } returns MutableStateFlow(goal)
        every { allocationRepository.getAllAllocationsFlow() } returns
            MutableStateFlow(listOf(allocation))
        every { allocationRepository.getAllocationsForGoalListFlow(goal.id) } returns
            MutableStateFlow(listOf(allocation))
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
        every { transactionRepository.getAllTransactions() } returns transactionFlow
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } answers {
            transactionFlow.value
                .filter { it.assetId == asset.id && it.source == TransactionSource.MANUAL }
                .sumOf { it.amount }
        }
        every { assetRepository.getAllAssets() } returns MutableStateFlow(listOf(asset))
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        every { onChainBalanceRepository.observeBalanceInvalidations() } returns flowOf(0L)
        every { exchangeRateRepository.observeRateInvalidations() } returns flowOf(0L)

        val useCase = GetGoalProgressUseCase(
            goalRepository = goalRepository,
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            exchangeRateRepository = exchangeRateRepository
        )
        val emissions = mutableListOf<GoalWithProgress?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            useCase.getProgressFlow(goal.id).take(2).toList(emissions)
        }
        runCurrent()
        assertThat(emissions).hasSize(1)
        assertThat(emissions.single()?.fundedAmount).isEqualTo(0.0)

        transactionFlow.value = listOf(manualTransaction(asset.id, amount = 40.0))
        runCurrent()

        assertThat(emissions).hasSize(2)
        assertThat(emissions.last()?.fundedAmount).isEqualTo(40.0)
        assertThat(emissions.last()?.progress).isEqualTo(0.4)
    }

    @Test
    fun `provider balance version invalidates goal detail progress`() = runTest {
        val goal = goal(currency = "BTC")
        val asset = asset(currency = "BTC", addressed = true)
        val allocation = allocation(goal, asset)
        val balanceVersion = MutableStateFlow(0L)
        var providerBalance = 10.0
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()

        every { goalRepository.getGoalByIdFlow(goal.id) } returns MutableStateFlow(goal)
        every { allocationRepository.getAllAllocationsFlow() } returns
            MutableStateFlow(listOf(allocation))
        every { allocationRepository.getAllocationsForGoalListFlow(goal.id) } returns
            MutableStateFlow(listOf(allocation))
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
        every { transactionRepository.getAllTransactions() } returns MutableStateFlow(emptyList())
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 0.0
        every { assetRepository.getAllAssets() } returns MutableStateFlow(listOf(asset))
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        every { balances.observeBalanceInvalidations() } returns balanceVersion
        coEvery { balances.getBalance(asset, forceRefresh = false) } answers {
            Result.success(providerBalance(asset, providerBalance))
        }
        every { rates.observeRateInvalidations() } returns flowOf(0L)

        val useCase = GetGoalProgressUseCase(
            goalRepository,
            allocationRepository,
            transactionRepository,
            assetRepository,
            balances,
            rates
        )
        val emissions = mutableListOf<GoalWithProgress?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            useCase.getProgressFlow(goal.id).take(2).toList(emissions)
        }
        runCurrent()
        assertThat(emissions.single()?.fundedAmount).isEqualTo(10.0)

        providerBalance = 40.0
        balanceVersion.value = 1L
        runCurrent()

        assertThat(emissions).hasSize(2)
        assertThat(emissions.last()?.fundedAmount).isEqualTo(40.0)
        assertThat(emissions.last()?.progress).isEqualTo(0.4)
    }

    @Test
    fun `rate and asset versions invalidate goal detail progress`() = runTest {
        val goal = goal(currency = "USD")
        val initialAsset = asset(currency = "BTC")
        val allocation = allocation(goal, initialAsset, amount = 1.0)
        val transaction = manualTransaction(initialAsset.id, amount = 1.0)
        val assetFlow = MutableStateFlow(listOf(initialAsset))
        val rateVersion = MutableStateFlow(0L)
        var rate = 10.0
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()

        every { goalRepository.getGoalByIdFlow(goal.id) } returns MutableStateFlow(goal)
        every { allocationRepository.getAllAllocationsFlow() } returns
            MutableStateFlow(listOf(allocation))
        every { allocationRepository.getAllocationsForGoalListFlow(goal.id) } returns
            MutableStateFlow(listOf(allocation))
        coEvery { allocationRepository.getAllocationsForAsset(initialAsset.id) } returns listOf(allocation)
        every { transactionRepository.getAllTransactions() } returns MutableStateFlow(listOf(transaction))
        coEvery { transactionRepository.getManualBalanceForAsset(initialAsset.id) } returns 1.0
        every { assetRepository.getAllAssets() } returns assetFlow
        coEvery { assetRepository.getAssetById(initialAsset.id) } answers {
            assetFlow.value.single()
        }
        every { balances.observeBalanceInvalidations() } returns flowOf(0L)
        every { rates.observeRateInvalidations() } returns rateVersion
        coEvery { rates.fetchRate(any(), "USD") } answers { rate }

        val useCase = GetGoalProgressUseCase(
            goalRepository,
            allocationRepository,
            transactionRepository,
            assetRepository,
            balances,
            rates
        )
        val emissions = mutableListOf<GoalWithProgress?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            useCase.getProgressFlow(goal.id).take(3).toList(emissions)
        }
        runCurrent()
        assertThat(emissions.single()?.fundedAmount).isEqualTo(10.0)

        rate = 20.0
        rateVersion.value = 1L
        runCurrent()
        assertThat(emissions.last()?.fundedAmount).isEqualTo(20.0)

        rate = 30.0
        assetFlow.value = listOf(initialAsset.copy(currency = "ETH", updatedAt = 2L))
        runCurrent()

        assertThat(emissions).hasSize(3)
        assertThat(emissions.last()?.fundedAmount).isEqualTo(30.0)
    }

    @Test
    fun `allocation on another goal invalidates shared asset funding on all goals flow`() = runTest {
        val goal = goal()
        val otherGoal = goal().copy(id = "goal-2", name = "Other")
        val asset = asset()
        val targetAllocation = allocation(goal, asset, amount = 60.0)
        val otherAllocation = allocation(otherGoal, asset, amount = 60.0).copy(id = "allocation-2")
        val allAllocations = MutableStateFlow(listOf(targetAllocation))
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val balances = mockk<OnChainBalanceRepository>()
        val rates = mockk<ExchangeRateRepository>()

        every { goalRepository.getAllGoals() } returns MutableStateFlow(listOf(goal))
        every { allocationRepository.getAllAllocationsFlow() } returns allAllocations
        coEvery { allocationRepository.getAllocationsForGoal(goal.id) } returns listOf(targetAllocation)
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } answers {
            allAllocations.value
        }
        every { transactionRepository.getAllTransactions() } returns
            MutableStateFlow(listOf(manualTransaction(asset.id, amount = 60.0)))
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 60.0
        every { assetRepository.getAllAssets() } returns MutableStateFlow(listOf(asset))
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        every { balances.observeBalanceInvalidations() } returns flowOf(0L)
        every { rates.observeRateInvalidations() } returns flowOf(0L)

        val useCase = GetGoalProgressUseCase(
            goalRepository,
            allocationRepository,
            transactionRepository,
            assetRepository,
            balances,
            rates
        )
        val emissions = mutableListOf<List<GoalWithProgress>>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            useCase().take(2).toList(emissions)
        }
        runCurrent()
        assertThat(emissions.single().single().fundedAmount).isEqualTo(60.0)

        allAllocations.value = listOf(targetAllocation, otherAllocation)
        runCurrent()

        assertThat(emissions).hasSize(2)
        assertThat(emissions.last().single().fundedAmount).isEqualTo(30.0)
    }

    private fun goal(currency: String = "USD") = Goal(
        id = "goal-1",
        name = "Goal",
        currency = currency,
        targetAmount = 100.0,
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

    private fun asset(
        currency: String = "USD",
        addressed: Boolean = false
    ) = Asset(
        id = "asset-1",
        currency = currency,
        address = if (addressed) "bc1qwallet" else null,
        chainId = if (addressed) "bitcoin" else null,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun allocation(
        goal: Goal,
        asset: Asset,
        amount: Double = 100.0
    ) = Allocation(
        id = "allocation-1",
        assetId = asset.id,
        goalId = goal.id,
        amount = amount,
        createdAt = 1L,
        lastModifiedAt = 1L
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

    private fun providerBalance(asset: Asset, balance: Double) = OnChainBalance(
        assetId = asset.id,
        chainId = checkNotNull(asset.chainId),
        address = checkNotNull(asset.address),
        currency = asset.currency,
        balance = balance,
        fetchedAtMillis = 1L,
        isStale = false
    )
}
