package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DeleteAssetUseCaseTest {
    @Test
    fun `captured asset cannot be deleted during active execution`() = runTest {
        val fixture = fixture()
        val runner = CheckingTransactionRunner()
        val record = executionRecord()
        every { fixture.records.getAllRecords() } answers {
            check(runner.isInside)
            flowOf(listOf(record))
        }
        every { fixture.rates.getByRecordId(record.id) } returns flowOf(
            listOf(ExecutionAssetRate("asset-1", "USD", 10_000.0, 1_000L))
        )

        val result = fixture.useCase(runner)("asset-1")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("reversible execution")
        coVerify(exactly = 0) { fixture.assets.deleteAsset(any<String>()) }
    }

    @Test
    fun `legacy relevant allocation prevents deletion while completion is undoable`() = runTest {
        val fixture = fixture()
        val record = executionRecord().copy(
            status = ExecutionStatus.CLOSED,
            closedAtMillis = System.currentTimeMillis() - 1_000L,
            canUndoUntilMillis = System.currentTimeMillis() + 60_000L,
            legacyRateSnapshotPending = true
        )
        every { fixture.records.getAllRecords() } returns flowOf(listOf(record))
        every { fixture.rates.getByRecordId(record.id) } returns flowOf(emptyList())
        every { fixture.snapshots.getByRecordId(record.id) } returns flowOf(
            listOf(snapshot(record.id, "goal-1"))
        )
        every { fixture.history.getByAssetId("asset-1") } returns flowOf(
            listOf(allocationHistory("asset-1", "goal-1"))
        )

        val result = fixture.useCase()("asset-1")

        assertThat(result.isFailure).isTrue()
        coVerify(exactly = 0) { fixture.assets.deleteAsset(any<String>()) }
    }

    @Test
    fun `asset unrelated to reversible execution remains deletable`() = runTest {
        val fixture = fixture()
        val record = executionRecord()
        every { fixture.records.getAllRecords() } returns flowOf(listOf(record))
        every { fixture.rates.getByRecordId(record.id) } returns flowOf(
            listOf(ExecutionAssetRate("other-asset", "USD", 1.0, 1_000L))
        )

        val result = fixture.useCase()("asset-1")

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) { fixture.assets.deleteAsset("asset-1") }
    }

    private fun fixture() = Fixture(
        assets = mockk(relaxed = true),
        records = mockk(),
        rates = mockk(),
        snapshots = mockk(relaxed = true),
        history = mockk(relaxed = true)
    )

    private data class Fixture(
        val assets: AssetRepository,
        val records: ExecutionRecordRepository,
        val rates: ExecutionAssetRateRepository,
        val snapshots: ExecutionSnapshotRepository,
        val history: AllocationHistoryRepository
    ) {
        fun useCase(
            runner: ExecutionTransitionTransactionRunner = DirectTransactionRunner
        ) = DeleteAssetUseCase(
            repository = assets,
            executionRecordRepository = records,
            executionAssetRateRepository = rates,
            executionSnapshotRepository = snapshots,
            allocationHistoryRepository = history,
            transactionRunner = runner
        )
    }

    private fun executionRecord() = ExecutionRecord(
        id = "record-1",
        planId = "plan-1",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = System.currentTimeMillis() - 1_000L,
        closedAtMillis = null,
        canUndoUntilMillis = null,
        createdAtMillis = 1_000L,
        updatedAtMillis = 1_000L
    )

    private fun snapshot(recordId: String, goalId: String) = ExecutionSnapshot(
        id = "snapshot-1",
        executionRecordId = recordId,
        goalId = goalId,
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

    private fun allocationHistory(assetId: String, goalId: String) = AllocationHistory(
        id = "history-1",
        assetId = assetId,
        goalId = goalId,
        amount = 1.0,
        monthLabel = "2026-07",
        timestamp = 1_000L,
        createdAt = 1_000L
    )

    private object DirectTransactionRunner : ExecutionTransitionTransactionRunner {
        override suspend fun <T> run(block: suspend () -> T): T = block()
    }

    private class CheckingTransactionRunner : ExecutionTransitionTransactionRunner {
        var isInside = false
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
