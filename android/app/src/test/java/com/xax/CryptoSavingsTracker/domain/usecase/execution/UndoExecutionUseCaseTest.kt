package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
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

        coEvery { recordRepo.getCurrentExecutingRecord() } returns flowOf(
            ExecutionRecord(
                id = "active",
                planId = "p1",
                monthLabel = "2025-12",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = 1L,
                closedAtMillis = null,
                createdAtMillis = 1L,
                updatedAtMillis = 1L
            )
        )
        coEvery { completedRepo.getByRecordId(any()) } returns flowOf(emptyList())

        val useCase = UndoExecutionUseCase(
            executionRecordRepository = recordRepo,
            completedExecutionRepository = completedRepo
        )

        val result = useCase("other")

        assertThat(result.isFailure).isTrue()
        coVerify(exactly = 0) { completedRepo.deleteByRecordId(any()) }
        coVerify(exactly = 0) { recordRepo.reopen(any()) }
    }

    @Test
    fun undoExecution_succeedsWithinWindow() = runTest {
        val recordRepo = mockk<ExecutionRecordRepository>(relaxed = true)
        val completedRepo = mockk<CompletedExecutionRepository>(relaxed = true)

        coEvery { recordRepo.getCurrentExecutingRecord() } returns flowOf(null)

        val now = System.currentTimeMillis()
        coEvery { completedRepo.getByRecordId("r1") } returns flowOf(
            listOf(
                CompletedExecution(
                    id = "c1",
                    executionRecordId = "r1",
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
            completedExecutionRepository = completedRepo
        )

        val result = useCase("r1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { completedRepo.deleteByRecordId("r1") }
        coVerify(exactly = 1) { recordRepo.reopen("r1") }
    }
}

