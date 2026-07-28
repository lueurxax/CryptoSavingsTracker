package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ManageAllocationUseCaseTest {
    @Test
    fun `add rejects an asset created after nonlegacy execution started`() = runTest {
        val dependencies = dependencies(
            activeRecord = executionRecord(),
            persistedRates = emptyList()
        )

        val result = dependencies.add()(
            assetId = "new-eth-asset",
            goalId = "goal-1",
            amount = 1.0
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution rate snapshot")
        coVerify(exactly = 0) { dependencies.allocations.upsertAllocation(any()) }
        coVerify(exactly = 0) { dependencies.history.createSnapshot(any()) }
    }

    @Test
    fun `update rejects an asset created after nonlegacy execution started`() = runTest {
        val dependencies = dependencies(
            activeRecord = executionRecord(),
            persistedRates = emptyList()
        )
        val allocation = allocation(assetId = "new-eth-asset")

        val result = dependencies.update()(allocation)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution rate snapshot")
        coVerify(exactly = 0) { dependencies.allocations.upsertAllocation(any()) }
        coVerify(exactly = 0) { dependencies.history.createSnapshot(any()) }
    }

    @Test
    fun `add allows an existing snapshotted asset to be allocated later`() = runTest {
        val dependencies = dependencies(
            activeRecord = executionRecord(),
            persistedRates = listOf(
                ExecutionAssetRate(
                    assetId = "existing-eth-asset",
                    snapshotCurrency = "USD",
                    rate = 2_000.0,
                    capturedAtMillis = 1_000L
                )
            )
        )

        val result = dependencies.add()(
            assetId = "existing-eth-asset",
            goalId = "goal-1",
            amount = 1.0
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrThrow().assetId).isEqualTo("existing-eth-asset")
        coVerify(exactly = 1) {
            dependencies.allocations.upsertAllocation(
                match { it.assetId == "existing-eth-asset" && it.goalId == "goal-1" }
            )
        }
        coVerify(exactly = 1) {
            dependencies.history.createSnapshot(
                match { it.assetId == "existing-eth-asset" && it.goalId == "goal-1" }
            )
        }
    }

    @Test
    fun `legacy pending execution rejects allocation until backfill completes`() = runTest {
        val dependencies = dependencies(
            activeRecord = executionRecord(legacyRateSnapshotPending = true),
            persistedRates = emptyList()
        )

        val result = dependencies.add()(
            assetId = "existing-eth-asset",
            goalId = "goal-1",
            amount = 1.0
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("still preparing")
        coVerify(exactly = 0) { dependencies.executionRates.getByRecordId(any()) }
        coVerify(exactly = 0) { dependencies.allocations.upsertAllocation(any()) }
        coVerify(exactly = 0) { dependencies.history.createSnapshot(any()) }
    }

    @Test
    fun `legacy pending execution rejects allocation update until backfill completes`() = runTest {
        val dependencies = dependencies(
            activeRecord = executionRecord(legacyRateSnapshotPending = true),
            persistedRates = emptyList()
        )

        val result = dependencies.update()(allocation(assetId = "existing-eth-asset"))

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("still preparing")
        coVerify(exactly = 0) { dependencies.executionRates.getByRecordId(any()) }
        coVerify(exactly = 0) { dependencies.allocations.upsertAllocation(any()) }
        coVerify(exactly = 0) { dependencies.history.createSnapshot(any()) }
    }

    @Test
    fun `add rejects an unsnapshotted asset while a closed execution remains undoable`() = runTest {
        val dependencies = dependencies(
            activeRecord = null,
            persistedRates = emptyList(),
            reversibleRecords = listOf(closedUndoableRecord())
        )

        val result = dependencies.add()(
            assetId = "new-eth-asset",
            goalId = "goal-1",
            amount = 1.0
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution rate snapshot")
        coVerify(exactly = 0) { dependencies.allocations.upsertAllocation(any()) }
        coVerify(exactly = 0) { dependencies.history.createSnapshot(any()) }
    }

    @Test
    fun `add waits for an execution commit then rechecks rate coverage`() = runTest {
        val runner = MutexTransactionRunner()
        val activeRecords = MutableStateFlow(emptyList<ExecutionRecord>())
        val storedAllocations = mutableListOf<Allocation>()
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationByAssetAndGoal(any(), any()) } returns null
            coEvery { upsertAllocation(any()) } answers {
                storedAllocations += firstArg<Allocation>()
            }
        }
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val validation = mockk<AllocationValidationService> {
            coEvery { validateAllocation(any(), any(), any(), any()) } returns null
        }
        val records = mockk<ExecutionRecordRepository> {
            every { getAllRecords() } returns activeRecords
        }
        val executionRates = mockk<ExecutionAssetRateRepository> {
            every { getByRecordId(any()) } returns flowOf(emptyList())
        }
        val executionHasLock = CompletableDeferred<Unit>()
        val allowExecutionCommit = CompletableDeferred<Unit>()
        val executionCommit = launch {
            runner.run {
                executionHasLock.complete(Unit)
                allowExecutionCommit.await()
                activeRecords.value = listOf(executionRecord())
            }
        }
        executionHasLock.await()

        val allocationResult = async {
            AddAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(
                assetId = "new-eth-asset",
                goalId = "goal-1",
                amount = 1.0
            )
        }
        yield()
        allowExecutionCommit.complete(Unit)
        executionCommit.join()

        val result = allocationResult.await()
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution rate snapshot")
        assertThat(storedAllocations).isEmpty()
    }

    @Test
    fun `update waits for an execution commit then rechecks rate coverage`() = runTest {
        val runner = MutexTransactionRunner()
        val activeRecords = MutableStateFlow(emptyList<ExecutionRecord>())
        val storedAllocations = mutableListOf<Allocation>()
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { upsertAllocation(any()) } answers {
                storedAllocations += firstArg<Allocation>()
            }
        }
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val validation = mockk<AllocationValidationService> {
            coEvery { validateAllocation(any(), any(), any(), any()) } returns null
        }
        val records = mockk<ExecutionRecordRepository> {
            every { getAllRecords() } returns activeRecords
        }
        val executionRates = mockk<ExecutionAssetRateRepository> {
            every { getByRecordId(any()) } returns flowOf(emptyList())
        }
        val executionHasLock = CompletableDeferred<Unit>()
        val allowExecutionCommit = CompletableDeferred<Unit>()
        val executionCommit = launch {
            runner.run {
                executionHasLock.complete(Unit)
                allowExecutionCommit.await()
                activeRecords.value = listOf(executionRecord())
            }
        }
        executionHasLock.await()

        val allocationResult = async {
            UpdateAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(allocation(assetId = "new-eth-asset"))
        }
        yield()
        allowExecutionCommit.complete(Unit)
        executionCommit.join()

        val result = allocationResult.await()
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("execution rate snapshot")
        assertThat(storedAllocations).isEmpty()
    }

    @Test
    fun `concurrent adds cannot jointly overallocate an asset`() = runTest {
        val runner = MutexTransactionRunner()
        val storedAllocations = mutableListOf<Allocation>()
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers {
                storedAllocations.toList()
            }
            coEvery { getAllocationByAssetAndGoal("asset-1", any()) } answers {
                val goalId = secondArg<String>()
                storedAllocations.firstOrNull { it.assetId == "asset-1" && it.goalId == goalId }
            }
            coEvery { upsertAllocation(any()) } answers {
                val allocation = firstArg<Allocation>()
                storedAllocations.removeAll { it.id == allocation.id }
                storedAllocations += allocation
            }
        }
        val validation = allocationValidation(allocations = storedAllocations, maximum = 1.0)
        val records = emptyExecutionRecords()
        val executionRates = emptyExecutionRates()
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val lockHeld = CompletableDeferred<Unit>()
        val releaseLock = CompletableDeferred<Unit>()
        val blocker = launch {
            runner.run {
                lockHeld.complete(Unit)
                releaseLock.await()
            }
        }
        lockHeld.await()

        val first = async {
            AddAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(assetId = "asset-1", goalId = "goal-1", amount = 0.6)
        }
        val second = async {
            AddAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(assetId = "asset-1", goalId = "goal-2", amount = 0.6)
        }
        runCurrent()
        releaseLock.complete(Unit)
        blocker.join()

        val results = listOf(first.await(), second.await())
        assertThat(results.count { it.isSuccess }).isEqualTo(1)
        assertThat(results.count { it.isFailure }).isEqualTo(1)
        assertThat(storedAllocations.sumOf { it.amount }).isWithin(0.0000001).of(0.6)
    }

    @Test
    fun `concurrent updates cannot jointly overallocate an asset`() = runTest {
        val firstAllocation = Allocation(
            id = "allocation-1",
            assetId = "asset-1",
            goalId = "goal-1",
            amount = 0.4,
            createdAt = 1_000L,
            lastModifiedAt = 1_000L
        )
        val secondAllocation = firstAllocation.copy(
            id = "allocation-2",
            goalId = "goal-2"
        )
        val storedAllocations = mutableListOf(firstAllocation, secondAllocation)
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } answers {
                storedAllocations.toList()
            }
            coEvery { upsertAllocation(any()) } answers {
                val allocation = firstArg<Allocation>()
                storedAllocations.removeAll { it.id == allocation.id }
                storedAllocations += allocation
            }
        }
        val runner = MutexTransactionRunner()
        val validation = allocationValidation(allocations = storedAllocations, maximum = 1.0)
        val records = emptyExecutionRecords()
        val executionRates = emptyExecutionRates()
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val lockHeld = CompletableDeferred<Unit>()
        val releaseLock = CompletableDeferred<Unit>()
        val blocker = launch {
            runner.run {
                lockHeld.complete(Unit)
                releaseLock.await()
            }
        }
        lockHeld.await()

        val first = async {
            UpdateAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(firstAllocation.copy(amount = 0.6))
        }
        val second = async {
            UpdateAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                validationService = validation,
                executionRecordRepository = records,
                executionAssetRateRepository = executionRates,
                transactionRunner = runner
            )(secondAllocation.copy(amount = 0.6))
        }
        runCurrent()
        releaseLock.complete(Unit)
        blocker.join()

        val results = listOf(first.await(), second.await())
        assertThat(results.count { it.isSuccess }).isEqualTo(1)
        assertThat(results.count { it.isFailure }).isEqualTo(1)
        assertThat(storedAllocations.sumOf { it.amount }).isWithin(0.0000001).of(1.0)
    }

    @Test
    fun `delete waits until execution scope capture has read allocations`() = runTest {
        val runner = MutexTransactionRunner()
        val existing = allocation(assetId = "btc-asset")
        val storedAllocations = mutableListOf(existing)
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("btc-asset") } answers {
                storedAllocations.toList()
            }
            coEvery { deleteAllocationsForAsset("btc-asset") } answers {
                storedAllocations.clear()
            }
        }
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val captureHasLock = CompletableDeferred<Unit>()
        val allowScopeRead = CompletableDeferred<Unit>()
        var capturedAllocations = emptyList<Allocation>()
        val scopeCapture = launch {
            runner.run {
                captureHasLock.complete(Unit)
                allowScopeRead.await()
                capturedAllocations = allocations.getAllocationsForAsset("btc-asset")
            }
        }
        captureHasLock.await()

        val deleteResult = async {
            DeleteAllocationUseCase(
                allocationRepository = allocations,
                allocationHistoryService = history,
                transactionRunner = runner
            ).deleteForAsset("btc-asset")
        }
        yield()
        allowScopeRead.complete(Unit)
        scopeCapture.join()

        assertThat(deleteResult.await().isSuccess).isTrue()
        assertThat(capturedAllocations).containsExactly(existing)
        assertThat(storedAllocations).isEmpty()
    }

    private fun dependencies(
        activeRecord: ExecutionRecord?,
        persistedRates: List<ExecutionAssetRate>,
        reversibleRecords: List<ExecutionRecord> = listOfNotNull(activeRecord),
        transactionRunner: ExecutionTransitionTransactionRunner = DirectTransactionRunner
    ): Dependencies {
        val allocations = mockk<AllocationRepository>(relaxed = true)
        val history = mockk<AllocationHistoryService>(relaxed = true)
        val validation = mockk<AllocationValidationService>()
        val records = mockk<ExecutionRecordRepository>()
        val executionRates = mockk<ExecutionAssetRateRepository>()

        coEvery { validation.validateAllocation(any(), any(), any(), any()) } returns null
        coEvery { allocations.getAllocationByAssetAndGoal(any(), any()) } returns null
        every { records.getCurrentExecutingRecord() } returns flowOf(activeRecord)
        every { records.getAllRecords() } returns flowOf(reversibleRecords)
        every { executionRates.getByRecordId(any()) } returns flowOf(persistedRates)

        return Dependencies(
            allocations = allocations,
            history = history,
            validation = validation,
            records = records,
            executionRates = executionRates,
            transactionRunner = transactionRunner
        )
    }

    private fun executionRecord(
        legacyRateSnapshotPending: Boolean = false
    ) = ExecutionRecord(
        id = "execution-1",
        planId = "plan-1",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = 1_000L,
        closedAtMillis = null,
        canUndoUntilMillis = null,
        createdAtMillis = 1_000L,
        updatedAtMillis = 1_000L,
        legacyRateSnapshotPending = legacyRateSnapshotPending
    )

    private fun allocation(assetId: String) = Allocation(
        id = "allocation-1",
        assetId = assetId,
        goalId = "goal-1",
        amount = 1.0,
        createdAt = 1_000L,
        lastModifiedAt = 1_000L
    )

    private fun closedUndoableRecord() = executionRecord().copy(
        status = ExecutionStatus.CLOSED,
        closedAtMillis = System.currentTimeMillis() - 1_000L,
        canUndoUntilMillis = System.currentTimeMillis() + 60_000L
    )

    private fun allocationValidation(
        allocations: List<Allocation>,
        maximum: Double
    ) = mockk<AllocationValidationService> {
        coEvery { validateAllocation(any(), any(), any(), any()) } answers {
            val amount = thirdArg<Double>()
            val excludeAllocationId = arg<String?>(3)
            val allocated = allocations
                .filter { it.id != excludeAllocationId }
                .sumOf { it.amount }
            if (allocated + amount > maximum + 0.0000001) {
                "Amount exceeds available balance"
            } else {
                null
            }
        }
    }

    private fun emptyExecutionRecords() = mockk<ExecutionRecordRepository> {
        every { getAllRecords() } returns flowOf(emptyList())
    }

    private fun emptyExecutionRates() = mockk<ExecutionAssetRateRepository> {
        every { getByRecordId(any()) } returns flowOf(emptyList())
    }

    private data class Dependencies(
        val allocations: AllocationRepository,
        val history: AllocationHistoryService,
        val validation: AllocationValidationService,
        val records: ExecutionRecordRepository,
        val executionRates: ExecutionAssetRateRepository,
        val transactionRunner: ExecutionTransitionTransactionRunner
    ) {
        fun add() = AddAllocationUseCase(
            allocationRepository = allocations,
            allocationHistoryService = history,
            validationService = validation,
            executionRecordRepository = records,
            executionAssetRateRepository = executionRates,
            transactionRunner = transactionRunner
        )

        fun update() = UpdateAllocationUseCase(
            allocationRepository = allocations,
            allocationHistoryService = history,
            validationService = validation,
            executionRecordRepository = records,
            executionAssetRateRepository = executionRates,
            transactionRunner = transactionRunner
        )
    }

    private object DirectTransactionRunner : ExecutionTransitionTransactionRunner {
        override suspend fun <T> run(block: suspend () -> T): T = block()
    }

    private class MutexTransactionRunner : ExecutionTransitionTransactionRunner {
        private val mutex = Mutex()

        override suspend fun <T> run(block: suspend () -> T): T {
            return mutex.withLock { block() }
        }
    }
}
