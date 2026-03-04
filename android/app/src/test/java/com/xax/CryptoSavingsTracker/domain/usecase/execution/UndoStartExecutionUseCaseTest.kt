package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class UndoStartExecutionUseCaseTest {
    @Test
    fun undoStart_succeedsWithinWindow() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val startedAt = System.currentTimeMillis() - (60L * 60L * 1000L)
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )

        coEvery { recordRepo.getRecordById("r1") } returns record
        coEvery { recordRepo.revertToDraft("r1") } returns Unit

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { snapshotRepo.deleteByRecordId("r1") }
        coVerify(exactly = 1) { recordRepo.revertToDraft("r1") }
    }

    @Test
    fun undoStart_failsAfterWindow() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val startedAt = System.currentTimeMillis() - (25L * 60L * 60L * 1000L)
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )

        coEvery { recordRepo.getRecordById("r1") } returns record

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.undoStartExpired("2025-12"))
        coVerify(exactly = 0) { snapshotRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.revertToDraft(any()) }
    }

    @Test
    fun undoStart_failsWhenRecordIsNotExecuting() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val now = System.currentTimeMillis()
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.DRAFT,
            startedAtMillis = now - 60_000,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = now - 60_000,
            updatedAtMillis = now - 60_000
        )
        coEvery { recordRepo.getRecordById("r1") } returns record

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.undoStartExpired("2025-12"))
        coVerify(exactly = 0) { snapshotRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.revertToDraft(any()) }
    }
}
