package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
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
        val assetRateRepo = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val transactionRunner = CheckingTransactionRunner()

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

        coEvery { recordRepo.getRecordById("r1") } answers {
            check(transactionRunner.isInside) { "undo-start precondition must run inside the transaction" }
            record
        }
        coEvery { recordRepo.revertToDraft("r1") } returns Unit

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo,
            executionAssetRateRepository = assetRateRepo,
            attributionRecoveryPolicy = mockk(relaxed = true),
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { snapshotRepo.deleteByRecordId("r1") }
        coVerify(exactly = 1) { assetRateRepo.deleteByRecordId("r1") }
        coVerify(exactly = 1) { recordRepo.revertToDraft("r1") }
    }

    @Test
    fun undoStart_failsAfterWindow() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val assetRateRepo = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val now = System.currentTimeMillis()
        val startedAt = now - (60L * 60L * 1000L)
        val record = ExecutionRecord(
            id = "r1",
            planId = "p1",
            monthLabel = "2025-12",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = now - 1L,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )

        coEvery { recordRepo.getRecordById("r1") } returns record
        val recoveryPolicy = mockk<ExecutionAttributionRecoveryPolicy>()
        coEvery { recoveryPolicy.requiresExpiredUndoRecovery(record) } returns false

        val useCase = UndoStartExecutionUseCase(
            executionRecordRepository = recordRepo,
            executionSnapshotRepository = snapshotRepo,
            executionAssetRateRepository = assetRateRepo,
            attributionRecoveryPolicy = recoveryPolicy,
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.undoStartExpired("2025-12"))
        coVerify(exactly = 0) { snapshotRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { assetRateRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.revertToDraft(any()) }
    }

    @Test
    fun `expired active and undo-reopened executions can recover when attribution is unavailable`() = runTest {
        val now = System.currentTimeMillis()
        val records = listOf(
            ExecutionRecord(
                id = "legacy-active",
                planId = "p1",
                monthLabel = "2025-11",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = now - 48L * 60L * 60L * 1000L,
                closedAtMillis = null,
                canUndoUntilMillis = now - 1L,
                createdAtMillis = now - 48L * 60L * 60L * 1000L,
                updatedAtMillis = now - 1L
            ),
            ExecutionRecord(
                id = "undo-reopened",
                planId = "p2",
                monthLabel = "2025-12",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = now - 72L * 60L * 60L * 1000L,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                createdAtMillis = now - 72L * 60L * 60L * 1000L,
                updatedAtMillis = now
            )
        )

        for (record in records) {
            val recordRepo = mockk<ExecutionRecordRepository>(relaxed = true)
            val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
            val rateRepo = mockk<ExecutionAssetRateRepository>(relaxed = true)
            val recoveryPolicy = mockk<ExecutionAttributionRecoveryPolicy>()
            coEvery { recordRepo.getRecordById(record.id) } returns record
            coEvery { recoveryPolicy.requiresExpiredUndoRecovery(record) } returns true

            val result = UndoStartExecutionUseCase(
                executionRecordRepository = recordRepo,
                executionSnapshotRepository = snapshotRepo,
                executionAssetRateRepository = rateRepo,
                attributionRecoveryPolicy = recoveryPolicy,
                transactionRunner = object : ExecutionTransitionTransactionRunner {
                    override suspend fun <T> run(block: suspend () -> T): T = block()
                }
            )(record.id)

            assertThat(result.isSuccess).isTrue()
            coVerify(exactly = 1) { snapshotRepo.deleteByRecordId(record.id) }
            coVerify(exactly = 1) { rateRepo.deleteByRecordId(record.id) }
            coVerify(exactly = 1) { recordRepo.revertToDraft(record.id) }
        }
    }

    @Test
    fun `missing or non-positive start can recover only through attribution recovery policy`() = runTest {
        for ((recordId, startedAtMillis) in listOf("missing-start" to null, "zero-start" to 0L)) {
            val record = ExecutionRecord(
                id = recordId,
                planId = "plan",
                monthLabel = "2026-07",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = startedAtMillis,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                createdAtMillis = 1L,
                updatedAtMillis = 1L
            )
            val records = mockk<ExecutionRecordRepository>(relaxed = true)
            val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
            val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
            val recoveryPolicy = mockk<ExecutionAttributionRecoveryPolicy>()
            coEvery { records.getRecordById(record.id) } returns record
            coEvery { recoveryPolicy.requiresExpiredUndoRecovery(record) } returns true

            val result = UndoStartExecutionUseCase(
                executionRecordRepository = records,
                executionSnapshotRepository = snapshots,
                executionAssetRateRepository = rates,
                attributionRecoveryPolicy = recoveryPolicy,
                transactionRunner = object : ExecutionTransitionTransactionRunner {
                    override suspend fun <T> run(block: suspend () -> T): T = block()
                }
            )(record.id)

            assertThat(result.isSuccess).isTrue()
            coVerify(exactly = 1) { recoveryPolicy.requiresExpiredUndoRecovery(record) }
            coVerify(exactly = 1) { snapshots.deleteByRecordId(record.id) }
            coVerify(exactly = 1) { rates.deleteByRecordId(record.id) }
            coVerify(exactly = 1) { records.revertToDraft(record.id) }
        }
    }

    @Test
    fun undoStart_failsWhenRecordIsNotExecuting() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>()
        val snapshotRepo = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val assetRateRepo = mockk<ExecutionAssetRateRepository>(relaxed = true)
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
            executionAssetRateRepository = assetRateRepo,
            attributionRecoveryPolicy = mockk(relaxed = true),
            transactionRunner = transactionRunner
        )

        val result = useCase("r1")
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.undoStartExpired("2025-12"))
        coVerify(exactly = 0) { snapshotRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { assetRateRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.revertToDraft(any()) }
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
