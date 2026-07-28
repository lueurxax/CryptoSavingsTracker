package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Test

class UpdateAssetUseCaseTest {
    @Test
    fun `addressed update rejects unsupported route without persisting partial changes`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val existing = asset(currency = "USDT").copy(chainId = "ethereum")
        coEvery { repository.getAssetById(existing.id) } returns existing

        val result = useCase(repository, records, rates).invoke(
            existing.copy(chainId = "polygon")
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("automatic balance tracking")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `update without address keeps unsupported route as manual tracking`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val existing = asset(currency = "USDT").copy(address = null, chainId = "ethereum")
        coEvery { repository.getAssetById(existing.id) } returns existing
        every { records.getAllRecords() } returns flowOf(emptyList())

        val result = useCase(repository, records, rates).invoke(
            existing.copy(chainId = "polygon")
        )

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) {
            repository.updateAsset(match { it.address == null && it.chainId == "polygon" })
        }
    }

    @Test
    fun `same wallet address owned by another currency does not block composite update`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val existing = asset(currency = "USDC").copy(
            address = "old-address",
            chainId = "ethereum"
        )
        val ethAtTargetAddress = existing.copy(
            id = "eth-asset",
            currency = "ETH",
            address = "0xshared"
        )
        coEvery { repository.getAssetById(existing.id) } returns existing
        coEvery { repository.getAssetByAddress("0xshared") } returns ethAtTargetAddress
        coEvery {
            repository.getAssetByOnChainIdentity("0xshared", "ethereum", "USDC")
        } returns null
        every { records.getAllRecords() } returns flowOf(emptyList())

        val result = useCase(repository, records, rates).invoke(
            existing.copy(address = "0xshared")
        )

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 1) {
            repository.updateAsset(match {
                it.id == existing.id &&
                    it.address == "0xshared" &&
                    it.chainId == "ethereum" &&
                    it.currency == "USDC"
            })
        }
    }

    @Test
    fun `currency change is rejected when active execution already snapshotted the asset`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val existing = asset(currency = "ETH").copy(chainId = "ethereum")
        val execution = executingRecord()
        coEvery { repository.getAssetById(existing.id) } returns existing
        every { records.getAllRecords() } returns flowOf(listOf(execution))
        every { rates.getByRecordId(execution.id) } returns flowOf(
            listOf(ExecutionAssetRate(existing.id, "USD", 10_000.0, 1_000L))
        )

        val result = useCase(repository, records, rates).invoke(
            existing.copy(currency = "USDC")
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity cannot be changed during a reversible execution")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `wallet address change is rejected for a snapshotted asset`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val existing = asset(currency = "BTC")
        val execution = executingRecord()
        coEvery { repository.getAssetById(existing.id) } returns existing
        coEvery {
            repository.getAssetByOnChainIdentity("new-address", "bitcoin", "BTC")
        } returns null
        every { records.getAllRecords() } returns flowOf(listOf(execution))
        every { rates.getByRecordId(execution.id) } returns flowOf(
            listOf(ExecutionAssetRate(existing.id, "USD", 10_000.0, 1_000L))
        )

        val result = useCase(repository, records, rates).invoke(
            existing.copy(address = " new-address ")
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity cannot be changed during a reversible execution")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `canonical wallet alias is not treated as a provider identity change`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val existing = asset(currency = "BTC").copy(address = "bc1qexampleaddress")
        coEvery { repository.getAssetById(existing.id) } returns existing
        coEvery {
            repository.getAssetByOnChainIdentity(
                "bc1qexampleaddress",
                "bitcoin",
                "BTC"
            )
        } returns existing

        val transactions = mockk<TransactionRepository>(relaxed = true) {
            coEvery { getTransactionCountForAsset(existing.id) } returns 1
        }

        val result = useCase(
            repository,
            records,
            rates,
            transactionRepository = transactions
        ).invoke(
            existing.copy(address = "BC1QEXAMPLEADDRESS")
        )

        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrThrow().address).isEqualTo("bc1qexampleaddress")
        coVerify(exactly = 0) { records.getAllRecords() }
        coVerify(exactly = 0) { transactions.getTransactionCountForAsset(any()) }
        coVerify(exactly = 1) {
            repository.updateAsset(match { it.address == "bc1qexampleaddress" })
        }
    }

    @Test
    fun `cross encoding UTXO alias is not a provider identity change`() = runTest {
        val cases = listOf(
            arrayOf(
                "BCH",
                "bitcoin-cash",
                "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu",
                "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
            ),
            arrayOf(
                "LTC",
                "litecoin",
                "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC",
                "MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN"
            )
        )

        cases.forEach { (currency, chainId, legacyAddress, canonicalAddress) ->
            val repository = mockk<AssetRepository>(relaxed = true)
            val records = mockk<ExecutionRecordRepository>(relaxed = true)
            val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
            val existing = asset(currency = currency).copy(
                address = legacyAddress,
                chainId = chainId
            )
            coEvery { repository.getAssetById(existing.id) } returns existing
            coEvery {
                repository.getAssetByOnChainIdentity(
                    canonicalAddress,
                    chainId,
                    currency
                )
            } returns existing
            val transactions = mockk<TransactionRepository>(relaxed = true) {
                coEvery { getTransactionCountForAsset(existing.id) } returns 1
            }

            val result = useCase(
                repository,
                records,
                rates,
                transactionRepository = transactions
            ).invoke(existing.copy(address = canonicalAddress))

            assertThat(result.isSuccess).isTrue()
            assertThat(result.getOrThrow().address).isEqualTo(canonicalAddress)
            coVerify(exactly = 0) { transactions.getTransactionCountForAsset(any()) }
            coVerify(exactly = 1) {
                repository.updateAsset(match { it.address == canonicalAddress })
            }
        }
    }

    @Test
    fun `currency change is blocked by mixed manual and on-chain transaction history`() =
        runTest {
            val repository = mockk<AssetRepository>(relaxed = true)
            val records = mockk<ExecutionRecordRepository>(relaxed = true)
            val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
            val transactions = mockk<TransactionRepository>(relaxed = true) {
                coEvery { getTransactionCountForAsset("asset-1") } returns 2
            }
            val existing = asset(currency = "ETH").copy(
                address = "0xwallet",
                chainId = "ethereum"
            )
            coEvery { repository.getAssetById(existing.id) } returns existing

            val result = useCase(
                repository,
                records,
                rates,
                transactionRepository = transactions
            ).invoke(existing.copy(currency = "USDC"))

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat()
                .contains("dependent financial activity")
            coVerify(exactly = 0) { repository.updateAsset(any()) }
        }

    @Test
    fun `network change is blocked by a current allocation`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>(relaxed = true) {
            coEvery { getAllocationsForAsset("asset-1") } returns listOf(
                Allocation(
                    id = "allocation-1",
                    assetId = "asset-1",
                    goalId = "goal-1",
                    amount = 1.0,
                    createdAt = 1L,
                    lastModifiedAt = 1L
                )
            )
        }
        val existing = asset(currency = "ETH").copy(
            address = "0xwallet",
            chainId = "ethereum"
        )
        coEvery { repository.getAssetById(existing.id) } returns existing

        val result = useCase(
            repository,
            records,
            rates,
            allocationRepository = allocations
        ).invoke(existing.copy(chainId = "base"))

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("dependent financial activity")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `address change is blocked by historical allocation evidence alone`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val rates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val history = mockk<AllocationHistoryRepository>(relaxed = true) {
            every { getByAssetId("asset-1") } returns flowOf(
                listOf(
                    AllocationHistory(
                        id = "history-1",
                        assetId = "asset-1",
                        goalId = "goal-1",
                        amount = 1.0,
                        monthLabel = "2026-07",
                        timestamp = 1L,
                        createdAt = 1L
                    )
                )
            )
        }
        val existing = asset(currency = "BTC")
        coEvery { repository.getAssetById(existing.id) } returns existing

        val result = useCase(
            repository,
            records,
            rates,
            allocationHistoryRepository = history
        ).invoke(existing.copy(address = "new-address"))

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("dependent financial activity")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `currency change is rejected while a completed execution can still be undone`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val existing = asset(currency = "ETH").copy(chainId = "ethereum")
        val execution = closedUndoableRecord()
        coEvery { repository.getAssetById(existing.id) } returns existing
        every { records.getAllRecords() } returns flowOf(listOf(execution))
        every { rates.getByRecordId(execution.id) } returns flowOf(
            listOf(ExecutionAssetRate(existing.id, "USD", 10_000.0, 1_000L))
        )

        val result = useCase(repository, records, rates).invoke(
            existing.copy(currency = "USDC")
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity cannot be changed during a reversible execution")
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `currency change is rejected while legacy execution rates are pending`() = runTest {
        val repository = mockk<AssetRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>()
        val rates = mockk<ExecutionAssetRateRepository>()
        val existing = asset(currency = "ETH").copy(chainId = "ethereum")
        val execution = executingRecord().copy(legacyRateSnapshotPending = true)
        coEvery { repository.getAssetById(existing.id) } returns existing
        every { records.getAllRecords() } returns flowOf(listOf(execution))

        val result = useCase(repository, records, rates).invoke(
            existing.copy(currency = "USDC")
        )

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity cannot be changed during a reversible execution")
        coVerify(exactly = 0) { rates.getByRecordId(any()) }
        coVerify(exactly = 0) { repository.updateAsset(any()) }
    }

    @Test
    fun `currency update waits for an execution commit then rechecks reversible records`() = runTest {
        val runner = MutexTransactionRunner()
        var storedAsset = asset(currency = "ETH").copy(chainId = "ethereum")
        val repository = mockk<AssetRepository>(relaxed = true) {
            coEvery { getAssetById(storedAsset.id) } answers { storedAsset }
            coEvery { updateAsset(any()) } answers {
                storedAsset = firstArg()
            }
        }
        val activeRecords = MutableStateFlow(emptyList<ExecutionRecord>())
        val records = mockk<ExecutionRecordRepository> {
            every { getAllRecords() } returns activeRecords
        }
        val rates = mockk<ExecutionAssetRateRepository> {
            every { getByRecordId(any()) } returns flowOf(
                listOf(ExecutionAssetRate(storedAsset.id, "USD", 10_000.0, 1_000L))
            )
        }
        val executionHasLock = CompletableDeferred<Unit>()
        val allowExecutionCommit = CompletableDeferred<Unit>()
        val executionCommit = launch {
            runner.run {
                executionHasLock.complete(Unit)
                allowExecutionCommit.await()
                activeRecords.value = listOf(executingRecord())
            }
        }
        executionHasLock.await()

        val updateResult = async {
            useCase(repository, records, rates, runner).invoke(
                storedAsset.copy(currency = "USDC")
            )
        }
        yield()
        allowExecutionCommit.complete(Unit)
        executionCommit.join()

        val result = updateResult.await()
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat()
            .contains("provider identity cannot be changed during a reversible execution")
        assertThat(storedAsset.currency).isEqualTo("ETH")
    }

    private fun useCase(
        repository: AssetRepository,
        records: ExecutionRecordRepository,
        rates: ExecutionAssetRateRepository,
        transactionRunner: ExecutionTransitionTransactionRunner = DirectTransactionRunner,
        transactionRepository: TransactionRepository = emptyTransactionRepository(),
        allocationRepository: AllocationRepository = emptyAllocationRepository(),
        allocationHistoryRepository: AllocationHistoryRepository = emptyHistoryRepository()
    ) = UpdateAssetUseCase(
        repository = repository,
        executionRecordRepository = records,
        executionAssetRateRepository = rates,
        transactionRunner = transactionRunner,
        transactionRepository = transactionRepository,
        allocationRepository = allocationRepository,
        allocationHistoryRepository = allocationHistoryRepository
    )

    private fun emptyTransactionRepository() = mockk<TransactionRepository>(relaxed = true) {
        coEvery { getTransactionCountForAsset(any()) } returns 0
    }

    private fun emptyAllocationRepository() = mockk<AllocationRepository>(relaxed = true) {
        coEvery { getAllocationsForAsset(any()) } returns emptyList()
    }

    private fun emptyHistoryRepository() = mockk<AllocationHistoryRepository>(relaxed = true) {
        every { getByAssetId(any()) } returns flowOf(emptyList())
    }

    private fun asset(currency: String) = Asset(
        id = "asset-1",
        currency = currency,
        address = "old-address",
        chainId = "bitcoin",
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun executingRecord() = ExecutionRecord(
        id = "execution-1",
        planId = "plan-1",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = 1_000L,
        closedAtMillis = null,
        canUndoUntilMillis = null,
        createdAtMillis = 1_000L,
        updatedAtMillis = 1_000L
    )

    private fun closedUndoableRecord() = executingRecord().copy(
        status = ExecutionStatus.CLOSED,
        closedAtMillis = System.currentTimeMillis() - 1_000L,
        canUndoUntilMillis = System.currentTimeMillis() + 60_000L
    )

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
