package com.xax.CryptoSavingsTracker.domain.usecase.execution

import androidx.lifecycle.ViewModelStore
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.*
import com.xax.CryptoSavingsTracker.domain.repository.*
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import com.xax.CryptoSavingsTracker.presentation.planning.MonthlyExecutionViewModel
import com.xax.CryptoSavingsTracker.presentation.execution.ExecutionViewModel
import kotlinx.coroutines.flow.flowOf
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ExecutionCurrencyConversionTest {
    @Test
    fun `live progress converts each asset to each goal currency`() = runTest {
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
    fun `missing exchange rate blocks completion before any persistence`() = runTest {
        val fixture = Fixture()
        coEvery { fixture.rates.fetchRate("BTC", "USD") } throws ExchangeRateException.RateNotAvailable

        assertThat(fixture.complete("record").isFailure).isTrue()

        assertThat(fixture.completed).isEmpty()
        coVerify(exactly = 0) { fixture.events.insert(any()) }
        coVerify(exactly = 0) { fixture.records.close(any(), any(), any()) }
    }

    @Test
    fun `missing asset currency blocks completion instead of assuming goal currency`() = runTest {
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
        coEvery { fixture.rates.fetchRate("BTC", "USD") } returns 100_000.0

        val progress = fixture.session.sessionForRecord("record", START).first()

        assertThat(progress.first { it.snapshot.goalId == "usd-goal" }.contributed).isWithin(0.000001).of(1.0)
    }

    @Test
    fun `same currency contributions do not require a remote exchange rate`() = runTest {
        val fixture = Fixture()
        fixture.assets.value = listOf(asset("btc", "usd"))
        fixture.transactions.value = listOf(transaction("btc", 25.0))
        fixture.history.value = listOf(history("btc", "usd-goal", 100.0))

        val progress = fixture.session.sessionForRecord("record", START).first()

        assertThat(progress.first { it.snapshot.goalId == "usd-goal" }.contributed).isEqualTo(25.0)
        coVerify(exactly = 0) { fixture.rates.fetchRate(any(), any()) }
    }

    @Test
    fun `invalid exchange rates never allow completion`() = runTest {
        for (rate in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            val fixture = Fixture()
            coEvery { fixture.rates.fetchRate("BTC", "USD") } returns rate

            assertThat(fixture.complete("record").isFailure).isTrue()
            assertThat(fixture.completed).isEmpty()
        }
    }

    @Test
    fun `live conversion failure is explicit and recovers on an asset currency update`() = runTest {
        val fixture = Fixture()
        fixture.assets.value = listOf(asset("btc", "UNKNOWN"), asset("eur", "EUR"))
        coEvery { fixture.rates.fetchRate("UNKNOWN", any()) } throws ExchangeRateException.RateNotAvailable
        val emissions = mutableListOf<List<ExecutionGoalProgress>>()
        val job = backgroundScope.launch {
            fixture.session.sessionForRecord("record", START).collect { emissions += it }
        }
        runCurrent()

        assertThat(emissions.last().all { it.conversionError != null && !it.isFulfilled }).isTrue()
        assertThat(emissions.last().all { it.contributed == 0.0 }).isTrue()

        fixture.assets.value = listOf(asset("btc", "BTC"), asset("eur", "EUR"))
        runCurrent()

        assertThat(emissions.last().all { it.conversionError == null }).isTrue()
        assertThat(emissions.last().first { it.snapshot.currency == "USD" }.contributed).isWithin(0.000001).of(220.0)
        job.cancel()
    }

    @Test
    fun `currency conversion cancellation propagates without completing execution`() = runTest {
        val fixture = Fixture()
        coEvery { fixture.rates.fetchRate("BTC", "USD") } throws CancellationException("cancelled")

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
    fun `explicit refresh retries FX with unchanged inputs and ends loading`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val store = ViewModelStore()
        try {
            val fixture = Fixture()
            val record = fixture.records.getRecordById("record")!!
            every { fixture.records.getCurrentExecutingRecord() } returns MutableStateFlow(record)
            coEvery { fixture.rates.fetchRate("BTC", "USD") } throws ExchangeRateException.RateNotAvailable
            val viewModel = MonthlyExecutionViewModel(
                fixture.session, mockk(), fixture.complete, mockk(), mockk()
            )
            store.put("execution", viewModel)
            runCurrent()
            assertThat(viewModel.uiState.value.goalProgress.first { it.snapshot.currency == "USD" }.conversionError)
                .isNotNull()

            // Only the external rate service changes; none of the observed repository inputs emit.
            coEvery { fixture.rates.fetchRate("BTC", "USD") } returns 10_000.0
            viewModel.refresh()
            runCurrent()

            assertThat(viewModel.uiState.value.goalProgress.first { it.snapshot.currency == "USD" }.conversionError)
                .isNull()
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
    fun `execution view model shares one valuation across its UI consumers`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val store = ViewModelStore()
        try {
            val fixture = Fixture()
            every { fixture.records.getCurrentExecutingRecord() } returns
                MutableStateFlow(fixture.records.getRecordById("record"))
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
                executionContributionCalculator = ExecutionContributionCalculatorUseCase(fixture.rates),
                getAssetsUseCase = mockk(), allocationRepository = mockk(), goalRepository = goals
            )
            store.put("execution", viewModel)
            val job = backgroundScope.launch { viewModel.uiState.collect {} }
            runCurrent()

            assertThat(viewModel.uiState.value.session?.goals).hasSize(2)
            coVerify(exactly = 1) { fixture.rates.fetchRate("BTC", "USD") }
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
        val assets = MutableStateFlow(listOf(asset("btc", "BTC"), asset("eur", "EUR")))
        val transactions = MutableStateFlow(listOf(transaction("btc", 0.02), transaction("eur", 200.0)))
        val history = MutableStateFlow(listOf(
            history("btc", "usd-goal", 0.01), history("btc", "eur-goal", 0.01),
            history("eur", "usd-goal", 100.0), history("eur", "eur-goal", 100.0)
        ))
        val assetRepository = mockk<AssetRepository>()
        val rates = mockk<ExchangeRateRepository>()
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
            every { assetRepository.getAllAssets() } returns assets
            coEvery { rates.fetchRate("BTC", "USD") } returns 10_000.0
            coEvery { rates.fetchRate("BTC", "EUR") } returns 8_000.0
            coEvery { rates.fetchRate("EUR", "USD") } returns 1.2
            coEvery { records.getRecordById("record") } returns ExecutionRecord(
                "record", "plan", "2026-10", ExecutionStatus.EXECUTING, START, null, null, START, START
            )
            coEvery { events.getNextSequence("record") } returns 1
            val completedRepository = mockk<CompletedExecutionRepository>()
            coEvery { completedRepository.append(any()) } answers { completed = firstArg() }
            val runner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            }
            val calculateProgress = CalculateExecutionProgressUseCase(rates)
            session = GetExecutionSessionUseCase(
                records, snapshots, historyRepository, txRepository, assetRepository, calculateProgress
            )
            complete = CompleteExecutionUseCase(
                records, snapshots, completedRepository, events, historyRepository, txRepository, runner,
                assetRepository, calculateProgress
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
