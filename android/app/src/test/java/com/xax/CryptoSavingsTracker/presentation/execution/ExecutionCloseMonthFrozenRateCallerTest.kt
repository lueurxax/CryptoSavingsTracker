package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AddAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AssetAllocationStatus
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.UpdateAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionContributionCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.StartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoStartExecutionUseCase
import com.xax.CryptoSavingsTracker.presentation.assets.AssetSharingViewModel
import com.xax.CryptoSavingsTracker.presentation.common.DeadlineTimeSource
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.launch
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ExecutionCloseMonthFrozenRateCallerTest {
    private val mainTestScheduler = TestCoroutineScheduler()
    private val mainDispatcher = StandardTestDispatcher(mainTestScheduler)

    @BeforeEach
    fun setUpMainDispatcher() {
        Dispatchers.setMain(mainDispatcher)
    }

    @AfterEach
    fun tearDownMainDispatcher() {
        Dispatchers.resetMain()
    }

    @Test
    fun `execution caller suggests one BTC from frozen rate instead of half BTC from live divergence`() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            Dispatchers.setMain(dispatcher)

            try {
                val session = session(assetRates = frozenRates())
                val sessions = mockk<GetExecutionSessionUseCase>()
                every { sessions.currentExecuting() } returns flowOf(session)
                val settings = mockk<MonthlyPlanningSettings>()
                every { settings.executionDisplayCurrency } returns "USD"
                val completed = mockk<CompletedExecutionRepository>()
                every { completed.getAll() } returns flowOf(emptyList())
                val goals = mockk<GoalRepository>()
                every { goals.getActiveGoals() } returns flowOf(emptyList())

                val viewModel = ExecutionViewModel(
                    startExecutionUseCase = mockk<StartExecutionUseCase>(),
                    getExecutionSessionUseCase = sessions,
                    completeExecutionUseCase = mockk<CompleteExecutionUseCase>(),
                    undoExecutionUseCase = mockk<UndoExecutionUseCase>(),
                    undoStartExecutionUseCase = mockk<UndoStartExecutionUseCase>(),
                    completedExecutionRepository = completed,
                    monthlyPlanningSettings = settings,
                    executionContributionCalculator = ExecutionContributionCalculatorUseCase(),
                    getAssetsUseCase = mockk<GetAssetsUseCase>(),
                    allocationRepository = mockk<AllocationRepository>(),
                    goalRepository = goals,
                    deadlineTimeSource = mockk {
                        every { nowMillis() } answers { testScheduler.currentTime }
                    }
                )

                val suggestion = viewModel.suggestedContributionAmount(
                    goal = session.goals.single(),
                    assetId = "btc-asset"
                )

                assertThat(suggestion).isEqualTo(1.0)
            } finally {
                Dispatchers.setMain(mainDispatcher)
            }
        }

    @Test
    fun `unavailable execution exposes recovery and rejects completion and contribution suggestions`() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            Dispatchers.setMain(dispatcher)
            var uiStateCollector: Job? = null

            try {
                val unavailable = session(
                    assetRates = frozenRates(),
                    isProgressAvailable = false
                )
                val sessions = mockk<GetExecutionSessionUseCase>()
                every { sessions.currentExecuting() } returns flowOf(unavailable)
                val settings = mockk<MonthlyPlanningSettings>()
                every { settings.executionDisplayCurrency } returns "USD"
                val completed = mockk<CompletedExecutionRepository>()
                every { completed.getAll() } returns flowOf(emptyList())
                val goals = mockk<GoalRepository>()
                every { goals.getActiveGoals() } returns flowOf(emptyList())
                val complete = mockk<CompleteExecutionUseCase>(relaxed = true)
                val timeSource = mockk<DeadlineTimeSource> {
                    every { nowMillis() } answers { testScheduler.currentTime }
                }

                val viewModel = ExecutionViewModel(
                    startExecutionUseCase = mockk<StartExecutionUseCase>(),
                    getExecutionSessionUseCase = sessions,
                    completeExecutionUseCase = complete,
                    undoExecutionUseCase = mockk<UndoExecutionUseCase>(),
                    undoStartExecutionUseCase = mockk<UndoStartExecutionUseCase>(),
                    completedExecutionRepository = completed,
                    monthlyPlanningSettings = settings,
                    executionContributionCalculator = ExecutionContributionCalculatorUseCase(),
                    getAssetsUseCase = mockk<GetAssetsUseCase>(),
                    allocationRepository = mockk<AllocationRepository>(),
                    goalRepository = goals,
                    deadlineTimeSource = timeSource
                )
                uiStateCollector = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                    viewModel.uiState.collect { }
                }
                advanceUntilIdle()

                assertThat(viewModel.uiState.value.isProgressAvailable).isFalse()
                assertThat(viewModel.uiState.value.canComplete).isFalse()
                assertThat(viewModel.uiState.value.canUndoStart).isTrue()
                assertThat(viewModel.uiState.value.currentFocusGoal).isNull()
                assertThat(viewModel.uiState.value.remainingByGoalId).isEmpty()

                viewModel.completeExecution()
                val suggestion = viewModel.suggestedContributionAmount(
                    goal = unavailable.goals.single(),
                    assetId = "btc-asset"
                )
                advanceUntilIdle()

                assertThat(suggestion).isNull()
                assertThat(viewModel.uiState.value.error).contains("progress is unavailable")
                coVerify(exactly = 0) { complete(any()) }
            } finally {
                uiStateCollector?.cancelAndJoin()
                Dispatchers.setMain(mainDispatcher)
            }
        }

    @Test
    fun `asset sharing caller fails closed when frozen rate row is missing`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val asset = asset()
            val goal = goal()
            val sessions = mockk<GetExecutionSessionUseCase>()
            every { sessions.currentExecuting() } returns flowOf(session(assetRates = emptyList()))
            val assetRepository = mockk<AssetRepository>()
            coEvery { assetRepository.getAssetById(asset.id) } returns asset
            val allocationRepository = mockk<AllocationRepository>()
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns emptyList()
            val goalRepository = mockk<GoalRepository>()
            every { goalRepository.getAllGoals() } returns flowOf(listOf(goal))
            val validation = mockk<AllocationValidationService>()
            coEvery { validation.getAssetAllocationStatus(asset.id) } returns AssetAllocationStatus(
                asset = asset,
                totalBalance = 10.0,
                totalAllocated = 0.0,
                allocationDelta = 10.0,
                unallocatedAmount = 10.0,
                isFullyAllocated = false,
                isOverAllocated = false
            )

            val viewModel = AssetSharingViewModel(
                savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
                assetRepository = assetRepository,
                goalRepository = goalRepository,
                allocationRepository = allocationRepository,
                allocationValidationService = validation,
                addAllocationUseCase = mockk<AddAllocationUseCase>(),
                updateAllocationUseCase = mockk<UpdateAllocationUseCase>(),
                executionSessionUseCase = sessions,
                executionContributionCalculator = ExecutionContributionCalculatorUseCase()
            )
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.closeMonthSuggestions).isEmpty()
            assertThat(viewModel.uiState.value.conversionWarning).contains("frozen execution rate")
        } finally {
            Dispatchers.setMain(mainDispatcher)
        }
    }

    @Test
    fun `start and completion undo expire at persisted deadlines without repository emissions`() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            Dispatchers.setMain(dispatcher)
            var uiStateCollector: Job? = null

            try {
                val twoHours = 2 * 60 * 60 * 1_000L
                val fortyEightHours = 48 * 60 * 60 * 1_000L
                val sessions = MutableStateFlow(
                    session(
                        assetRates = frozenRates(),
                        canUndoUntilMillis = fortyEightHours
                    )
                )
                val completedRows = MutableStateFlow(
                    listOf(completedExecution(canUndoUntilMillis = twoHours))
                )
                val getSession = mockk<GetExecutionSessionUseCase>()
                every { getSession.currentExecuting() } returns sessions
                val completed = mockk<CompletedExecutionRepository>()
                every { completed.getAll() } returns completedRows
                val settings = mockk<MonthlyPlanningSettings>()
                every { settings.executionDisplayCurrency } returns "USD"
                val goals = mockk<GoalRepository>()
                every { goals.getActiveGoals() } returns flowOf(emptyList())
                val timeSource = mockk<DeadlineTimeSource>()
                every { timeSource.nowMillis() } answers { testScheduler.currentTime }

                val viewModel = ExecutionViewModel(
                    startExecutionUseCase = mockk<StartExecutionUseCase>(),
                    getExecutionSessionUseCase = getSession,
                    completeExecutionUseCase = mockk<CompleteExecutionUseCase>(),
                    undoExecutionUseCase = mockk<UndoExecutionUseCase>(),
                    undoStartExecutionUseCase = mockk<UndoStartExecutionUseCase>(),
                    completedExecutionRepository = completed,
                    monthlyPlanningSettings = settings,
                    executionContributionCalculator = ExecutionContributionCalculatorUseCase(),
                    getAssetsUseCase = mockk<GetAssetsUseCase>(),
                    allocationRepository = mockk<AllocationRepository>(),
                    goalRepository = goals,
                    deadlineTimeSource = timeSource
                )
                uiStateCollector = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                    viewModel.uiState.collect { }
                }
                runCurrent()

                assertThat(viewModel.uiState.value.canUndoStart).isTrue()
                assertThat(viewModel.uiState.value.undoStartDeadlineMillis)
                    .isEqualTo(fortyEightHours)
                assertThat(viewModel.uiState.value.undoableRecordId).isEqualTo("record-1")

                advanceTimeBy(twoHours)
                runCurrent()

                assertThat(viewModel.uiState.value.undoableRecordId).isNull()
                assertThat(viewModel.uiState.value.canUndoStart).isTrue()

                advanceTimeBy(fortyEightHours - twoHours)
                runCurrent()

                assertThat(viewModel.uiState.value.canUndoStart).isFalse()
                assertThat(viewModel.uiState.value.undoStartDeadlineMillis)
                    .isEqualTo(fortyEightHours)
            } finally {
                uiStateCollector?.cancelAndJoin()
                Dispatchers.setMain(mainDispatcher)
            }
        }

    @Test
    fun `asset sharing caller builds suggestion from the active execution matrix`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val asset = asset()
            val goal = goal()
            val sessions = mockk<GetExecutionSessionUseCase>()
            every { sessions.currentExecuting() } returns flowOf(session(assetRates = frozenRates()))
            val assetRepository = mockk<AssetRepository>()
            coEvery { assetRepository.getAssetById(asset.id) } returns asset
            val allocationRepository = mockk<AllocationRepository>()
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns emptyList()
            val goalRepository = mockk<GoalRepository>()
            every { goalRepository.getAllGoals() } returns flowOf(listOf(goal))
            val validation = mockk<AllocationValidationService>()
            coEvery { validation.getAssetAllocationStatus(asset.id) } returns AssetAllocationStatus(
                asset = asset,
                totalBalance = 10.0,
                totalAllocated = 0.0,
                allocationDelta = 10.0,
                unallocatedAmount = 10.0,
                isFullyAllocated = false,
                isOverAllocated = false
            )

            val viewModel = AssetSharingViewModel(
                savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
                assetRepository = assetRepository,
                goalRepository = goalRepository,
                allocationRepository = allocationRepository,
                allocationValidationService = validation,
                addAllocationUseCase = mockk<AddAllocationUseCase>(),
                updateAllocationUseCase = mockk<UpdateAllocationUseCase>(),
                executionSessionUseCase = sessions,
                executionContributionCalculator = ExecutionContributionCalculatorUseCase()
            )
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.closeMonthSuggestions)
                .containsExactly("goal-1", 1.0)
            assertThat(viewModel.uiState.value.conversionWarning).isNull()
        } finally {
            Dispatchers.setMain(mainDispatcher)
        }
    }

    private fun session(
        assetRates: List<ExecutionAssetRate>,
        isProgressAvailable: Boolean = true,
        canUndoUntilMillis: Long = 10_000L
    ): ExecutionSession {
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 1_000.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 200.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = 1_000L
        )
        return ExecutionSession(
            record = ExecutionRecord(
                id = "record-1",
                planId = "plan-1",
                monthLabel = "2026-07",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = 1_000L,
                closedAtMillis = null,
                canUndoUntilMillis = canUndoUntilMillis,
                createdAtMillis = 1_000L,
                updatedAtMillis = 1_000L
            ),
            goals = listOf(
                ExecutionGoalProgress(
                    snapshot = snapshot,
                    contributed = 100.0,
                    plannedAmount = 200.0,
                    isFulfilled = false
                )
            ),
            assetRates = assetRates,
            isProgressAvailable = isProgressAvailable
        )
    }

    private fun completedExecution(canUndoUntilMillis: Long) = CompletedExecution(
        id = "completed-1",
        executionRecordId = "record-1",
        completionEventId = "event-1",
        goalId = "goal-1",
        goalName = "USD goal",
        currency = "USD",
        requiredAmount = 100.0,
        actualAmount = 100.0,
        completedAtMillis = 1L,
        canUndoUntilMillis = canUndoUntilMillis,
        createdAtMillis = 1L
    )

    private fun frozenRates() = listOf(
        ExecutionAssetRate(
            assetId = "btc-asset",
            snapshotCurrency = "USD",
            rate = 100.0,
            capturedAtMillis = 1_000L
        )
    )

    private fun asset() = Asset(
        id = "btc-asset",
        currency = "BTC",
        address = null,
        chainId = "bitcoin",
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun goal() = Goal(
        id = "goal-1",
        name = "USD goal",
        currency = "USD",
        targetAmount = 1_000.0,
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
}
