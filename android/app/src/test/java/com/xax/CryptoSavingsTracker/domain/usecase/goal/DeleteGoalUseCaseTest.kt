package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DeleteGoalUseCaseTest {
    @Test
    fun `goal with active execution snapshot cannot be hard deleted`() = runTest {
        val fixture = fixture()
        every { fixture.snapshots.getByGoalId("goal-1") } returns flowOf(
            listOf(snapshot())
        )

        val result = fixture.useCase()("goal-1")

        assertBlocked(fixture, result)
    }

    @Test
    fun `goal with completed execution history cannot be hard deleted`() = runTest {
        val fixture = fixture()
        every { fixture.snapshots.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.completed.getByGoalId("goal-1") } returns flowOf(
            listOf(completed().copy(canUndoUntilMillis = 0L))
        )

        val result = fixture.useCase()("goal-1")

        assertBlocked(fixture, result)
    }

    @Test
    fun `goal with undoable completion cannot be hard deleted`() = runTest {
        val fixture = fixture()
        every { fixture.snapshots.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.completed.getByGoalId("goal-1") } returns flowOf(
            listOf(completed().copy(canUndoUntilMillis = Long.MAX_VALUE))
        )

        val result = fixture.useCase()("goal-1")

        assertBlocked(fixture, result)
    }

    @Test
    fun `allocation history without execution evidence does not block goal deletion`() = runTest {
        val fixture = fixture()
        every { fixture.snapshots.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.completed.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.history.getByGoalId("goal-1") } returns flowOf(
            listOf(history())
        )

        val result = fixture.useCase()("goal-1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { fixture.goals.deleteGoal("goal-1") }
        coVerify(exactly = 1) { fixture.scheduler.cancel("goal-1") }
    }

    @Test
    fun `goal without execution evidence is deleted before reminder cancellation`() = runTest {
        val fixture = fixture()
        every { fixture.snapshots.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.completed.getByGoalId("goal-1") } returns flowOf(emptyList())
        every { fixture.history.getByGoalId("goal-1") } returns flowOf(emptyList())

        val result = fixture.useCase()("goal-1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { fixture.goals.deleteGoal("goal-1") }
        coVerify(exactly = 1) { fixture.scheduler.cancel("goal-1") }
    }

    private fun assertBlocked(fixture: Fixture, result: Result<Unit>) {
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution history")
        coVerify(exactly = 0) { fixture.goals.deleteGoal(any<String>()) }
        coVerify(exactly = 0) { fixture.scheduler.cancel(any()) }
    }

    private fun fixture() = Fixture(
        goals = mockk(relaxed = true),
        scheduler = mockk(relaxed = true),
        snapshots = mockk(relaxed = true),
        completed = mockk(relaxed = true),
        history = mockk(relaxed = true)
    )

    private data class Fixture(
        val goals: GoalRepository,
        val scheduler: GoalReminderScheduler,
        val snapshots: ExecutionSnapshotRepository,
        val completed: CompletedExecutionRepository,
        val history: AllocationHistoryRepository
    ) {
        fun useCase() = DeleteGoalUseCase(
            repository = goals,
            reminderScheduler = scheduler,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            transactionRunner = DirectTransactionRunner
        )
    }

    private fun snapshot() = ExecutionSnapshot(
        id = "snapshot-1",
        executionRecordId = "record-1",
        goalId = "goal-1",
        goalName = "Goal",
        currency = "USD",
        targetAmount = 100.0,
        currentTotalAtStart = 0.0,
        requiredAmount = 10.0,
        isProtected = false,
        isSkipped = false,
        customAmount = null,
        createdAtMillis = 1_000L
    )

    private fun completed() = CompletedExecution(
        id = "completed-1",
        executionRecordId = "record-1",
        goalId = "goal-1",
        goalName = "Goal",
        currency = "USD",
        requiredAmount = 10.0,
        actualAmount = 10.0,
        completedAtMillis = 1_000L,
        canUndoUntilMillis = 2_000L,
        createdAtMillis = 1_000L
    )

    private fun history() = AllocationHistory(
        id = "history-1",
        assetId = "asset-1",
        goalId = "goal-1",
        amount = 1.0,
        monthLabel = "2026-07",
        timestamp = 1_000L,
        createdAt = 1_000L
    )

    private object DirectTransactionRunner : ExecutionTransitionTransactionRunner {
        override suspend fun <T> run(block: suspend () -> T): T = block()
    }
}
