package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GetExecutionSessionUseCaseTest {
    @Test
    fun `session ignores pre-start deallocated assets outside the persisted rate scope`() = runTest {
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val legacyRateSnapshotBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val startedAt = 1_000L
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
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

        coEvery { snapshots.getByRecordId("record-1") } returns flowOf(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(
            listOf(
                Transaction(
                    id = "old-asset-deposit",
                    assetId = "deallocated-before-start",
                    amount = 1.0,
                    dateMillis = startedAt + 1,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1
                )
            )
        )
        coEvery { allocationHistory.getAll() } returns flowOf(
            listOf(
                AllocationHistory(
                    id = "old-allocation",
                    assetId = "deallocated-before-start",
                    goalId = snapshot.goalId,
                    amount = 1.0,
                    monthLabel = "2026-07",
                    timestamp = startedAt - 100,
                    createdAt = startedAt - 100
                ),
                AllocationHistory(
                    id = "old-deallocation",
                    assetId = "deallocated-before-start",
                    goalId = snapshot.goalId,
                    amount = 0.0,
                    monthLabel = "2026-07",
                    timestamp = startedAt - 10,
                    createdAt = startedAt - 10
                ),
                AllocationHistory(
                    id = "current-allocation",
                    assetId = "allocated-at-start",
                    goalId = snapshot.goalId,
                    amount = 1.0,
                    monthLabel = "2026-07",
                    timestamp = startedAt - 10,
                    createdAt = startedAt - 10
                )
            )
        )
        coEvery { allocations.getAllAllocationsFlow() } returns flowOf(
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
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = "allocated-at-start",
                    snapshotCurrency = "USD",
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val result = GetExecutionSessionUseCase(
            executionRecordRepository = mockk(),
            executionSnapshotRepository = snapshots,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = legacyRateSnapshotBackfill
        ).sessionForRecord("record-1", startedAt).first()

        assertThat(result.single().contributed).isEqualTo(0.0)
    }

    @Test
    fun `reopened migrated execution backfills rates before calculating progress`() = runTest {
        val records = mockk<ExecutionRecordRepository>()
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val legacyRateSnapshotBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val startedAt = 1_000L
        val record = ExecutionRecord(
            id = "legacy-record",
            planId = "legacy-plan",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt + 1,
            legacyRateSnapshotPending = true
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
            timestamp = startedAt - 1,
            createdAt = startedAt - 1
        )
        val rate = ExecutionAssetRate(
            assetId = history.assetId,
            snapshotCurrency = snapshot.currency,
            rate = 10_000.0,
            capturedAtMillis = startedAt
        )

        coEvery { records.getCurrentExecutingRecord() } returns flowOf(record)
        coEvery { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(
            listOf(
                Transaction(
                    id = "tx-1",
                    assetId = history.assetId,
                    amount = 0.01,
                    dateMillis = startedAt + 1,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1
                )
            )
        )
        coEvery { allocationHistory.getAll() } returns flowOf(listOf(history))
        coEvery { allocations.getAllAllocationsFlow() } returns flowOf(
            listOf(
                Allocation(
                    id = "allocation-1",
                    assetId = history.assetId,
                    goalId = history.goalId,
                    amount = history.amount,
                    createdAt = history.createdAt,
                    lastModifiedAt = history.timestamp
                )
            )
        )
        coEvery { executionRates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery {
            legacyRateSnapshotBackfill.resolve(record, listOf(snapshot), listOf(history))
        } returns listOf(rate)

        val session = GetExecutionSessionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = legacyRateSnapshotBackfill
        ).currentExecuting().first()

        assertThat(session).isNotNull()
        assertThat(session!!.goals.single().contributed).isEqualTo(100.0)
        assertThat(session.assetRates).containsExactly(rate)
        coVerify(exactly = 1) {
            legacyRateSnapshotBackfill.resolve(record, listOf(snapshot), listOf(history))
        }
    }

    @Test
    fun `session uses persisted execution rate without resolving a live FX rate`() = runTest {
        val records = mockk<ExecutionRecordRepository>()
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val legacyRateSnapshotBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        val startedAt = 1_000L

        coEvery { snapshots.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionSnapshot(
                    id = "snapshot-1",
                    executionRecordId = "record-1",
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
            )
        )
        coEvery { transactions.getAllTransactions() } returns flowOf(
            listOf(
                Transaction(
                    id = "tx-1",
                    assetId = "btc-asset",
                    amount = 0.01,
                    dateMillis = startedAt + 1,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1
                )
            )
        )
        coEvery { allocationHistory.getAll() } returns flowOf(
            listOf(
                AllocationHistory(
                    id = "allocation-1",
                    assetId = "btc-asset",
                    goalId = "goal-1",
                    amount = 0.01,
                    monthLabel = "2026-07",
                    timestamp = startedAt - 1,
                    createdAt = startedAt - 1
                )
            )
        )
        coEvery { allocations.getAllAllocationsFlow() } returns flowOf(
            listOf(
                Allocation(
                    id = "allocation-1",
                    assetId = "btc-asset",
                    goalId = "goal-1",
                    amount = 0.01,
                    createdAt = startedAt - 1,
                    lastModifiedAt = startedAt - 1
                )
            )
        )
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = "btc-asset",
                    snapshotCurrency = "USD",
                    rate = 10_000.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val result = GetExecutionSessionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            transactionRepository = transactions,
            assetRepository = manualAssetRepository(),
            executionAssetRateRepository = executionRates,
            legacyRateSnapshotBackfill = legacyRateSnapshotBackfill
        ).sessionForRecord("record-1", startedAt).first()

        assertThat(result.single().contributed).isEqualTo(100.0)
        coVerify(exactly = 1) { executionRates.getByRecordId("record-1") }
    }

    @Test
    fun `missing required frozen rate cannot remove an active asset from execution progress`() = runTest {
        val startedAt = 1_000L
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
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
            monthLabel = "2026-07",
            timestamp = startedAt - 1L,
            createdAt = startedAt - 1L
        )
        val transaction = Transaction(
            id = "transaction-1",
            assetId = history.assetId,
            amount = 0.01,
            dateMillis = startedAt + 1L,
            source = TransactionSource.MANUAL,
            externalId = null,
            counterparty = null,
            comment = null,
            createdAt = startedAt + 1L
        )

        coEvery { snapshots.getByRecordId("record-1") } returns
            MutableStateFlow(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(listOf(transaction))
        coEvery { allocationHistory.getAll() } returns flowOf(listOf(history))
        coEvery { allocations.getAllAllocationsFlow() } returns flowOf(
            listOf(
                Allocation(
                    id = "allocation-1",
                    assetId = history.assetId,
                    goalId = history.goalId,
                    amount = history.amount,
                    createdAt = history.createdAt,
                    lastModifiedAt = history.timestamp
                )
            )
        )
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(emptyList())

        val unavailable = withTimeoutOrNull(250L) {
            GetExecutionSessionUseCase(
                executionRecordRepository = mockk(),
                executionSnapshotRepository = snapshots,
                allocationRepository = allocations,
                allocationHistoryRepository = allocationHistory,
                transactionRepository = transactions,
                assetRepository = manualAssetRepository(),
                executionAssetRateRepository = executionRates,
                legacyRateSnapshotBackfill = mockk()
            ).sessionForRecord("record-1", startedAt).first()
        }

        assertThat(unavailable).isNull()
    }

    @Test
    fun `current allocation without provable history makes execution progress unavailable`() = runTest {
        val startedAt = 1_000L
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
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

        coEvery { snapshots.getByRecordId("record-1") } returns
            MutableStateFlow(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(emptyList())
        coEvery { allocations.getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        coEvery { allocationHistory.getAll() } returns flowOf(emptyList())
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = allocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 10_000.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val unavailable = withTimeoutOrNull(250L) {
            GetExecutionSessionUseCase(
                executionRecordRepository = mockk(),
                executionSnapshotRepository = snapshots,
                allocationRepository = allocations,
                allocationHistoryRepository = allocationHistory,
                transactionRepository = transactions,
                assetRepository = manualAssetRepository(),
                executionAssetRateRepository = executionRates,
                legacyRateSnapshotBackfill = mockk()
            ).sessionForRecord("record-1", startedAt).first()
        }

        assertThat(unavailable).isNull()
    }

    @Test
    fun `shared asset sibling without history makes execution progress unavailable`() = runTest {
        val startedAt = 1_000L
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
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
            monthLabel = "2026-07",
            timestamp = snapshotAllocation.lastModifiedAt,
            createdAt = snapshotAllocation.lastModifiedAt
        )

        coEvery { snapshots.getByRecordId("record-1") } returns
            MutableStateFlow(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(emptyList())
        coEvery {
            allocations.getAllAllocationsFlow()
        } returns flowOf(listOf(snapshotAllocation, siblingAllocation))
        coEvery { allocationHistory.getAll() } returns flowOf(listOf(snapshotHistory))
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = snapshotAllocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val unavailable = withTimeoutOrNull(250L) {
            GetExecutionSessionUseCase(
                executionRecordRepository = mockk(),
                executionSnapshotRepository = snapshots,
                allocationRepository = allocations,
                allocationHistoryRepository = allocationHistory,
                transactionRepository = transactions,
                assetRepository = manualAssetRepository(),
                executionAssetRateRepository = executionRates,
                legacyRateSnapshotBackfill = mockk()
            ).sessionForRecord("record-1", startedAt).first()
        }

        assertThat(unavailable).isNull()
    }

    @Test
    fun `collector survives source incoherence longer than old grace and then recovers`() = runTest {
        val startedAt = 1_000L
        val records = mockk<ExecutionRecordRepository>()
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 200.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 200.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val record = ExecutionRecord(
            id = snapshot.executionRecordId,
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = startedAt,
            updatedAtMillis = startedAt
        )
        val allocationA = Allocation(
            id = "allocation-a",
            assetId = "asset-a",
            goalId = snapshot.goalId,
            amount = 100.0,
            createdAt = startedAt - 1L,
            lastModifiedAt = startedAt - 1L
        )
        val allocationB = allocationA.copy(
            id = "allocation-b",
            assetId = "asset-b"
        )
        val historyA = AllocationHistory(
            id = "history-a",
            assetId = allocationA.assetId,
            goalId = snapshot.goalId,
            amount = allocationA.amount,
            monthLabel = "2026-07",
            timestamp = startedAt - 1L,
            createdAt = startedAt - 1L
        )
        val historyB = historyA.copy(
            id = "history-b",
            assetId = allocationB.assetId
        )
        val transactionsFlow = MutableStateFlow(
            listOf(
                Transaction(
                    id = "deposit-a",
                    assetId = allocationA.assetId,
                    amount = 50.0,
                    dateMillis = startedAt + 1L,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1L
                ),
                Transaction(
                    id = "deposit-b",
                    assetId = allocationB.assetId,
                    amount = 50.0,
                    dateMillis = startedAt + 1L,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = startedAt + 1L
                )
            )
        )
        val allocationsFlow = MutableStateFlow(listOf(allocationA))
        val historyFlow = MutableStateFlow(listOf(historyA))
        val ratesFlow = MutableStateFlow(
            listOf(
                ExecutionAssetRate(
                    assetId = allocationA.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        coEvery { records.getCurrentExecutingRecord() } returns MutableStateFlow(record)
        coEvery { snapshots.getByRecordId("record-1") } returns flowOf(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns transactionsFlow
        coEvery { allocations.getAllAllocationsFlow() } returns allocationsFlow
        coEvery { allocationHistory.getAll() } returns historyFlow
        coEvery { executionRates.getByRecordId("record-1") } returns ratesFlow

        val emissions = mutableListOf<ExecutionSession?>()
        val collection = launch {
            GetExecutionSessionUseCase(
                executionRecordRepository = records,
                executionSnapshotRepository = snapshots,
                allocationRepository = allocations,
                allocationHistoryRepository = allocationHistory,
                transactionRepository = transactions,
                assetRepository = manualAssetRepository(),
                executionAssetRateRepository = executionRates,
                legacyRateSnapshotBackfill = mockk()
            ).currentExecuting().toList(emissions)
        }

        runCurrent()
        assertThat(emissions.last()).isNotNull()
        assertThat(emissions.last()!!.isProgressAvailable).isTrue()
        assertThat(emissions.last()!!.goals.single().contributed).isEqualTo(50.0)

        allocationsFlow.value = listOf(allocationA, allocationB)
        runCurrent()
        advanceTimeBy(250L)
        runCurrent()
        assertThat(collection.isActive).isTrue()
        assertThat(emissions.last()).isNotNull()
        assertThat(emissions.last()!!.record.id).isEqualTo(record.id)
        assertThat(emissions.last()!!.isProgressAvailable).isFalse()

        historyFlow.value = listOf(historyA, historyB)
        runCurrent()
        advanceTimeBy(250L)
        runCurrent()
        assertThat(collection.isActive).isTrue()

        ratesFlow.value = ratesFlow.value + ExecutionAssetRate(
            assetId = allocationB.assetId,
            snapshotCurrency = snapshot.currency,
            rate = 1.0,
            capturedAtMillis = startedAt
        )
        runCurrent()

        assertThat(collection.isActive).isTrue()
        assertThat(emissions.last()).isNotNull()
        assertThat(emissions.last()!!.record.id).isEqualTo(record.id)
        assertThat(emissions.last()!!.isProgressAvailable).isTrue()
        assertThat(emissions.last()!!.goals.single().contributed).isEqualTo(100.0)
        collection.cancel()
    }

    @Test
    fun `permanent source incoherence keeps collector alive without publishing hybrid state`() = runTest {
        val startedAt = 1_000L
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()
        val snapshot = ExecutionSnapshot(
            id = "snapshot-1",
            executionRecordId = "record-1",
            goalId = "goal-1",
            goalName = "USD goal",
            currency = "USD",
            targetAmount = 200.0,
            currentTotalAtStart = 0.0,
            requiredAmount = 200.0,
            isProtected = false,
            isSkipped = false,
            customAmount = null,
            createdAtMillis = startedAt
        )
        val allocation = Allocation(
            id = "allocation-1",
            assetId = "asset-1",
            goalId = snapshot.goalId,
            amount = 100.0,
            createdAt = startedAt - 1L,
            lastModifiedAt = startedAt - 1L
        )
        val history = AllocationHistory(
            id = "history-1",
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            monthLabel = "2026-07",
            timestamp = allocation.lastModifiedAt,
            createdAt = allocation.lastModifiedAt
        )
        val allocationsFlow = MutableStateFlow(listOf(allocation))

        coEvery { snapshots.getByRecordId("record-1") } returns flowOf(listOf(snapshot))
        coEvery { transactions.getAllTransactions() } returns flowOf(emptyList())
        coEvery { allocations.getAllAllocationsFlow() } returns allocationsFlow
        coEvery { allocationHistory.getAll() } returns flowOf(listOf(history))
        coEvery { executionRates.getByRecordId("record-1") } returns flowOf(
            listOf(
                ExecutionAssetRate(
                    assetId = allocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )

        val emissions = mutableListOf<List<ExecutionGoalProgress>>()
        val collection = async {
            runCatching {
                withTimeout(1_000L) {
                    GetExecutionSessionUseCase(
                        executionRecordRepository = mockk(),
                        executionSnapshotRepository = snapshots,
                        allocationRepository = allocations,
                        allocationHistoryRepository = allocationHistory,
                        transactionRepository = transactions,
                        assetRepository = manualAssetRepository(),
                        executionAssetRateRepository = executionRates,
                        legacyRateSnapshotBackfill = mockk()
                    ).sessionForRecord("record-1", startedAt)
                        .toList(emissions)
                }
            }
        }

        runCurrent()
        assertThat(emissions).hasSize(1)

        allocationsFlow.value = listOf(
            allocation.copy(
                amount = 150.0,
                lastModifiedAt = startedAt
            )
        )
        advanceTimeBy(1_000L)
        runCurrent()

        assertThat(collection.await().exceptionOrNull())
            .isInstanceOf(TimeoutCancellationException::class.java)
        assertThat(emissions).hasSize(1)
    }

    @Test
    fun `addressed asset without exhaustive ledger proof keeps current execution unavailable`() = runTest {
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

        val records = mockk<ExecutionRecordRepository>()
        val snapshots = mockk<ExecutionSnapshotRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val historyRepository = mockk<AllocationHistoryRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val assets = mockk<AssetRepository>()
        val legacyBackfill = mockk<LegacyExecutionRateSnapshotBackfill>()
        every { records.getCurrentExecutingRecord() } returns flowOf(record)
        every { snapshots.getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        every { transactions.getAllTransactions() } returns flowOf(emptyList())
        every { allocations.getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        every { historyRepository.getAll() } returns flowOf(listOf(history))
        val frozenRate = ExecutionAssetRate(
            assetId = allocation.assetId,
            snapshotCurrency = snapshot.currency,
            rate = 10_000.0,
            capturedAtMillis = startedAt
        )
        every { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery {
            legacyBackfill.resolve(record, listOf(snapshot), listOf(history))
        } returns listOf(frozenRate)
        val assetState = MutableStateFlow(
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

        val useCase = GetExecutionSessionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            allocationRepository = allocations,
            allocationHistoryRepository = historyRepository,
            transactionRepository = transactions,
            assetRepository = assets,
            executionAssetRateRepository = rates,
            legacyRateSnapshotBackfill = legacyBackfill
        )
        val session = useCase.currentExecuting().first()

        assertThat(session).isNotNull()
        assertThat(session!!.record).isEqualTo(record)
        assertThat(session.isProgressAvailable).isFalse()
        assertThat(session.goals).isEmpty()
        coVerify(exactly = 0) { legacyBackfill.resolve(any(), any(), any()) }

        assetState.value = assetState.value.map { asset ->
            asset.copy(address = null)
        }
        val chainOnlyManualSession = useCase.currentExecuting()
            .first { it?.isProgressAvailable == true }

        assertThat(chainOnlyManualSession).isNotNull()
        assertThat(chainOnlyManualSession!!.record).isEqualTo(record)
        assertThat(chainOnlyManualSession.isProgressAvailable).isTrue()
        coVerify(exactly = 1) {
            legacyBackfill.resolve(record, listOf(snapshot), listOf(history))
        }
    }

    @Test
    fun `current execution without snapshots is record-bearing but progress unavailable`() = runTest {
        val record = corruptExecutingRecord(id = "missing-snapshots", startedAtMillis = 1_000L)

        val session = corruptExecutionUseCase(
            record = record,
            snapshots = emptyList()
        ).currentExecuting().first()

        assertThat(session).isNotNull()
        assertThat(session!!.record).isEqualTo(record)
        assertThat(session.isProgressAvailable).isFalse()
        assertThat(session.goals).isEmpty()
    }

    @Test
    fun `current execution with non-positive start is record-bearing but progress unavailable`() = runTest {
        for (startedAtMillis in listOf(0L, -1L)) {
            val record = corruptExecutingRecord(
                id = "invalid-start-$startedAtMillis",
                startedAtMillis = startedAtMillis
            )

            val session = corruptExecutionUseCase(
                record = record,
                snapshots = listOf(corruptSnapshot(record.id))
            ).currentExecuting().first()

            assertThat(session).isNotNull()
            assertThat(session!!.record).isEqualTo(record)
            assertThat(session.isProgressAvailable).isFalse()
            assertThat(session.goals).isEmpty()
        }
    }

    private fun corruptExecutionUseCase(
        record: ExecutionRecord,
        snapshots: List<ExecutionSnapshot>
    ): GetExecutionSessionUseCase {
        val records = mockk<ExecutionRecordRepository> {
            every { getCurrentExecutingRecord() } returns flowOf(record)
        }
        val snapshotRepository = mockk<ExecutionSnapshotRepository> {
            every { getByRecordId(record.id) } returns flowOf(snapshots)
        }
        val allocations = mockk<AllocationRepository> {
            every { getAllAllocationsFlow() } returns flowOf(emptyList())
        }
        val history = mockk<AllocationHistoryRepository> {
            every { getAll() } returns flowOf(emptyList())
        }
        val transactions = mockk<TransactionRepository> {
            every { getAllTransactions() } returns flowOf(emptyList())
        }
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns flowOf(emptyList())
        }
        val rates = mockk<ExecutionAssetRateRepository> {
            every { getByRecordId(record.id) } returns flowOf(emptyList())
        }
        return GetExecutionSessionUseCase(
            executionRecordRepository = records,
            executionSnapshotRepository = snapshotRepository,
            allocationRepository = allocations,
            allocationHistoryRepository = history,
            transactionRepository = transactions,
            assetRepository = assets,
            executionAssetRateRepository = rates,
            legacyRateSnapshotBackfill = mockk(relaxed = true)
        )
    }

    private fun corruptExecutingRecord(
        id: String,
        startedAtMillis: Long
    ) = ExecutionRecord(
        id = id,
        planId = "plan",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = startedAtMillis,
        closedAtMillis = null,
        canUndoUntilMillis = null,
        createdAtMillis = 1L,
        updatedAtMillis = 1L
    )

    private fun corruptSnapshot(recordId: String) = ExecutionSnapshot(
        id = "snapshot-$recordId",
        executionRecordId = recordId,
        goalId = "goal",
        goalName = "Goal",
        currency = "USD",
        targetAmount = 100.0,
        currentTotalAtStart = 0.0,
        requiredAmount = 10.0,
        isProtected = false,
        isSkipped = false,
        customAmount = null,
        createdAtMillis = 1L
    )

    private fun manualAssetRepository(): AssetRepository {
        val repository = mockk<AssetRepository>()
        val assetIds = listOf(
            "allocated-at-start",
            "asset-1",
            "asset-a",
            "asset-b",
            "btc-asset",
            "deallocated-before-start",
            "shared-asset"
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
}
