package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class CompleteExecutionUseCaseTest {
    @Test
    fun `completion ignores pre-start deallocated assets outside persisted rate scope`() = runTest {
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>(relaxed = true)
        val transactions = mockk<TransactionRepository>(relaxed = true)
        val executionRates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val legacyBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val planningSettings = mockk<MonthlyPlanningSettings> {
            every { undoGracePeriodHours } returns 0
        }
        val startedAt = 1_000L
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt,
            legacyRateSnapshotPending = false
        )
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = record.id,
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 100.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )

        coEvery { records.getRecordById(record.id) } returns record
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        coEvery { events.getNextSequence(record.id) } returns 1
        every { transactions.getAllTransactions() } returns flowOf(
            listOf(
                Transaction(
                    id = "old-asset-deposit",
                    assetId = "deallocated-before-start",
                    amount = 1.0,
                    dateMillis = startedAt + 1,
                    source = com.xax.CryptoSavingsTracker.domain.model.TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1
                )
            )
        )
        every { allocationHistory.getAll() } returns flowOf(
            listOf(
                AllocationHistory(
                    id = "old-allocation",
                    assetId = "deallocated-before-start",
                    goalId = snapshot.goalId,
                    amount = 1.0,
                    monthLabel = record.monthLabel,
                    timestamp = startedAt - 100,
                    createdAt = startedAt - 100
                ),
                AllocationHistory(
                    id = "old-deallocation",
                    assetId = "deallocated-before-start",
                    goalId = snapshot.goalId,
                    amount = 0.0,
                    monthLabel = record.monthLabel,
                    timestamp = startedAt - 10,
                    createdAt = startedAt - 10
                ),
                AllocationHistory(
                    id = "current-allocation",
                    assetId = "allocated-at-start",
                    goalId = snapshot.goalId,
                    amount = 1.0,
                    monthLabel = record.monthLabel,
                    timestamp = startedAt - 10,
                    createdAt = startedAt - 10
                )
            )
        )
        every { allocations.getAllAllocationsFlow() } returns flowOf(
            listOf(
                Allocation(
                    id = "current-allocation",
                    assetId = "allocated-at-start",
                    goalId = snapshot.goalId,
                    amount = 1.0,
                    createdAt = startedAt - 10,
                    lastModifiedAt = startedAt - 10
                )
            )
        )
        every { executionRates.getByRecordId(record.id) } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = "allocated-at-start",
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )
        var appendedActualAmount: Double? = null
        var appendedUndoUntilMillis: Long? = null
        coEvery { completed.append(any()) } answers {
            val row = firstArg<List<com.xax.CryptoSavingsTracker.domain.model.CompletedExecution>>()
                .single()
            appendedActualAmount = row.actualAmount
            appendedUndoUntilMillis = row.canUndoUntilMillis
            Unit
        }
        var closedAtMillis: Long? = null
        var closedUndoUntilMillis: Long? = null
        coEvery { records.close(record.id, any(), any()) } answers {
            closedAtMillis = secondArg()
            closedUndoUntilMillis = thirdArg()
            Unit
        }

        val result = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = legacyBackfill,
            planningSettings = planningSettings
        )(record.id)

        assertThat(result.isSuccess).isTrue()
        assertThat(appendedActualAmount).isEqualTo(0.0)
        assertThat(closedUndoUntilMillis).isEqualTo(closedAtMillis)
        assertThat(appendedUndoUntilMillis).isEqualTo(closedAtMillis)
        coVerify(exactly = 1) { records.close(record.id, any(), any()) }
    }

    @Test
    fun completeExecution_createsEventAndAppendsCompletedRows() = runTest {
        val executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
        val executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completedExecutionRepository = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepository = mockk<CompletionEventRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>()
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val executionAssetRateRepository = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val legacyRateSnapshotBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val planningSettings = mockk<MonthlyPlanningSettings> {
            every { undoGracePeriodHours } returns 48
        }
        val transactionRunner = CheckingTransactionRunner()

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
            updatedAtMillis = now - 10_000,
            legacyRateSnapshotPending = true
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
        coEvery { transactionRepository.getAllTransactions() } answers {
            check(transactionRunner.isInside) {
                "completion transaction snapshot must be read inside the transaction"
            }
            flowOf(
                listOf(
                    Transaction(
                        id = "unrelated-transaction",
                        assetId = "unrelated-asset",
                        amount = 1.0,
                        dateMillis = now - 1_000,
                        source = com.xax.CryptoSavingsTracker.domain.model.TransactionSource.MANUAL,
                        externalId = null,
                        counterparty = null,
                        comment = null,
                        createdAt = now - 1_000
                    )
                )
            )
        }
        coEvery { allocationHistoryRepository.getAll() } returns flowOf(
            listOf(
                AllocationHistory(
                    id = "relevant-allocation",
                    assetId = "relevant-asset",
                    goalId = "g1",
                    amount = 1.0,
                    monthLabel = "2026-01",
                    timestamp = now - 5_000,
                    createdAt = now - 5_000
                ),
                AllocationHistory(
                    id = "unrelated-allocation",
                    assetId = "unrelated-asset",
                    goalId = "unrelated-goal",
                    amount = 1.0,
                    monthLabel = "2026-01",
                    timestamp = now - 5_000,
                    createdAt = now - 5_000
                )
            )
        )
        coEvery { allocationRepository.getAllAllocationsFlow() } returns flowOf(
            listOf(
                Allocation(
                    id = "relevant-allocation",
                    assetId = "relevant-asset",
                    goalId = "g1",
                    amount = 1.0,
                    createdAt = now - 5_000,
                    lastModifiedAt = now - 5_000
                )
            )
        )
        val legacyRates = listOf(
            ExecutionAssetRate(
                assetId = "relevant-asset",
                snapshotCurrency = "USD",
                rate = 10_000.0,
                capturedAtMillis = now - 10_000
            )
        )
        coEvery { legacyRateSnapshotBackfill.resolve(record, snapshots, any()) } returns legacyRates
        every { executionAssetRateRepository.getByRecordId(record.id) } returns flowOf(legacyRates)

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
            allocationRepository = allocationRepository,
            allocationHistoryRepository = allocationHistoryRepository,
            transactionRepository = transactionRepository,
            assetRepository = manualAssetRepository(),
            transactionRunner = transactionRunner,
            executionAssetRateRepository = executionAssetRateRepository,
            legacyRateSnapshotBackfill = legacyRateSnapshotBackfill,
            planningSettings = planningSettings
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
        val expectedUndoUntil = insertedEvent!!.completedAtMillis + 48L * 60L * 60L * 1000L
        assertThat(appendedRows.map { it.canUndoUntilMillis }.distinct())
            .containsExactly(expectedUndoUntil)

        coVerify(exactly = 1) { completionEventRepository.insert(any()) }
        coVerify(exactly = 1) { completedExecutionRepository.append(any()) }
        coVerify(exactly = 1) {
            executionRecordRepository.close(
                record.id,
                insertedEvent!!.completedAtMillis,
                expectedUndoUntil
            )
        }
        coVerify(exactly = 1) { legacyRateSnapshotBackfill.resolve(record, snapshots, any()) }
        coVerify(exactly = 1) { executionAssetRateRepository.getByRecordId(record.id) }
        coVerify(exactly = 2) { executionRecordRepository.getRecordById(record.id) }
    }

    @Test
    fun completeExecution_failsWhenRecordIsNotExecuting() = runTest {
        val executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
        val executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completedExecutionRepository = mockk<CompletedExecutionRepository>(relaxed = true)
        val completionEventRepository = mockk<CompletionEventRepository>(relaxed = true)
        val allocationHistoryRepository = mockk<AllocationHistoryRepository>(relaxed = true)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val executionAssetRateRepository = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val legacyRateSnapshotBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val planningSettings = mockk<MonthlyPlanningSettings> {
            every { undoGracePeriodHours } returns 24
        }
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
            allocationRepository = mockk(),
            allocationHistoryRepository = allocationHistoryRepository,
            transactionRepository = transactionRepository,
            assetRepository = manualAssetRepository(),
            transactionRunner = transactionRunner,
            executionAssetRateRepository = executionAssetRateRepository,
            legacyRateSnapshotBackfill = legacyRateSnapshotBackfill,
            planningSettings = planningSettings
        )

        val result = useCase(record.id)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo(ExecutionActionCopyCatalog.finishBlockedNoExecuting())
        coVerify(exactly = 0) { completionEventRepository.insert(any()) }
        coVerify(exactly = 0) { completedExecutionRepository.append(any()) }
    }

    @Test
    fun `completion rejects non-positive execution start before any completion write`() = runTest {
        val record = ExecutionRecord(
            id = "invalid-start",
            planId = "plan",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = 0L,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = 1L,
            updatedAtMillis = 1L
        )
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        coEvery { records.getRecordById(record.id) } returns record

        val result = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = mockk(relaxed = true),
            allocationHistoryRepository = mockk(relaxed = true),
            transactionRepository = mockk(relaxed = true),
            assetRepository = mockk(relaxed = true),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = mockk(relaxed = true),
            legacyRateSnapshotBackfill = mockk(relaxed = true),
            planningSettings = mockk(relaxed = true)
        )(record.id)

        assertThat(result.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        coVerify(exactly = 0) { events.insert(any()) }
        coVerify(exactly = 0) { completed.append(any()) }
        coVerify(exactly = 0) { records.close(any(), any(), any()) }
    }

    @Test
    fun `completion fails closed when current allocation history is missing`() = runTest {
        val startedAt = 1_000L
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val transactions = mockk<TransactionRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = record.id,
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 100.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val allocation = Allocation(
            id = "allocation-1",
            assetId = "btc-asset",
            goalId = snapshot.goalId,
            amount = 0.01,
            createdAt = startedAt - 10L,
            lastModifiedAt = startedAt - 1L
        )

        coEvery { records.getRecordById(record.id) } returns record
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        every { allocations.getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        every { allocationHistory.getAll() } returns flowOf(emptyList())
        every { transactions.getAllTransactions() } returns flowOf(emptyList())
        every { executionRates.getByRecordId(record.id) } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = allocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 10_000.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val result = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = mockk(),
            planningSettings = mockk(relaxed = true)
        )(record.id)

        assertThat(result.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        coVerify(exactly = 0) { completed.append(any()) }
        coVerify(exactly = 0) { records.close(any(), any(), any()) }
    }

    @Test
    fun `completion fails closed when shared asset sibling history is stale`() = runTest {
        val startedAt = 1_000L
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val transactions = mockk<TransactionRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = record.id,
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 100.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val snapshotAllocation = Allocation(
            id = "allocation-1",
            assetId = "shared-asset",
            goalId = snapshot.goalId,
            amount = 60.0,
            createdAt = startedAt - 10L,
            lastModifiedAt = startedAt - 1L
        )
        val siblingAllocation = snapshotAllocation.copy(
            id = "allocation-2",
            goalId = "goal-2",
            amount = 40.0
        )
        val snapshotHistory = AllocationHistory(
            id = "history-1",
            assetId = snapshotAllocation.assetId,
            goalId = snapshotAllocation.goalId,
            amount = snapshotAllocation.amount,
            monthLabel = record.monthLabel,
            timestamp = snapshotAllocation.lastModifiedAt,
            createdAt = snapshotAllocation.lastModifiedAt
        )
        val staleSiblingHistory = snapshotHistory.copy(
            id = "history-2",
            goalId = siblingAllocation.goalId,
            amount = 20.0
        )

        coEvery { records.getRecordById(record.id) } returns record
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        every {
            allocations.getAllAllocationsFlow()
        } returns flowOf(listOf(snapshotAllocation, siblingAllocation))
        every {
            allocationHistory.getAll()
        } returns flowOf(listOf(snapshotHistory, staleSiblingHistory))
        every { transactions.getAllTransactions() } returns flowOf(emptyList())
        every { executionRates.getByRecordId(record.id) } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = snapshotAllocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val result = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = mockk(),
            planningSettings = mockk(relaxed = true)
        )(record.id)

        assertThat(result.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        coVerify(exactly = 0) { completed.append(any()) }
        coVerify(exactly = 0) { records.close(any(), any(), any()) }
    }

    @Test
    fun `completion cannot close an active asset as zero when its frozen rate is missing`() = runTest {
        val startedAt = 1_000L
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val transactions = mockk<TransactionRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = record.id,
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 100.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val history = AllocationHistory(
            id = "allocation-1",
            assetId = "btc-asset",
            goalId = snapshot.goalId,
            amount = 0.01,
            monthLabel = record.monthLabel,
            timestamp = startedAt - 1L,
            createdAt = startedAt - 1L
        )
        val allocation = Allocation(
            id = history.id,
            assetId = history.assetId,
            goalId = history.goalId,
            amount = history.amount,
            createdAt = history.createdAt,
            lastModifiedAt = history.timestamp
        )

        coEvery { records.getRecordById(record.id) } returns record
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        every { allocations.getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        every { allocationHistory.getAll() } returns flowOf(listOf(history))
        every { transactions.getAllTransactions() } returns flowOf(
            listOf(
                Transaction(
                    id = "transaction-1",
                    assetId = history.assetId,
                    amount = history.amount,
                    dateMillis = startedAt + 1L,
                    source = com.xax.CryptoSavingsTracker.domain.model.TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1L
                )
            )
        )
        every { executionRates.getByRecordId(record.id) } returns flowOf(emptyList())

        val result = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = mockk(),
            planningSettings = mockk(relaxed = true)
        )(record.id)

        assertThat(result.exceptionOrNull()).isInstanceOf(MissingExecutionAssetRateException::class.java)
        coVerify(exactly = 0) { completed.append(any()) }
        coVerify(exactly = 0) { records.close(any(), any(), any()) }
    }

    @Test
    fun `completion fails closed for addressed asset without exhaustive ledger proof`() = runTest {
        val startedAt = 1_000L
        val record = ExecutionRecord(
            id = "record-addressed",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt,
            legacyRateSnapshotPending = true
        )
        val snapshot = ExecutionSnapshot(
            id = "snapshot-addressed",
            executionRecordId = record.id,
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 100.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val allocation = Allocation(
            id = "allocation-addressed",
            assetId = "btc-asset",
            goalId = snapshot.goalId,
            amount = 0.01,
            createdAt = startedAt - 1L,
            lastModifiedAt = startedAt - 1L
        )
        val history = AllocationHistory(
            id = "history-addressed",
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            monthLabel = record.monthLabel,
            timestamp = allocation.lastModifiedAt,
            createdAt = allocation.lastModifiedAt
        )
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val completed = mockk<CompletedExecutionRepository>(relaxed = true)
        val events = mockk<CompletionEventRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>()
        val historyRepository = mockk<AllocationHistoryRepository>()
        val transactions = mockk<TransactionRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val assets = mockk<AssetRepository>()
        val legacyBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        coEvery { records.getRecordById(record.id) } returns record
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        every { allocations.getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        every { historyRepository.getAll() } returns flowOf(listOf(history))
        every { transactions.getAllTransactions() } returns flowOf(emptyList())
        every { rates.getByRecordId(record.id) } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = allocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 10_000.0,
                    capturedAtMillis = startedAt
                )
            )
        )
        val assetState = kotlinx.coroutines.flow.MutableStateFlow(
            listOf(
                Asset(
                    id = allocation.assetId,
                    currency = "BTC",
                    address = "wallet-address",
                    chainId = "bitcoin",
                    createdAt = 0L,
                    updatedAt = 0L
                )
            )
        )
        every { assets.getAllAssets() } returns assetState
        coEvery {
            legacyBackfill.resolve(record, listOf(snapshot), listOf(history))
        } returns listOf(
            ExecutionAssetRate(
                assetId = allocation.assetId,
                snapshotCurrency = snapshot.currency,
                rate = 10_000.0,
                capturedAtMillis = startedAt
            )
        )

        val useCase = CompleteExecutionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            completedExecutionRepository = completed,
            completionEventRepository = events,
            allocationRepository = allocations,
            allocationHistoryRepository = historyRepository,
            transactionRepository = transactions,
            assetRepository = assets,
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            executionAssetRateRepository = rates,
            legacyRateSnapshotBackfill = legacyBackfill,
            planningSettings = mockk(relaxed = true)
        )
        val result = useCase(record.id)

        assertThat(result.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("on-chain ledger")
        coVerify(exactly = 0) { legacyBackfill.resolve(any(), any(), any()) }
        coVerify(exactly = 0) { completed.append(any()) }
        coVerify(exactly = 0) { records.close(any(), any(), any()) }

        assetState.value = assetState.value.map { asset ->
            asset.copy(address = null)
        }
        val chainOnlyManualResult = useCase(record.id)

        assertThat(chainOnlyManualResult.isSuccess).isTrue()
        coVerify(exactly = 1) {
            legacyBackfill.resolve(record, listOf(snapshot), listOf(history))
        }
        coVerify(exactly = 1) { completed.append(any()) }
        coVerify(exactly = 1) { records.close(record.id, any(), any()) }
    }

    private fun manualAssetRepository(): AssetRepository {
        val repository = mockk<AssetRepository>()
        val assetIds = listOf(
            "allocated-at-start",
            "btc-asset",
            "deallocated-before-start",
            "relevant-asset",
            "shared-asset",
            "unrelated-asset"
        )
        every { repository.getAllAssets() } returns flowOf(
            assetIds.map { assetId ->
                Asset(
                    id = assetId,
                    currency = "BTC",
                    address = null,
                    chainId = null,
                    createdAt = 0L,
                    updatedAt = 0L
                )
            }
        )
        return repository
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
