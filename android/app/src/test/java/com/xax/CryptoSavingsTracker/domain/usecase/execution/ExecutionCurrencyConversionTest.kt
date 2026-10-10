package com.xax.CryptoSavingsTracker.domain.usecase.execution

import androidx.lifecycle.ViewModelStore
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.*
import com.xax.CryptoSavingsTracker.domain.repository.*
import com.xax.CryptoSavingsTracker.presentation.execution.ExecutionViewModel
import com.xax.CryptoSavingsTracker.presentation.planning.MonthlyExecutionViewModel
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ExecutionCurrencyConversionTest {
    @Test
    fun `live progress converts each asset to each goal currency using frozen rates`() = runTest {
        val fixture = Fixture()
        val progress = fixture.session.sessionForRecord("record", START).first().associateBy { it.snapshot.goalId }

        assertThat(progress.getValue("usd-goal").contributed).isWithin(0.000001).of(220.0)
        assertThat(progress.getValue("eur-goal").contributed).isWithin(0.000001).of(180.0)
        assertThat(progress.values.all { it.isFulfilled }).isTrue()
    }

    @Test
    fun `completion persists the same converted goal amounts as live progress`() = runTest {
        val fixture = Fixture()
        assertThat(fixture.complete("record").isSuccess).isTrue()

        val actual = fixture.completed.associateBy { it.goalId }
        assertThat(actual.getValue("usd-goal").currency).isEqualTo("USD")
        assertThat(actual.getValue("usd-goal").actualAmount).isWithin(0.000001).of(220.0)
        assertThat(actual.getValue("eur-goal").actualAmount).isWithin(0.000001).of(180.0)
    }

    @Test
    fun `missing frozen exchange rate blocks completion before any persistence`() = runTest {
        val fixture = Fixture()
        fixture.frozenRates.value = fixture.frozenRates.value.filterNot {
            it.assetId == "btc" && it.snapshotCurrency == "USD"
        }

        assertThat(fixture.complete("record").isFailure).isTrue()
        assertThat(fixture.completed).isEmpty()
        coVerify(exactly = 0) { fixture.events.insert(any()) }
        coVerify(exactly = 0) { fixture.records.close(any(), any(), any()) }
    }

    @Test
    fun `missing required asset blocks completion instead of assuming goal currency`() = runTest {
        val fixture = Fixture()
        fixture.assets.value = fixture.assets.value.filter { it.id != "btc" }

        assertThat(fixture.complete("record").isFailure).isTrue()
        assertThat(fixture.completed).isEmpty()
        coVerify(exactly = 0) { fixture.events.insert(any()) }
    }

    @Test
    fun `a small bitcoin contribution retains its meaningful goal currency value`() = runTest {
        val fixture = Fixture()
        fixture.transactions.value = listOf(transaction("btc", 0.00001))
        fixture.history.value = listOf(history("btc", "usd-goal", 1.0))
        fixture.frozenRates.value = fixture.frozenRates.value.map {
            if (it.assetId == "btc" && it.snapshotCurrency == "USD") it.copy(rate = 100_000.0) else it
        }

        val progress = fixture.session.sessionForRecord("record", START).first()
        assertThat(progress.first { it.snapshot.goalId == "usd-goal" }.contributed).isWithin(0.000001).of(1.0)
    }

    @Test
    fun `same currency contributions do not require a remote exchange rate`() = runTest {
        val fixture = Fixture()
        fixture.assets.value = listOf(asset("btc", "USD"))
        fixture.transactions.value = listOf(transaction("btc", 25.0))
        fixture.history.value = listOf(history("btc", "usd-goal", 100.0))
        fixture.frozenRates.value = listOf(
            ExecutionAssetRate("btc", "USD", 1.0, START), ExecutionAssetRate("btc", "EUR", 0.8, START)
        )

        val progress = fixture.session.sessionForRecord("record", START).first()
        assertThat(progress.first { it.snapshot.goalId == "usd-goal" }.contributed).isEqualTo(25.0)
        coVerify(exactly = 0) { fixture.rates.fetchRate(any(), any()) }
    }

    @Test
    fun `invalid exchange rates never allow completion`() = runTest {
        for (rate in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            val fixture = Fixture()
            fixture.frozenRates.value = fixture.frozenRates.value.map {
                if (it.assetId == "btc" && it.snapshotCurrency == "USD") it.copy(rate = rate) else it
            }
            assertThat(fixture.complete("record").isFailure).isTrue()
            assertThat(fixture.completed).isEmpty()
        }
    }

    @Test
    fun `finite converted contributions cannot overflow the persisted goal total`() = runTest {
        val fixture = Fixture()
        fixture.history.value = fixture.history.value.map { it.copy(amount = 100.0) }
        fixture.transactions.value = listOf(transaction("btc", 200.0), transaction("eur", 200.0))
        fixture.frozenRates.value = fixture.frozenRates.value.map { it.copy(rate = 1e306) }

        assertThat(fixture.complete("record").isFailure).isTrue()
        assertThat(fixture.completed).isEmpty()
        coVerify(exactly = 0) { fixture.events.insert(any()) }
        coVerify(exactly = 0) { fixture.records.close(any(), any(), any()) }
    }

    @Test
    fun `incomplete conversion is explicit and recovers when frozen snapshot is repaired`() = runTest {
        val fixture = Fixture()
        val completeMatrix = fixture.frozenRates.value
        fixture.frozenRates.value = emptyList()
        val emissions = mutableListOf<ExecutionSession?>()
        val job = backgroundScope.launch { fixture.session.currentExecuting().collect { emissions += it } }
        runCurrent()

        assertThat(emissions.last()?.isProgressAvailable).isFalse()
        assertThat(emissions.last()?.goals).isEmpty()
        fixture.frozenRates.value = completeMatrix
        runCurrent()

        assertThat(emissions.last()?.isProgressAvailable).isTrue()
        assertThat(emissions.last()?.goals?.all { it.conversionError == null }).isTrue()
        assertThat(emissions.last()!!.goals.first { it.snapshot.currency == "USD" }.contributed)
            .isWithin(0.000001).of(220.0)
        job.cancel()
    }

    @Test
    fun `currency conversion cancellation propagates without completing execution`() = runTest {
        val fixture = Fixture()
        fixture.record.value = fixture.record.value.copy(legacyRateSnapshotPending = true)
        coEvery { fixture.legacyBackfill.resolve(any(), any(), any()) } throws CancellationException("cancelled")

        val failure = try {
            fixture.complete("record")
            null
        } catch (cancelled: CancellationException) {
            cancelled
        }
        assertThat(failure).isNotNull()
        assertThat(fixture.completed).isEmpty()
    }

    @Test
    fun `explicit refresh retries legacy FX with unchanged inputs and ends loading`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val store = ViewModelStore()
        try {
            val fixture = Fixture()
            fixture.record.value = fixture.record.value.copy(legacyRateSnapshotPending = true)
            coEvery { fixture.legacyBackfill.resolve(any(), any(), any()) } throws
                MissingExecutionAssetRateException("btc", "USD")
            val viewModel = MonthlyExecutionViewModel(fixture.session, mockk(), fixture.complete, mockk(), mockk())
            store.put("execution", viewModel)
            runCurrent()
            assertThat(viewModel.uiState.value.isProgressAvailable).isFalse()
            assertThat(viewModel.uiState.value.canComplete).isFalse()

            // No observed repository input emits; only the backfill service recovers.
            coEvery { fixture.legacyBackfill.resolve(any(), any(), any()) } returns fixture.frozenRates.value
            viewModel.refresh()
            runCurrent()

            assertThat(viewModel.uiState.value.isProgressAvailable).isTrue()
            assertThat(viewModel.uiState.value.canComplete).isTrue()
            assertThat(viewModel.uiState.value.goalProgress.first { it.snapshot.currency == "USD" }.contributed)
                .isWithin(0.000001).of(220.0)
            assertThat(viewModel.uiState.value.isLoading).isFalse()
        } finally {
            store.clear()
            runCurrent()
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `execution view model shares one frozen valuation across its UI consumers`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val store = ViewModelStore()
        try {
            val fixture = Fixture()
            val completedRepository = mockk<CompletedExecutionRepository>()
            every { completedRepository.getAll() } returns flowOf(emptyList())
            val settings = mockk<MonthlyPlanningSettings>()
            every { settings.executionDisplayCurrency } returns "USD"
            val goals = mockk<GoalRepository>()
            every { goals.getActiveGoals() } returns flowOf(emptyList())
            val viewModel = ExecutionViewModel(
                startExecutionUseCase = mockk(), getExecutionSessionUseCase = fixture.session,
                completeExecutionUseCase = fixture.complete, undoExecutionUseCase = mockk(),
                undoStartExecutionUseCase = mockk(), completedExecutionRepository = completedRepository,
                monthlyPlanningSettings = settings,
                executionContributionCalculator = ExecutionContributionCalculatorUseCase(),
                getAssetsUseCase = mockk(), allocationRepository = mockk(), goalRepository = goals,
                deadlineTimeSource = com.xax.CryptoSavingsTracker.presentation.common.DeadlineTimeSource()
            )
            store.put("execution", viewModel)
            val job = backgroundScope.launch { viewModel.uiState.collect {} }
            runCurrent()

            assertThat(viewModel.uiState.value.session?.goals).hasSize(2)
            verify(exactly = 1) { fixture.executionRates.getByRecordId("record") }
            coVerify(exactly = 0) { fixture.rates.fetchRate(any(), any()) }
            job.cancel()
        } finally {
            store.clear()
            runCurrent()
            Dispatchers.resetMain()
        }
    }

    private class Fixture {
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val record = MutableStateFlow(ExecutionRecord(
            "record", "plan", "2026-10", ExecutionStatus.EXECUTING, START, null, null, START, START
        ))
        val assets = MutableStateFlow(listOf(asset("btc", "BTC"), asset("eur", "EUR")))
        val transactions = MutableStateFlow(listOf(transaction("btc", 0.02), transaction("eur", 200.0)))
        val history = MutableStateFlow(listOf(
            history("btc", "usd-goal", 0.01), history("btc", "eur-goal", 0.01),
            history("eur", "usd-goal", 100.0), history("eur", "eur-goal", 100.0)
        ))
        val frozenRates = MutableStateFlow(listOf(
            ExecutionAssetRate("btc", "USD", 10_000.0, START), ExecutionAssetRate("btc", "EUR", 8_000.0, START),
            ExecutionAssetRate("eur", "USD", 1.2, START), ExecutionAssetRate("eur", "EUR", 1.0, START)
        ))
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val assetRepository = mockk<AssetRepository>()
        val rates = mockk<ExchangeRateRepository>()
        val legacyBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        var completed = emptyList<CompletedExecution>()
        val session: GetExecutionSessionUseCase
        val complete: CompleteExecutionUseCase

        init {
            val snapshots = mockk<ExecutionSnapshotRepository>()
            every { snapshots.getByRecordId("record") } returns MutableStateFlow(listOf(
                snapshot("usd-goal", "USD", 200.0), snapshot("eur-goal", "EUR", 150.0)
            ))
            val txRepository = mockk<TransactionRepository>()
            every { txRepository.getAllTransactions() } returns transactions
            val historyRepository = mockk<AllocationHistoryRepository>()
            every { historyRepository.getAll() } returns history
            val allocations = mockk<AllocationRepository>()
            every { allocations.getAllAllocationsFlow() } answers {
                flowOf(history.value.map {
                    Allocation(it.id, it.assetId, it.goalId, it.amount, it.createdAt, it.createdAt)
                })
            }
            every { assetRepository.getAllAssets() } returns assets
            every { executionRates.getByRecordId("record") } returns frozenRates
            every { records.getCurrentExecutingRecord() } returns record
            coEvery { records.getRecordById("record") } answers { record.value }
            coEvery { events.getNextSequence("record") } returns 1
            val completedRepository = mockk<CompletedExecutionRepository>()
            coEvery { completedRepository.append(any()) } answers { completed = firstArg() }
            val runner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            }
            val settings = mockk<MonthlyPlanningSettings>()
            every { settings.undoGracePeriodHours } returns 24
            session = GetExecutionSessionUseCase(
                records, snapshots, allocations, historyRepository, txRepository,
                assetRepository, executionRates, legacyBackfill
            )
            complete = CompleteExecutionUseCase(
                records, snapshots, completedRepository, events, allocations, historyRepository,
                txRepository, assetRepository, runner, executionRates, legacyBackfill, settings
            )
        }
    }

    private companion object {
        const val START = 1_000_000L
        fun asset(id: String, currency: String) = Asset(id, currency, null, null, START, START)
        fun transaction(assetId: String, amount: Double) = Transaction(
            "tx-$assetId", assetId, amount, START + 2_000, TransactionSource.MANUAL, null, null, null, START + 2_000
        )
        fun history(assetId: String, goalId: String, amount: Double) = AllocationHistory(
            "history-$assetId-$goalId", assetId, goalId, amount, "2026-10", START - 1_000, START - 1_000
        )
        fun snapshot(goalId: String, currency: String, required: Double) = ExecutionSnapshot(
            "snapshot-$goalId", "record", goalId, goalId, currency, 10_000.0, 0.0,
            required, false, false, null, START
        )
    }
}
