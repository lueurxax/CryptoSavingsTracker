package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class LegacyExecutionRateSnapshotBackfillTest {
    @Test
    fun `legacy executing record backfills once then atomically clears its marker`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val expectedRate = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        coEvery { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery { records.getRecordById(record.id) } returns record
        coEvery { resolver.capture(setOf("btc-asset"), setOf("USD"), any()) } returns listOf(expectedRate)

        val result = backfill(rates, records, resolver).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(expectedRate)
        coVerify(exactly = 1) { rates.replaceForRecord(record.id, listOf(expectedRate)) }
        coVerify(exactly = 1) { records.clearLegacyRateSnapshotPending(record.id) }
    }

    @Test
    fun `legacy backfill excludes unrelated existing assets`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val assets = repositoryWithAssets("btc-asset", "eth-asset")
        val record = legacyRecord()
        val btcRate = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        coEvery { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery { records.getRecordById(record.id) } returns record
        coEvery {
            resolver.capture(setOf("btc-asset"), setOf("USD"), any())
        } returns listOf(btcRate)

        val result = backfill(rates, records, resolver, assets).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(btcRate)
        coVerify(exactly = 1) {
            rates.replaceForRecord(record.id, listOf(btcRate))
        }
    }

    @Test
    fun `legacy backfill captures asset removed from current allocations but retained in history`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val historicalEth = history().copy(
            id = "eth-history",
            assetId = "eth-asset"
        )
        val expectedRate = ExecutionAssetRate("eth-asset", "USD", 2_000.0, 1_000L)
        coEvery { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery { records.getRecordById(record.id) } returns record
        coEvery {
            resolver.capture(setOf("eth-asset"), setOf("USD"), any())
        } returns listOf(expectedRate)

        val result = backfill(
            rates = rates,
            records = records,
            resolver = resolver,
            assets = repositoryWithAssets("btc-asset", "eth-asset"),
            historyRows = listOf(historicalEth)
        ).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(historicalEth)
        )

        assertThat(result).containsExactly(expectedRate)
        coVerify(exactly = 1) {
            rates.replaceForRecord(record.id, listOf(expectedRate))
        }
    }

    @Test
    fun `partial legacy rate rows fail without fetching replacement live FX`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        coEvery { rates.getByRecordId(record.id) } returns flowOf(
            listOf(ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L))
        )
        coEvery { records.getRecordById(record.id) } returns record

        val failure = runCatching {
            backfill(rates, records, resolver).resolve(
                record = record,
                snapshots = listOf(snapshot(record.id), snapshot(record.id).copy(goalId = "goal-2", currency = "EUR")),
                allocationHistory = listOf(history())
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("partial or corrupt")
        coVerify(exactly = 0) { resolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { records.clearLegacyRateSnapshotPending(any()) }
    }

    @Test
    fun `concurrent backfill returns the persisted winner without replacing its quote`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val winner = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        val challenger = ExecutionAssetRate("btc-asset", "USD", 11_000.0, 1_001L)
        coEvery { rates.getByRecordId(record.id) } returnsMany listOf(
            flowOf(emptyList()),
            flowOf(listOf(winner))
        )
        coEvery { records.getRecordById(record.id) } returnsMany listOf(
            record,
            record.copy(legacyRateSnapshotPending = false)
        )
        coEvery { resolver.capture(setOf("btc-asset"), setOf("USD"), any()) } returns listOf(challenger)

        val result = backfill(rates, records, resolver).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(winner)
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { records.clearLegacyRateSnapshotPending(any()) }
    }

    @Test
    fun `stale empty read returns a freshly reread winner when another caller already cleared marker`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val winner = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        coEvery { rates.getByRecordId(record.id) } returnsMany listOf(
            flowOf(emptyList()),
            flowOf(listOf(winner))
        )
        coEvery { records.getRecordById(record.id) } returns record.copy(legacyRateSnapshotPending = false)

        val result = backfill(rates, records, resolver).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(winner)
        coVerify(exactly = 0) { resolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
    }

    @Test
    fun `concurrent asset addition does not redefine the winner matrix for an in-flight backfill`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val btc = asset("btc-asset")
        val eth = asset("eth-asset")
        val assetsState = MutableStateFlow(listOf(btc))
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns assetsState
        }
        val winner = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        every { rates.getByRecordId(record.id) } answers {
            assetsState.value = listOf(btc, eth)
            flowOf(listOf(winner))
        }
        coEvery {
            records.getRecordById(record.id)
        } returns record.copy(legacyRateSnapshotPending = false)

        val result = backfill(rates, records, resolver, assets).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(winner)
        coVerify(exactly = 0) { resolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
    }

    @Test
    fun `concurrent asset deletion does not redefine the winner matrix for an in-flight backfill`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val btc = asset("btc-asset")
        val eth = asset("eth-asset")
        val assetsState = MutableStateFlow(listOf(btc, eth))
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns assetsState
        }
        val winnerRates = listOf(
            ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L),
            ExecutionAssetRate("eth-asset", "USD", 2_000.0, 1_000L)
        )
        every { rates.getByRecordId(record.id) } answers {
            assetsState.value = listOf(btc)
            flowOf(winnerRates)
        }
        coEvery {
            records.getRecordById(record.id)
        } returns record.copy(legacyRateSnapshotPending = false)

        val result = backfill(rates, records, resolver, assets).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactlyElementsIn(winnerRates)
        coVerify(exactly = 0) { resolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
    }

    @Test
    fun `concurrent caller accepts the committed winner from an earlier asset scope`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val winner = ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L)
        every { rates.getByRecordId(record.id) } returns flowOf(listOf(winner))
        coEvery {
            records.getRecordById(record.id)
        } returns record.copy(legacyRateSnapshotPending = false)

        val result = backfill(
            rates = rates,
            records = records,
            resolver = resolver,
            assets = repositoryWithAssets("btc-asset", "eth-asset")
        ).resolve(
            record = record,
            snapshots = listOf(snapshot(record.id)),
            allocationHistory = listOf(history())
        )

        assertThat(result).containsExactly(winner)
        coVerify(exactly = 0) { resolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
    }

    @Test
    fun `currency change during live FX capture rejects legacy backfill commit`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val btc = asset("btc-asset")
        val assetsState = MutableStateFlow(listOf(btc))
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns assetsState
        }
        every { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery { records.getRecordById(record.id) } returns record
        coEvery {
            resolver.capture(setOf("btc-asset"), setOf("USD"), any())
        } answers {
            assetsState.value = listOf(btc.copy(currency = "ETH"))
            listOf(ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L))
        }

        val failure = runCatching {
            backfill(rates, records, resolver, assets).resolve(
                record = record,
                snapshots = listOf(snapshot(record.id)),
                allocationHistory = listOf(history())
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("scope changed")
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { records.clearLegacyRateSnapshotPending(any()) }
    }

    @Test
    fun `allocation change during live FX capture rejects legacy backfill commit`() = runTest {
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val resolver = mockk<ExecutionAssetRateResolver>()
        val record = legacyRecord()
        val allocationState = mutableListOf<Allocation>()
        val allocations = mockk<AllocationRepository> {
            coEvery { getAllocationsForAsset("btc-asset") } answers {
                allocationState.toList()
            }
        }
        every { rates.getByRecordId(record.id) } returns flowOf(emptyList())
        coEvery { records.getRecordById(record.id) } returns record
        coEvery {
            resolver.capture(setOf("btc-asset"), setOf("USD"), any())
        } answers {
            allocationState += Allocation(
                id = "allocation-2",
                assetId = "btc-asset",
                goalId = "goal-1",
                amount = 0.02,
                createdAt = 1_001L,
                lastModifiedAt = 1_001L
            )
            listOf(ExecutionAssetRate("btc-asset", "USD", 10_000.0, 1_000L))
        }

        val failure = runCatching {
            backfill(
                rates = rates,
                records = records,
                resolver = resolver,
                allocations = allocations
            ).resolve(
                record = record,
                snapshots = listOf(snapshot(record.id)),
                allocationHistory = listOf(history())
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("scope changed")
        coVerify(exactly = 0) { rates.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { records.clearLegacyRateSnapshotPending(any()) }
    }

    private fun backfill(
        rates: ExecutionAssetRateRepository,
        records: ExecutionRecordRepository,
        resolver: ExecutionAssetRateResolver,
        assets: AssetRepository = repositoryWithAssets("btc-asset"),
        allocations: AllocationRepository = repositoryWithAllocations(),
        historyRows: List<AllocationHistory> = listOf(history())
    ) = LegacyExecutionRateSnapshotBackfill(
        executionAssetRateRepository = rates,
        executionRecordRepository = records,
        transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        },
        assetRateResolver = resolver,
        assetRepository = assets,
        allocationRepository = allocations,
        allocationHistoryRepository = mockk {
            every { getAll() } returns flowOf(historyRows)
        }
    )

    private fun repositoryWithAssets(vararg ids: String): AssetRepository =
        mockk {
            every { getAllAssets() } returns flowOf(
                ids.map(::asset)
            )
        }

    private fun repositoryWithAllocations(
        vararg values: Allocation
    ): AllocationRepository = mockk {
        coEvery { getAllocationsForAsset(any()) } answers {
            val assetId = firstArg<String>()
            values.filter { it.assetId == assetId }
        }
    }

    private fun asset(id: String) = Asset(
        id = id,
        currency = id.substringBefore("-").uppercase(),
        address = null,
        chainId = null,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun legacyRecord() = ExecutionRecord(
        id = "legacy-record",
        planId = "plan-1",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = 1_000L,
        closedAtMillis = null,
        canUndoUntilMillis = null,
        createdAtMillis = 1_000L,
        updatedAtMillis = 1_000L,
        legacyRateSnapshotPending = true
    )

    private fun snapshot(recordId: String) = ExecutionSnapshot(
        id = "snapshot-1",
        executionRecordId = recordId,
        goalId = "goal-1",
        goalName = "Goal",
        currency = "USD",
        targetAmount = 100.0,
        currentTotalAtStart = 0.0,
        requiredAmount = 100.0,
        isProtected = false,
        isSkipped = false,
        customAmount = null,
        createdAtMillis = 1_000L
    )

    private fun history() = AllocationHistory(
        id = "history-1",
        assetId = "btc-asset",
        goalId = "goal-1",
        amount = 0.01,
        monthLabel = "2026-07",
        timestamp = 999L,
        createdAt = 999L
    )
}
