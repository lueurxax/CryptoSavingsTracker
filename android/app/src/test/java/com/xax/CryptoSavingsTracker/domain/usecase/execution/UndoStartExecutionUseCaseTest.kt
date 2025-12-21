package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
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

        val startedAt = System.currentTimeMillis() - (60L * 60L * 1000L)
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )

        coEvery { recordRepo.getRecordById("r1") } returns record
        coEvery { recordRepo.revertToDraft("r1") } returns Unit

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo
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

        val startedAt = System.currentTimeMillis() - (25L * 60L * 60L * 1000L)
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )

        coEvery { recordRepo.getRecordById("r1") } returns record

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo
        )

        val result = useCase("r1")

        assertThat(result.isFailure).isTrue()
        coVerify(exactly = 0) { snapshotRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.revertToDraft(any()) }
    }
}

