package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class UndoExecutionUseCaseTest {
    @Test
    fun undoExecution_failsWhenAnotherExecutionIsActive() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val completedRepo = mockk<CompletedExecutionRepository>()
        val completionEventRepo = mockk<CompletionEventRepository>()
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        coEvery { recordRepo.getCurrentExecutingRecord() } returns flowOf(
            ExecutionRecord(
                id = "active",
                planId = "p1",
                monthLabel = "2025-12",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = 1L,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                createdAtMillis = 1L,
                updatedAtMillis = 1L
            )
        )
        coEvery { completedRepo.getActiveByRecordId(any()) } returns flowOf(emptyList())
        val useCase = UndoExecutionUseCase(
            executionRecordRepository = recordRepo,
            completedExecutionRepository = completedRepo,
            completionEventRepository = completionEventRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("other")

        assertThat(result.isFailure).isTrue()
        coVerify(exactly = 0) { completedRepo.markUndoneByCompletionEventId(any(), any(), any()) }
        coVerify(exactly = 0) { completionEventRepo.markUndone(any(), any(), any()) }
        coVerify(exactly = 0) { recordRepo.reopen(any()) }
    }

    @Test
    fun undoExecution_succeedsWithinWindow() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>(relaxed = true)
        val completedRepo = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepo = mockk<CompletionEventRepository>(relaxed = true)
        val transactionRunner = CheckingTransactionRunner()

        val now = System.currentTimeMillis()
        coEvery { recordRepo.getCurrentExecutingRecord() } answers {
            check(transactionRunner.isInside) { "undo precondition must run inside the transaction" }
            flowOf(null)
        }
        coEvery { recordRepo.getRecordById("r1") } answers {
            check(transactionRunner.isInside) { "undo target lookup must run inside the transaction" }
            ExecutionRecord(
                id = "r1",
                planId = "p1",
                monthLabel = "2025-12",
                status = ExecutionStatus.CLOSED,
                startedAtMillis = now - 1_000,
                closedAtMillis = now,
                canUndoUntilMillis = now + 10_000,
                createdAtMillis = now - 1_000,
                updatedAtMillis = now
            )
        }

        coEvery { completionEventRepo.getLatestOpenByRecordId("r1") } returns CompletionEvent(
            id = "e1",
            executionRecordId = "r1",
            monthLabel = "2025-12",
            sequence = 1,
            sourceDiscriminator = "s1",
            completedAtMillis = now,
            completionSnapshotRef = "snap-1",
            createdAtMillis = now
        )
        coEvery { completedRepo.getActiveByCompletionEventId("e1") } returns flowOf(
            listOf(
                CompletedExecution(
                    id = "c1",
                    executionRecordId = "r1",
                    completionEventId = "e1",
                    goalId = "g1",
                    goalName = "Goal",
                    currency = "USD",
                    requiredAmount = 1.0,
                    actualAmount = 1.0,
                    completedAtMillis = now,
                    canUndoUntilMillis = now + 10_000,
                    createdAtMillis = now
                )
            )
        )

        val useCase = UndoExecutionUseCase(
            executionRecordRepository = recordRepo,
            completedExecutionRepository = completedRepo,
            completionEventRepository = completionEventRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { completionEventRepo.markUndone("e1", any(), "manualUndo") }
        coVerify(exactly = 1) { completedRepo.markUndoneByCompletionEventId("e1", any(), "manualUndo") }
        coVerify(exactly = 1) { recordRepo.reopen("r1") }
    }

    @Test
    fun `recent completion undo can reopen an old unavailable execution and recover to planning`() = runTest {
        val now = System.currentTimeMillis()
        var currentRecord = ExecutionRecord(
            id = "old-execution",
            planId = "plan",
            monthLabel = "2026-05",
            status = ExecutionStatus.CLOSED,
            startedAtMillis = now - 72L * 60L * 60L * 1000L,
            closedAtMillis = now - 1_000L,
            canUndoUntilMillis = now + 60_000L,
            createdAtMillis = now - 72L * 60L * 60L * 1000L,
            updatedAtMillis = now - 1_000L
        )
        val recordRepo = mockk<ExecutionRecordRepository>(relaxed = true)
        val completedRepo = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepo = mockk<CompletionEventRepository>(relaxed = true)
        val runner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }
        coEvery { recordRepo.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { recordRepo.getRecordById(currentRecord.id) } answers { currentRecord }
        coEvery { recordRepo.reopen(currentRecord.id) } answers {
            currentRecord = currentRecord.copy(
                status = ExecutionStatus.EXECUTING,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                updatedAtMillis = now
            )
        }
        coEvery { completionEventRepo.getLatestOpenByRecordId(currentRecord.id) } returns CompletionEvent(
            id = "event",
            executionRecordId = currentRecord.id,
            monthLabel = currentRecord.monthLabel,
            sequence = 1,
            sourceDiscriminator = "source",
            completedAtMillis = now - 1_000L,
            completionSnapshotRef = "snapshot",
            createdAtMillis = now - 1_000L
        )
        coEvery { completedRepo.getActiveByCompletionEventId("event") } returns flowOf(
            listOf(
                CompletedExecution(
                    id = "completed",
                    executionRecordId = currentRecord.id,
                    completionEventId = "event",
                    goalId = "goal",
                    goalName = "Goal",
                    currency = "USD",
                    requiredAmount = 1.0,
                    actualAmount = 1.0,
                    completedAtMillis = now - 1_000L,
                    canUndoUntilMillis = now + 60_000L,
                    createdAtMillis = now - 1_000L
                )
            )
        )

        val undoCompletion = UndoExecutionUseCase(
            executionRecordRepository = recordRepo,
            completedExecutionRepository = completedRepo,
            completionEventRepository = completionEventRepo,
            transactionRunner = runner
        )(currentRecord.id)

        assertThat(undoCompletion.isSuccess).isTrue()
        assertThat(currentRecord.status).isEqualTo(ExecutionStatus.EXECUTING)
        assertThat(currentRecord.canUndoUntilMillis).isNull()

        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val recoveryPolicy = mockk<ExecutionAttributionRecoveryPolicy>()
        coEvery { recoveryPolicy.requiresExpiredUndoRecovery(currentRecord) } returns true
        coEvery { recordRepo.revertToDraft(currentRecord.id) } answers {
            currentRecord = currentRecord.copy(status = ExecutionStatus.DRAFT)
        }

        val undoStart = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshots,
            executionAssetRateRepository = rates,
            attributionRecoveryPolicy = recoveryPolicy,
            transactionRunner = runner
        )(currentRecord.id)

        assertThat(undoStart.isSuccess).isTrue()
        assertThat(currentRecord.status).isEqualTo(ExecutionStatus.DRAFT)
        coVerify(exactly = 1) { snapshots.deleteByRecordId("old-execution") }
        coVerify(exactly = 1) { rates.deleteByRecordId("old-execution") }
    }

    @Test
    fun undoExecution_failsWithCopyCatalogMessageWhenExpired() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>(relaxed = true)
        val completedRepo = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepo = mockk<CompletionEventRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val now = System.currentTimeMillis()
        coEvery { recordRepo.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { recordRepo.getRecordById("r1") } returns ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.CLOSED,
            startedAtMillis = now - 10_000,
            closedAtMillis = now - 9_000,
            canUndoUntilMillis = now - 1_000,
            createdAtMillis = now - 10_000,
            updatedAtMillis = now - 9_000
        )
        coEvery { completionEventRepo.getLatestOpenByRecordId("r1") } returns CompletionEvent(
            id = "e1",
            executionRecordId = "r1",
            monthLabel = "2025-12",
            sequence = 1,
            sourceDiscriminator = "s1",
            completedAtMillis = now - 9_000,
            completionSnapshotRef = "snap-1",
            createdAtMillis = now - 9_000
        )
        coEvery { completedRepo.getActiveByCompletionEventId("e1") } returns flowOf(
            listOf(
                CompletedExecution(
                    id = "c1",
                    executionRecordId = "r1",
                    completionEventId = "e1",
                    goalId = "g1",
                    goalName = "Goal",
                    currency = "USD",
                    requiredAmount = 1.0,
                    actualAmount = 1.0,
                    completedAtMillis = now - 9_000,
                    canUndoUntilMillis = now - 1_000,
                    createdAtMillis = now - 9_000
                )
            )
        )

        val useCase = UndoExecutionUseCase(
            executionRecordRepository = recordRepo,
            completedExecutionRepository = completedRepo,
            completionEventRepository = completionEventRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.undoCompletionExpired("2025-12"))
    }

    private class CheckingTransactionRunner : ExecutionTransitionTransactionRunner {
        var isInside: Boolean = false
            private set

        override suspend fun <T> run(block: suspend () -> T): T {
            isInside = true
            return try {
                block()
            } finally {
                isInside = false
            }
        }
    }
}
