package com.xax.CryptoSavingsTracker.presentation.dashboard

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.navigation.NavigationTelemetryTracker
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.execution.FundedDeltaAttributionCalculator
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalContributionAttributionCalculator
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

@OptIn(ExperimentalCoroutinesApi::class)
class GoalDashboardViewModelContributionAttributionTest {
    @Test
    fun `shared asset transaction contributes only the goal funded delta`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val targetAllocation = allocation(id = "allocation-a", goalId = goal.id, amount = 60.0)
            val otherAllocation = allocation(id = "allocation-b", goalId = "goal-b", amount = 40.0)
            val transaction = transaction(id = "shared-deposit", amount = 50.0, dateMillis = now - 1_000L)
            val fixture = fixture(
                goal = goal,
                allocations = listOf(targetAllocation, otherAllocation),
                histories = listOf(
                    history(id = "history-a", goalId = goal.id, amount = 60.0, timestamp = now - 10_000L),
                    history(id = "history-b", goalId = "goal-b", amount = 40.0, timestamp = now - 10_000L)
                ),
                transactions = listOf(transaction),
                fundedAmount = 30.0
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.FRESH)
            assertThat(scene.contributionActivity.monthContributionSum.toDouble()).isEqualTo(30.0)
            assertThat(scene.contributionActivity.recentRows).hasSize(1)
            assertThat(scene.contributionActivity.recentRows.single().amount.toDouble()).isEqualTo(30.0)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `current allocation without matching history makes contribution attribution unavailable`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = listOf(
                    allocation(id = "allocation-a", goalId = goal.id, amount = 60.0)
                ),
                histories = emptyList(),
                transactions = listOf(
                    transaction(id = "unattributable", amount = 50.0, dateMillis = now - 1_000L)
                ),
                fundedAmount = 50.0
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.contributionActivity.recentRows).isEmpty()
            assertThat(scene.freshnessReason).contains("attribution")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `addressed asset cannot publish recent activity or pace without exhaustive ledger proof`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = listOf(
                    allocation(id = "allocation-a", goalId = goal.id, amount = 100.0)
                ),
                histories = listOf(
                    history(
                        id = "history-a",
                        goalId = goal.id,
                        amount = 100.0,
                        timestamp = now - 10_000L
                    )
                ),
                transactions = listOf(
                    transaction(id = "manual-row", amount = 10.0, dateMillis = now - 1_000L)
                ),
                fundedAmount = 10.0,
                assetAddress = "0x1234"
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.contributionActivity.recentRows).isEmpty()
            assertThat(scene.contributionActivity.monthContributionSum.toDouble()).isEqualTo(0.0)
            assertThat(scene.forecastRisk.projectedAmount).isNull()
            assertThat(scene.freshnessReason).contains("ledger")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `provider row cannot publish recent activity or pace without exhaustive ledger proof`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = listOf(
                    allocation(id = "allocation-a", goalId = goal.id, amount = 100.0)
                ),
                histories = listOf(
                    history(
                        id = "history-a",
                        goalId = goal.id,
                        amount = 100.0,
                        timestamp = now - 10_000L
                    )
                ),
                transactions = listOf(
                    transaction(
                        id = "provider-row",
                        amount = 10.0,
                        dateMillis = now - 1_000L,
                        source = TransactionSource.ON_CHAIN
                    )
                ),
                fundedAmount = 10.0
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.contributionActivity.recentRows).isEmpty()
            assertThat(scene.forecastRisk.projectedAmount).isNull()
            assertThat(scene.freshnessReason).contains("ledger")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `missing rate for used forecast contribution fails forecast closed`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = listOf(
                    allocation(id = "allocation-a", goalId = goal.id, amount = 100.0)
                ),
                histories = listOf(
                    history(
                        id = "history-a",
                        goalId = goal.id,
                        amount = 100.0,
                        timestamp = now - 10_000L
                    )
                ),
                transactions = listOf(
                    transaction(id = "recent-deposit", amount = 10.0, dateMillis = now - 1_000L)
                ),
                fundedAmount = 10.0,
                assetCurrency = "BTC",
                exchangeRateFailure = IllegalStateException("BTC/USD rate unavailable")
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.STALE)
            assertThat(scene.forecastRisk.moduleState).isEqualTo(GoalDashboardModuleState.ERROR)
            assertThat(scene.forecastRisk.status).isNull()
            assertThat(scene.forecastRisk.confidence).isNull()
            assertThat(scene.forecastRisk.projectedAmount).isNull()
            assertThat(scene.forecastRisk.whyStatusCopyKey).isNull()
            assertThat(scene.forecastRisk.errorReasonCode).isEqualTo("missing_exchange_rate")
            assertThat(scene.snapshot.status).isNull()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @ParameterizedTest(name = "{0} source failure is a hard error")
    @ValueSource(strings = ["transactions", "allocation_history"])
    fun `financial source failure cannot become fresh zero activity`(failedSource: String) = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = emptyList(),
                histories = emptyList(),
                transactions = emptyList(),
                fundedAmount = 10.0,
                failedSource = failedSource
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.freshnessReason).contains(failedSource)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `real goal progress transaction source failure becomes a hard error`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val fixture = realProgressSourceFailureFixture(goal(id = "goal-a"))

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.freshnessReason).contains("transactions")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `retry resubscribes a failed cold financial source`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            var historyCollections = 0
            val historySource: Flow<List<AllocationHistory>> = flow {
                historyCollections += 1
                if (historyCollections == 1) {
                    throw IllegalStateException("allocation history source unavailable")
                }
                emit(emptyList())
            }
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = emptyList(),
                histories = emptyList(),
                transactions = emptyList(),
                fundedAmount = 10.0,
                allocationHistorySource = historySource
            )

            advanceUntilIdle()
            assertThat(fixture.viewModel.uiState.value.sceneModel?.freshness)
                .isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(historyCollections).isEqualTo(1)

            fixture.viewModel.refresh()
            advanceUntilIdle()

            assertThat(historyCollections).isEqualTo(2)
            assertThat(fixture.viewModel.uiState.value.sceneModel?.freshness)
                .isEqualTo(DataFreshnessState.FRESH)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `allocation validation failure cannot become fresh`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val goal = goal(id = "goal-a")
            val fixture = fixture(
                goal = goal,
                allocations = emptyList(),
                histories = emptyList(),
                transactions = emptyList(),
                fundedAmount = 10.0,
                validationFailure = true
            )

            advanceUntilIdle()

            val scene = fixture.viewModel.uiState.value.sceneModel
            assertThat(scene).isNotNull()
            assertThat(scene!!.freshness).isEqualTo(DataFreshnessState.HARD_ERROR)
            assertThat(scene.freshnessReason).contains("validation")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `refresh cancellation cannot publish a stale hard error`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val goal = goal(id = "goal-a")
            val targetAllocation = allocation(
                id = "allocation-a",
                goalId = goal.id,
                amount = 60.0
            )
            val firstLookupStarted = CompletableDeferred<Unit>()
            val latestLookupStarted = CompletableDeferred<Unit>()
            val latestAsset = CompletableDeferred<Asset?>()
            var lookupCount = 0
            val fixture = fixture(
                goal = goal,
                allocations = listOf(targetAllocation),
                histories = listOf(
                    history(
                        id = "history-a",
                        goalId = goal.id,
                        amount = targetAllocation.amount,
                        timestamp = now - 1_000L
                    )
                ),
                transactions = emptyList(),
                fundedAmount = 10.0,
                assetLookup = {
                    lookupCount += 1
                    if (lookupCount == 1) {
                        firstLookupStarted.complete(Unit)
                        awaitCancellation()
                    } else {
                        latestLookupStarted.complete(Unit)
                        latestAsset.await()
                    }
                }
            )

            runCurrent()
            assertThat(firstLookupStarted.isCompleted).isTrue()

            fixture.viewModel.refresh()
            runCurrent()

            assertThat(latestLookupStarted.isCompleted).isTrue()
            assertThat(fixture.viewModel.uiState.value.sceneModel).isNull()

            latestAsset.complete(
                Asset(
                    id = "shared-asset",
                    currency = "USD",
                    address = null,
                    chainId = null,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
            advanceUntilIdle()

            assertThat(lookupCount).isEqualTo(2)
            assertThat(fixture.viewModel.uiState.value.sceneModel?.freshness)
                .isEqualTo(DataFreshnessState.FRESH)
        } finally {
            Dispatchers.resetMain()
        }
    }

    private fun fixture(
        goal: Goal,
        allocations: List<Allocation>,
        histories: List<AllocationHistory>,
        transactions: List<Transaction>,
        fundedAmount: Double,
        failedSource: String? = null,
        allocationHistorySource: Flow<List<AllocationHistory>>? = null,
        validationFailure: Boolean = false,
        assetLookup: (suspend () -> Asset?)? = null,
        assetCurrency: String = "USD",
        assetAddress: String? = null,
        exchangeRateFailure: Throwable? = null
    ): Fixture {
        val progressUseCase = mockk<GetGoalProgressUseCase>()
        val allocationRepository = mockk<AllocationRepository>()
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>()
        val assetRepository = mockk<AssetRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()
        val validationService = mockk<AllocationValidationService>()

        every { progressUseCase.getProgressFlow(goal.id) } returns flowOf(
            GoalWithProgress(
                goal = goal,
                allocatedAmount = allocations
                    .filter { it.goalId == goal.id }
                    .sumOf { it.amount },
                fundedAmount = fundedAmount,
                progress = goal.progressFromFunded(fundedAmount)
            )
        )
        every { allocationRepository.getAllocationsForGoalListFlow(goal.id) } returns flowOf(
            allocations.filter { it.goalId == goal.id }
        )
        every { allocationRepository.getAllAllocationsFlow() } returns flowOf(allocations)
        coEvery { allocationRepository.getAllocationsForGoal(goal.id) } returns
            allocations.filter { it.goalId == goal.id }
        every { allocationHistoryRepository.getAll() } returns (
            allocationHistorySource ?: if (failedSource == "allocation_history") {
                flow { throw IllegalStateException("allocation history source unavailable") }
            } else {
                flowOf(histories)
            }
            )
        every { transactionRepository.getAllTransactions() } returns if (
            failedSource == "transactions"
        ) {
            flow { throw IllegalStateException("transactions source unavailable") }
        } else {
            flowOf(transactions)
        }
        if (assetLookup == null) {
            coEvery { assetRepository.getAssetById("shared-asset") } returns Asset(
                id = "shared-asset",
                currency = assetCurrency,
                address = assetAddress,
                chainId = null,
                createdAt = 1L,
                updatedAt = 1L
            )
        } else {
            coEvery {
                assetRepository.getAssetById("shared-asset")
            } coAnswers {
                assetLookup()
            }
        }
        if (exchangeRateFailure == null) {
            coEvery { exchangeRateRepository.fetchRate(any(), any()) } returns 1.0
        } else {
            coEvery {
                exchangeRateRepository.fetchRate(any(), any())
            } throws exchangeRateFailure
        }
        if (validationFailure) {
            coEvery {
                validationService.getOverAllocatedAssets()
            } throws IllegalStateException("allocation validation unavailable")
        } else {
            coEvery { validationService.getOverAllocatedAssets() } returns emptyList()
        }

        val viewModel = GoalDashboardViewModel(
            savedStateHandle = SavedStateHandle(mapOf("goalId" to goal.id)),
            getGoalProgressUseCase = progressUseCase,
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            assetRepository = assetRepository,
            transactionRepository = transactionRepository,
            exchangeRateRepository = exchangeRateRepository,
            allocationValidationService = validationService,
            contributionAttributionCalculator = GoalContributionAttributionCalculator(
                FundedDeltaAttributionCalculator()
            ),
            sceneAssembler = GoalDashboardSceneAssembler(GoalDashboardNextActionResolver()),
            telemetryTracker = mockk<NavigationTelemetryTracker>(relaxed = true)
        )
        return Fixture(viewModel = viewModel)
    }

    private fun realProgressSourceFailureFixture(goal: Goal): Fixture {
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>()
        val assetRepository = mockk<AssetRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()
        val validationService = mockk<AllocationValidationService>()

        every { goalRepository.getGoalByIdFlow(goal.id) } returns flowOf(goal)
        coEvery { goalRepository.getGoalById(goal.id) } returns goal
        every {
            allocationRepository.getAllocationsForGoalListFlow(goal.id)
        } returns flowOf(emptyList())
        every { allocationRepository.getAllAllocationsFlow() } returns flowOf(emptyList())
        every {
            transactionRepository.getAllTransactions()
        } returns flow { throw IllegalStateException("transactions financial source unavailable") }
        every { assetRepository.getAllAssets() } returns flowOf(emptyList())
        every { onChainBalanceRepository.observeBalanceInvalidations() } returns flowOf(0L)
        every { exchangeRateRepository.observeRateInvalidations() } returns flowOf(0L)
        every { allocationHistoryRepository.getAll() } returns flowOf(emptyList())
        coEvery { validationService.getOverAllocatedAssets() } returns emptyList()

        val progressUseCase = GetGoalProgressUseCase(
            goalRepository = goalRepository,
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            exchangeRateRepository = exchangeRateRepository
        )
        val viewModel = GoalDashboardViewModel(
            savedStateHandle = SavedStateHandle(mapOf("goalId" to goal.id)),
            getGoalProgressUseCase = progressUseCase,
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            assetRepository = assetRepository,
            transactionRepository = transactionRepository,
            exchangeRateRepository = exchangeRateRepository,
            allocationValidationService = validationService,
            contributionAttributionCalculator = GoalContributionAttributionCalculator(
                FundedDeltaAttributionCalculator()
            ),
            sceneAssembler = GoalDashboardSceneAssembler(GoalDashboardNextActionResolver()),
            telemetryTracker = mockk<NavigationTelemetryTracker>(relaxed = true)
        )
        return Fixture(viewModel = viewModel)
    }

    private fun goal(id: String): Goal = Goal(
        id = id,
        name = id,
        currency = "USD",
        targetAmount = 100.0,
        deadline = LocalDate.now().plusMonths(6),
        startDate = LocalDate.now().minusMonths(1),
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

    private fun allocation(id: String, goalId: String, amount: Double): Allocation = Allocation(
        id = id,
        assetId = "shared-asset",
        goalId = goalId,
        amount = amount,
        createdAt = 1L,
        lastModifiedAt = 1L
    )

    private fun history(
        id: String,
        goalId: String,
        amount: Double,
        timestamp: Long
    ): AllocationHistory = AllocationHistory(
        id = id,
        assetId = "shared-asset",
        goalId = goalId,
        amount = amount,
        monthLabel = "2026-07",
        timestamp = timestamp,
        createdAt = timestamp
    )

    private fun transaction(
        id: String,
        amount: Double,
        dateMillis: Long,
        source: TransactionSource = TransactionSource.MANUAL
    ): Transaction = Transaction(
        id = id,
        assetId = "shared-asset",
        amount = amount,
        dateMillis = dateMillis,
        source = source,
        externalId = null,
        counterparty = null,
        comment = "deposit",
        createdAt = dateMillis
    )

    private data class Fixture(
        val viewModel: GoalDashboardViewModel
    )
}
