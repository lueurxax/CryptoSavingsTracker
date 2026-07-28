package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.viewModelScope
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import com.xax.CryptoSavingsTracker.presentation.common.DeadlineTimeSource
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PlanHistoryDeadlineTest {
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
    fun `history undo expires at persisted deadline without repository emission`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        var viewModelToClear: PlanHistoryViewModel? = null

        try {
            val deadline = 168 * 60 * 60 * 1_000L
            val events = MutableStateFlow(
                listOf(
                    CompletionEvent(
                        id = "event-1",
                        executionRecordId = "record-1",
                        monthLabel = "2026-07",
                        sequence = 1,
                        sourceDiscriminator = "manual",
                        completedAtMillis = 1L,
                        completionSnapshotRef = null,
                        createdAtMillis = 1L
                    )
                )
            )
            val completed = MutableStateFlow(
                listOf(
                    CompletedExecution(
                        id = "completed-1",
                        executionRecordId = "record-1",
                        completionEventId = "event-1",
                        goalId = "goal-1",
                        goalName = "Goal",
                        currency = "USD",
                        requiredAmount = 100.0,
                        actualAmount = 100.0,
                        completedAtMillis = 1L,
                        canUndoUntilMillis = deadline,
                        createdAtMillis = 1L
                    )
                )
            )
            val completionEventRepository = mockk<CompletionEventRepository>()
            every { completionEventRepository.getAll() } returns events
            val completedExecutionRepository = mockk<CompletedExecutionRepository>()
            every { completedExecutionRepository.getAll() } returns completed
            val timeSource = mockk<DeadlineTimeSource>()
            every { timeSource.nowMillis() } answers { testScheduler.currentTime }

            val viewModel = PlanHistoryViewModel(
                completionEventRepository = completionEventRepository,
                completedExecutionRepository = completedExecutionRepository,
                undoExecutionUseCase = mockk<UndoExecutionUseCase>(),
                deadlineTimeSource = timeSource
            )
            viewModelToClear = viewModel
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.uiState.collect { }
            }
            runCurrent()

            assertThat(viewModel.uiState.value.groups.single().undoRecordId)
                .isEqualTo("record-1")
            assertThat(viewModel.uiState.value.groups.single().events.single().isUndoAvailable)
                .isTrue()

            advanceTimeBy(deadline)
            runCurrent()

            assertThat(viewModel.uiState.value.groups.single().undoRecordId).isNull()
            assertThat(viewModel.uiState.value.groups.single().events.single().isUndoAvailable)
                .isFalse()
        } finally {
            viewModelToClear?.viewModelScope?.cancel()
            runCurrent()
            Dispatchers.setMain(mainDispatcher)
        }
    }
}
