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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GetGoalProgressUseCaseReactiveTest {
    @Test
    fun `list and detail update after a deposit without changing the goal`() = runTest {
        val fixture = Fixture(this, initialBalance = 50.0)
        fixture.assertFunded(50.0)

        fixture.transactions.value += fixture.transaction("deposit", 50.0)
        runCurrent()

        fixture.assertFunded(100.0)
    }

    @Test
    fun `list and detail update after editing a transaction`() = runTest {
        val fixture = Fixture(this)
        fixture.assertFunded(100.0)

        fixture.transactions.value = listOf(fixture.transaction("initial", 50.0))
        runCurrent()

        fixture.assertFunded(50.0)
    }

    @Test
    fun `list and detail update after deleting a transaction`() = runTest {
        val fixture = Fixture(this)
        fixture.assertFunded(100.0)

        fixture.transactions.value = emptyList()
        runCurrent()

        fixture.assertFunded(0.0)
    }

    @Test
    fun `list and detail update when the goal allocation changes`() = runTest {
        val fixture = Fixture(this)
        fixture.assertFunded(100.0)

        fixture.allocations.value = listOf(fixture.allocation.copy(amount = 40.0))
        runCurrent()

        fixture.assertFunded(40.0)
    }

    @Test
    fun `competing allocation updates funding for an unchanged goal allocation`() = runTest {
        val fixture = Fixture(this)
        fixture.assertFunded(100.0)

        fixture.allocations.value += fixture.allocation.copy(id = "other", goalId = "other-goal")
        runCurrent()

        // A balance of 100 shared by two equal allocations funds each by 50.
        fixture.assertFunded(50.0)
    }

    @Test
    fun `asset currency edits update converted values without changing transactions`() = runTest {
        val fixture = Fixture(this)
        fixture.assertFunded(100.0)

        fixture.assets.value = listOf(fixture.asset.copy(currency = "EUR"))
        runCurrent()

        fixture.assertFunded(120.0)
        assertThat(fixture.list.last().single().allocatedAmount).isWithin(0.0001).of(120.0)
    }

    @Test
    fun `on chain refresh updates both progress flows without database writes`() = runTest {
        val fixture = Fixture(this, initialBalance = 0.0, onChainBalance = 50.0)
        runCurrent()
        fixture.assertFunded(50.0)

        fixture.cachedOnChainBalance = 100.0
        fixture.balanceRevision.value += 1
        runCurrent()

        fixture.assertFunded(100.0)
    }

    @Test
    fun `manual progress excludes on chain transactions already represented by the cached balance`() = runTest {
        val fixture = Fixture(this, initialBalance = 20.0, onChainBalance = 30.0)
        runCurrent()
        fixture.assertFunded(50.0)

        fixture.transactions.value += fixture.transaction("chain", 30.0).copy(source = TransactionSource.ON_CHAIN)
        runCurrent()

        fixture.assertFunded(50.0)
    }

    private class Fixture(
        scope: TestScope,
        initialBalance: Double = 100.0,
        onChainBalance: Double? = null
    ) {
        val goal = Goal(
            id = "goal", name = "Goal", currency = "USD", targetAmount = 200.0,
            deadline = LocalDate.of(2027, 1, 1), startDate = LocalDate.of(2026, 1, 1),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE, lifecycleStatusChangedAt = null,
            emoji = null, description = null, link = null, reminderFrequency = null,
            reminderTimeMillis = null, firstReminderDate = null, createdAt = 1L, updatedAt = 1L
        )
        val asset = Asset(
            "asset", "USD", if (onChainBalance != null) "wallet" else null,
            if (onChainBalance != null) "ethereum" else null, 1L, 1L
        )
        val allocation = Allocation("allocation", asset.id, goal.id, 100.0, 1L, 1L)
        val allocations = MutableStateFlow(listOf(allocation))
        val assets = MutableStateFlow(listOf(asset))
        val transactions = MutableStateFlow(listOf(transaction("initial", initialBalance)))
        val list = mutableListOf<List<GoalWithProgress>>()
        val detail = mutableListOf<GoalWithProgress?>()
        val balanceRevision = MutableStateFlow(0L)
        var cachedOnChainBalance = onChainBalance ?: 0.0

        init {
            val goals = mockk<GoalRepository>()
            val allocationRepository = mockk<AllocationRepository>()
            val assetRepository = mockk<AssetRepository>()
            val transactionRepository = mockk<TransactionRepository>()
            val onChain = mockk<OnChainBalanceRepository>()
            val rates = mockk<ExchangeRateRepository>()
            every { allocationRepository.getAllAllocationsFlow() } returns allocations
            every { onChain.observeBalanceInvalidations() } returns balanceRevision
            coEvery { onChain.getBalance(any(), any()) } coAnswers {
                val requested = firstArg<Asset>()
                Result.success(OnChainBalance(
                    requested.id, requested.chainId!!, requested.address!!, requested.currency,
                    cachedOnChainBalance, 1L, false
                ))
            }
            every { goals.getAllGoals() } returns MutableStateFlow(listOf(goal))
            every { goals.getGoalByIdFlow(goal.id) } returns MutableStateFlow(goal)
            every { allocationRepository.getAllocationsForGoalListFlow(goal.id) } returns
                allocations.map { rows -> rows.filter { it.goalId == goal.id } }
            coEvery { allocationRepository.getAllocationsForGoal(goal.id) } coAnswers {
                allocations.value.filter { it.goalId == goal.id }
            }
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } coAnswers { allocations.value }
            every { assetRepository.getAllAssets() } returns assets
            coEvery { assetRepository.getAssetById(asset.id) } coAnswers { assets.value.single() }
            every { transactionRepository.getAllTransactions() } returns transactions
            coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } coAnswers {
                transactions.value.filter { it.source == TransactionSource.MANUAL }.sumOf { it.amount }
            }
            every { rates.observeRateInvalidations() } returns MutableStateFlow(0L)
            coEvery { rates.fetchRate("EUR", "USD") } returns 1.2
            val useCase = GetGoalProgressUseCase(
                goals, allocationRepository, transactionRepository, assetRepository, onChain, rates
            )
            scope.backgroundScope.launch(UnconfinedTestDispatcher(scope.testScheduler)) {
                useCase().collect { list += it }
            }
            scope.backgroundScope.launch(UnconfinedTestDispatcher(scope.testScheduler)) {
                useCase.getProgressFlow(goal.id).collect { detail += it }
            }
            scope.runCurrent()
        }

        fun transaction(id: String, amount: Double) = Transaction(
            id, asset.id, amount, 1L, TransactionSource.MANUAL, null, null, null, 1L
        )

        fun assertFunded(expected: Double) {
            assertThat(list.last().single().fundedAmount).isWithin(0.0001).of(expected)
            assertThat(detail.last()!!.fundedAmount).isWithin(0.0001).of(expected)
        }
    }
}
