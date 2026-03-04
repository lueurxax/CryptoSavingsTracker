package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class CompleteExecutionUseCaseTest {

    @Test
    fun completeExecution_createsEventAndAppendsCompletedRows() = runTest {
        val executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
        val executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completedExecutionRepository = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepository = mockk<CompletionEventRepository>(relaxed = true)
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val now = System.currentTimeMillis()
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-01",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = now - 10_000,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = now - 10_000,
            updatedAtMillis = now - 10_000
        )
        val snapshots = listOf(
            ExecutionSnapshot(
                id = "s1",
                executionRecordId = record.id,
                goalId = "g1",
                goalName = "Goal 1",
                currency = "USD",
                targetAmount = 100.0,
                currentTotalAtStart = 20.0,
                requiredAmount = 40.0,
                isProtected = false,
                isSkipped = false,
                customAmount = null,
                createdAtMillis = now - 9_000
            ),
            ExecutionSnapshot(
                id = "s2",
                executionRecordId = record.id,
                goalId = "g2",
                goalName = "Goal 2",
                currency = "USD",
                targetAmount = 200.0,
                currentTotalAtStart = 50.0,
                requiredAmount = 60.0,
                isProtected = false,
                isSkipped = false,
                customAmount = null,
                createdAtMillis = now - 9_000
            )
        )

        coEvery { executionRecordRepository.getRecordById(record.id) } returns record
        coEvery { executionSnapshotRepository.getByRecordId(record.id) } returns flowOf(snapshots)
        coEvery { completionEventRepository.getNextSequence(record.id) } returns 3
        coEvery { transactionRepository.getAllTransactions() } returns flowOf(emptyList<Transaction>())
        coEvery { allocationHistoryRepository.getAll() } returns flowOf(emptyList<AllocationHistory>())

        var insertedEvent: CompletionEvent? = null
        coEvery { completionEventRepository.insert(any()) } answers {
            insertedEvent = firstArg()
            Unit
        }

        val appendedRows = mutableListOf<com.xax.CryptoSavingsTracker.domain.model.CompletedExecution>()
        coEvery { completedExecutionRepository.append(any()) } answers {
            appendedRows.clear()
            appendedRows.addAll(firstArg())
            Unit
        }

        val useCase = CompleteExecutionUseCase(
            executionRecordRepository = executionRecordRepository,
            executionSnapshotRepository = executionSnapshotRepository,
            completedExecutionRepository = completedExecutionRepository,
            completionEventRepository = completionEventRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            transactionRepository = transactionRepository,
            transactionRunner = transactionRunner
        )

        val result = useCase(record.id)

        assertThat(result.isSuccess).isTrue()
        assertThat(insertedEvent).isNotNull()
        assertThat(insertedEvent!!.executionRecordId).isEqualTo(record.id)
        assertThat(insertedEvent!!.monthLabel).isEqualTo(record.monthLabel)
        assertThat(insertedEvent!!.sequence).isEqualTo(3)

        assertThat(appendedRows).hasSize(2)
        assertThat(appendedRows.map { it.goalId }).containsExactly("g1", "g2")
        assertThat(appendedRows.map { it.completionEventId }.distinct()).containsExactly(insertedEvent!!.id)

        coVerify(exactly = 1) { completionEventRepository.insert(any()) }
        coVerify(exactly = 1) { completedExecutionRepository.append(any()) }
        coVerify(exactly = 1) { executionRecordRepository.close(record.id, any(), any()) }
    }

    @Test
    fun completeExecution_failsWhenRecordIsNotExecuting() = runTest {
        val executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
        val executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completedExecutionRepository = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepository = mockk<CompletionEventRepository>(relaxed = true)
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }

        val record = ExecutionRecord(
            id = "record-closed",
            planId = "plan-1",
            monthLabel = "2026-01",
            status = ExecutionStatus.CLOSED,
            startedAtMillis = null,
            closedAtMillis = System.currentTimeMillis(),
            canUndoUntilMillis = null,
            createdAtMillis = System.currentTimeMillis(),
            updatedAtMillis = System.currentTimeMillis()
        )

        coEvery { executionRecordRepository.getRecordById(record.id) } returns record

        val useCase = CompleteExecutionUseCase(
            executionRecordRepository = executionRecordRepository,
            executionSnapshotRepository = executionSnapshotRepository,
            completedExecutionRepository = completedExecutionRepository,
            completionEventRepository = completionEventRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            transactionRepository = transactionRepository,
            transactionRunner = transactionRunner
        )

        val result = useCase(record.id)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.finishBlockedNoExecuting())
        coVerify(exactly = 0) { completionEventRepository.insert(any()) }
        coVerify(exactly = 0) { completedExecutionRepository.append(any()) }
    }
}
