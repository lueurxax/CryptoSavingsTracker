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
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class ExecutionAttributionRecoveryPolicyTest {
    @Test
    fun `missing snapshots and non-positive start always expose recovery`() = runTest {
        val missingSnapshots = ExecutionRecord(
            id = "missing-snapshots",
            planId = "plan",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = 1_000L,
            closedAtMillis = null,
            canUndoUntilMillis = 2_000L,
            createdAtMillis = 1L,
            updatedAtMillis = 1L
        )
        val invalidStart = missingSnapshots.copy(
            id = "invalid-start",
            startedAtMillis = 0L
        )
        val snapshots = mockk<ExecutionSnapshotRepository> {
            every { getByRecordId(missingSnapshots.id) } returns flowOf(emptyList())
        }
        val policy = ExecutionAttributionRecoveryPolicy(
            executionSnapshotRepository = snapshots,
            allocationRepository = mockk(relaxed = true),
            allocationHistoryRepository = mockk(relaxed = true),
            assetRepository = mockk(relaxed = true),
            transactionRepository = mockk(relaxed = true),
            executionAssetRateRepository = mockk(relaxed = true)
        )

        assertThat(policy.requiresExpiredUndoRecovery(missingSnapshots)).isTrue()
        assertThat(policy.requiresExpiredUndoRecovery(invalidStart)).isTrue()
    }

    @Test
    fun `expired recovery is scoped to attribution-incoherent addressed or provider ledgers`() = runTest {
        val startedAt = 1_000L
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = startedAt,
            closedAtMillis = null,
            canUndoUntilMillis = 2_000L,
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
            assetId = "asset-1",
            goalId = snapshot.goalId,
            amount = 1.0,
            createdAt = startedAt - 1L,
            lastModifiedAt = startedAt - 1L
        )
        val history = AllocationHistory(
            id = "history-1",
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            monthLabel = record.monthLabel,
            timestamp = allocation.lastModifiedAt,
            createdAt = allocation.lastModifiedAt
        )
        val assetState = MutableStateFlow(
            listOf(
                Asset(
                    id = allocation.assetId,
                    currency = "BTC",
                    address = null,
                    chainId = "bitcoin",
                    createdAt = 0L,
                    updatedAt = 0L
                )
            )
        )
        val transactionState = MutableStateFlow(
            listOf(transaction(allocation.assetId, TransactionSource.MANUAL))
        )
        val historyState = MutableStateFlow(listOf(history))
        val rateState = MutableStateFlow(
            listOf(
                ExecutionAssetRate(
                    assetId = allocation.assetId,
                    snapshotCurrency = snapshot.currency,
                    rate = 1.0,
                    capturedAtMillis = startedAt
                )
            )
        )
        val snapshots = mockk<ExecutionSnapshotRepository> {
            every { getByRecordId(record.id) } returns flowOf(listOf(snapshot))
        }
        val allocations = mockk<AllocationRepository> {
            every { getAllAllocationsFlow() } returns flowOf(listOf(allocation))
        }
        val historyRepository = mockk<AllocationHistoryRepository> {
            every { getAll() } returns historyState
        }
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns assetState
        }
        val transactions = mockk<TransactionRepository> {
            every { getAllTransactions() } returns transactionState
        }
        val rates = mockk<ExecutionAssetRateRepository> {
            every { getByRecordId(record.id) } returns rateState
        }
        val policy = ExecutionAttributionRecoveryPolicy(
            executionSnapshotRepository = snapshots,
            allocationRepository = allocations,
            allocationHistoryRepository = historyRepository,
            assetRepository = assets,
            transactionRepository = transactions,
            executionAssetRateRepository = rates
        )

        assertThat(policy.requiresExpiredUndoRecovery(record)).isFalse()

        rateState.value = emptyList()
        assertThat(policy.requiresExpiredUndoRecovery(record)).isTrue()
        rateState.value = listOf(
            ExecutionAssetRate(
                assetId = allocation.assetId,
                snapshotCurrency = snapshot.currency,
                rate = 1.0,
                capturedAtMillis = startedAt
            )
        )

        assetState.value = assetState.value.map { it.copy(address = "wallet-address") }
        assertThat(policy.requiresExpiredUndoRecovery(record)).isTrue()

        assetState.value = assetState.value.map { it.copy(address = null) }
        transactionState.value = listOf(transaction(allocation.assetId, TransactionSource.ON_CHAIN))
        assertThat(policy.requiresExpiredUndoRecovery(record)).isTrue()

        transactionState.value = emptyList()
        historyState.value = emptyList()
        assertThat(policy.requiresExpiredUndoRecovery(record)).isTrue()
    }

    private fun transaction(assetId: String, source: TransactionSource) = Transaction(
        id = "transaction-${source.rawValue}",
        assetId = assetId,
        amount = 1.0,
        dateMillis = 2_000L,
        source = source,
        externalId = if (source == TransactionSource.ON_CHAIN) "provider-row" else null,
        counterparty = null,
        comment = null,
        createdAt = 2_000L
    )
}
