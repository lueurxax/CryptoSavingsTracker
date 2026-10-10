package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModelStore
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MonthlyExecutionViewModelTest {
    @Test
    fun `mixed goal currencies do not expose a monetary summary currency`() {
        val usd = ExecutionGoalProgress(
            ExecutionSnapshot("usd", "record", "usd-goal", "USD goal", "USD", 1_000.0,
                0.0, 100.0, false, false, null, 1_000_000L), 50.0, 100.0, false
        )
        val eur = usd.copy(snapshot = usd.snapshot.copy(goalId = "eur-goal", currency = "EUR"))
        val record = ExecutionRecord(
            "record", "plan", "2026-10", ExecutionStatus.EXECUTING,
            1_000_000L, null, null, 1_000_000L, 1_000_000L
        )

        assertThat(MonthlyExecutionUiState(goalProgress = listOf(usd, eur)).summaryCurrency).isNull()
        assertThat(ExecutionSession(record, listOf(usd, eur)).summaryCurrency).isNull()
        assertThat(MonthlyExecutionUiState(goalProgress = listOf(usd)).summaryCurrency).isEqualTo("USD")
        assertThat(ExecutionSession(record, listOf(usd, usd.copy(snapshot = usd.snapshot.copy(currency = "usd"))))
            .summaryCurrency).isEqualTo("USD")
    }

    @Test
    fun `live FX recovery clears conversion errors while preserving unrelated action errors`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val store = ViewModelStore()
        try {
            val record = ExecutionRecord(
                "record", "plan", "2026-10", ExecutionStatus.EXECUTING,
                1_000_000L, null, null, 1_000_000L, 1_000_000L
            )
            val snapshot = ExecutionSnapshot(
                "snapshot", record.id, "goal", "Savings", "USD", 1_000.0,
                0.0, 100.0, false, false, null, 1_000_000L
            )
            val unavailable = ExecutionGoalProgress(snapshot, 0.0, 100.0, false, "FX unavailable")
            val healthy = ExecutionGoalProgress(snapshot, 50.0, 100.0, false)
            val sessions = MutableStateFlow<ExecutionSession?>(ExecutionSession(record, listOf(unavailable)))
            val getSession = mockk<GetExecutionSessionUseCase>()
            every { getSession.currentExecuting() } returns sessions
            val complete = mockk<CompleteExecutionUseCase>()
            coEvery { complete(record.id) } returns Result.failure(IllegalStateException("Save failed"))
            val viewModel = MonthlyExecutionViewModel(
                getSession, mockk(), complete, mockk(), mockk()
            )
            store.put("execution", viewModel)
            runCurrent()
            assertThat(viewModel.uiState.value.goalProgress.single().conversionError).isEqualTo("FX unavailable")
            assertThat(viewModel.uiState.value.canComplete).isFalse()

            sessions.value = ExecutionSession(record, listOf(healthy))
            runCurrent()

            assertThat(viewModel.uiState.value.goalProgress.single().conversionError).isNull()
            assertThat(viewModel.uiState.value.canComplete).isTrue()
            assertThat(viewModel.uiState.value.error).isNull()
            assertThat(viewModel.uiState.value.totalContributed).isEqualTo(50.0)

            viewModel.completeExecution()
            runCurrent()
            assertThat(viewModel.uiState.value.error).isEqualTo("Save failed")
            sessions.value = ExecutionSession(record, listOf(healthy.copy(contributed = 60.0)))
            runCurrent()
            assertThat(viewModel.uiState.value.error).isEqualTo("Save failed")
        } finally {
            store.clear()
            Dispatchers.resetMain()
        }
    }
}
