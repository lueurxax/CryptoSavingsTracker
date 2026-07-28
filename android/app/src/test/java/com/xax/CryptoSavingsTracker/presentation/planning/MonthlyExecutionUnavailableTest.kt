package com.xax.CryptoSavingsTracker.presentation.planning

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.StartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoStartExecutionUseCase
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MonthlyExecutionUnavailableTest {
    @Test
    fun `unavailable session hides progress keeps recovery undo and rejects completion`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val now = System.currentTimeMillis()
            val record = ExecutionRecord(
                id = "legacy-execution",
                planId = "plan",
                monthLabel = "2026-07",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = now - 72L * 60L * 60L * 1000L,
                closedAtMillis = null,
                canUndoUntilMillis = now - 1L,
                createdAtMillis = now - 72L * 60L * 60L * 1000L,
                updatedAtMillis = now
            )
            val sessions = mockk<GetExecutionSessionUseCase>()
            every { sessions.currentExecuting() } returns flowOf(
                ExecutionSession(
                    record = record,
                    goals = emptyList(),
                    isProgressAvailable = false
                )
            )
            val complete = mockk<CompleteExecutionUseCase>(relaxed = true)
            val viewModel = MonthlyExecutionViewModel(
                getExecutionSessionUseCase = sessions,
                startExecutionUseCase = mockk<StartExecutionUseCase>(),
                completeExecutionUseCase = complete,
                undoExecutionUseCase = mockk<UndoExecutionUseCase>(),
                undoStartExecutionUseCase = mockk<UndoStartExecutionUseCase>()
            )
            runCurrent()

            val state = viewModel.uiState.value
            assertThat(state.isProgressAvailable).isFalse()
            assertThat(state.recoveryRequired).isTrue()
            assertThat(state.canComplete).isFalse()
            assertThat(state.showUndoBanner).isTrue()
            assertThat(state.goalProgress).isEmpty()
            assertThat(state.totalPlanned).isNull()
            assertThat(state.totalContributed).isNull()
            assertThat(state.allFulfilled).isFalse()

            viewModel.showCompleteConfirmation()
            viewModel.completeExecution()
            runCurrent()

            assertThat(viewModel.uiState.value.showCompleteConfirmDialog).isFalse()
            assertThat(viewModel.uiState.value.error).contains("progress is unavailable")
            coVerify(exactly = 0) { complete(any()) }
        } finally {
            Dispatchers.resetMain()
        }
    }
}
