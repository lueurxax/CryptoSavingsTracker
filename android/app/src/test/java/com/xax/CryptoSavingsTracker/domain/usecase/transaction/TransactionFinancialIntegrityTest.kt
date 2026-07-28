package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.database.dao.TransactionDao
import com.xax.CryptoSavingsTracker.data.repository.TransactionRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class TransactionFinancialIntegrityTest {
    @Test
    fun `add rejects non-finite amount before any persistence`() = runTest {
        listOf(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        ).forEach { invalidAmount ->
            val fixture = addFixture()

            val failure = runCatching {
                fixture.useCase(transaction(amount = invalidAmount))
            }.exceptionOrNull()

            assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
            assertThat(failure).hasMessageThat().contains("finite")
            coVerify(exactly = 0) {
                fixture.transactionRepository.insertTransaction(any())
            }
        }
    }

    @Test
    fun `manual date beyond clock tolerance is rejected before persistence`() = runTest {
        val fixture = addFixture()
        val future = System.currentTimeMillis() + 120_000L

        val failure = runCatching {
            fixture.useCase(transaction(dateMillis = future))
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(failure).hasMessageThat().contains("future")
        coVerify(exactly = 0) {
            fixture.transactionRepository.insertTransaction(any())
        }
    }

    @Test
    fun `manual date inside clock tolerance is normalized to current time`() = runTest {
        val fixture = addFixture()
        val future = System.currentTimeMillis() + 30_000L
        val inserted = slot<Transaction>()
        coEvery {
            fixture.transactionRepository.insertTransaction(capture(inserted))
        } returns Unit

        fixture.useCase(transaction(dateMillis = future))

        assertThat(inserted.captured.dateMillis).isLessThan(future)
        assertThat(inserted.captured.dateMillis)
            .isAtMost(System.currentTimeMillis())
    }

    @Test
    fun `auto allocation arithmetic overflow fails before transaction insert`() = runTest {
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()
        val asset = Asset(
            id = "asset-1",
            currency = "USD",
            address = null,
            chainId = null,
            createdAt = 1L,
            updatedAt = 1L
        )
        val allocation = Allocation(
            id = "allocation-1",
            assetId = asset.id,
            goalId = "goal-1",
            amount = Double.MAX_VALUE,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery {
            allocationRepository.getAllocationsForAsset(asset.id)
        } returns listOf(allocation)
        coEvery {
            allocationRepository.getAllocationById(allocation.id)
        } returns allocation
        coEvery {
            transactionRepository.getManualBalanceForAsset(asset.id)
        } returns Double.MAX_VALUE

        val useCase = AddTransactionUseCase(
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryService = mockk(relaxed = true),
            assetRepository = assetRepository,
            onChainBalanceRepository = mockk(relaxed = true),
            transactionRunner = DirectTransactionIntegrityRunner
        )

        val failure = runCatching {
            useCase(transaction(amount = Double.MAX_VALUE))
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(failure).hasMessageThat().contains("overflow")
        coVerify(exactly = 0) { transactionRepository.insertTransaction(any()) }
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
    }

    @Test
    fun `persistence boundary rejects non-finite transaction`() = runTest {
        val dao = mockk<TransactionDao>(relaxed = true)
        val repository = TransactionRepositoryImpl(dao)

        val failure = runCatching {
            repository.insertTransaction(
                transaction(
                    amount = Double.POSITIVE_INFINITY,
                    source = TransactionSource.ON_CHAIN
                )
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        coVerify(exactly = 0) { dao.insert(any()) }
    }

    @Test
    fun `rejected financial update leaves persistence untouched and metadata retry succeeds`() = runTest {
        val original = transaction(
            amount = 10.0,
            dateMillis = 1_000L,
            counterparty = "Before",
            comment = "Before"
        )
        val repository = mockk<TransactionRepository>(relaxed = true)
        coEvery { repository.getTransactionById(original.id) } returns original
        val useCase = UpdateTransactionUseCase(repository)

        val amountFailure = runCatching {
            useCase(original.copy(amount = 11.0))
        }.exceptionOrNull()
        val dateFailure = runCatching {
            useCase(original.copy(dateMillis = 2_000L))
        }.exceptionOrNull()

        assertThat(amountFailure).isInstanceOf(IllegalStateException::class.java)
        assertThat(amountFailure).hasMessageThat().contains("amount")
        assertThat(dateFailure).isInstanceOf(IllegalStateException::class.java)
        assertThat(dateFailure).hasMessageThat().contains("date")

        coVerify(exactly = 0) { repository.updateTransaction(any()) }

        useCase(
            original.copy(
                counterparty = "After",
                comment = "After"
            )
        )

        coVerify(exactly = 1) {
            repository.updateTransaction(
                original.copy(
                    counterparty = "After",
                    comment = "After"
                )
            )
        }
        coVerify(exactly = 1) { repository.updateTransaction(any()) }
    }

    @Test
    fun `manual delete is rejected when allocation provenance is unavailable`() = runTest {
        val original = transaction()
        val repository = mockk<TransactionRepository>(relaxed = true)
        coEvery { repository.getTransactionById(original.id) } returns original
        val useCase = DeleteTransactionUseCase(repository)

        val byIdFailure = runCatching {
            useCase(original.id)
        }.exceptionOrNull()
        val byValueFailure = runCatching {
            useCase.delete(original)
        }.exceptionOrNull()

        assertThat(byIdFailure).isInstanceOf(IllegalStateException::class.java)
        assertThat(byIdFailure).hasMessageThat().contains("automatic allocation")
        assertThat(byValueFailure).isInstanceOf(IllegalStateException::class.java)
        coVerify(exactly = 0) { repository.deleteTransaction(any<String>()) }
        coVerify(exactly = 0) { repository.deleteTransaction(any<Transaction>()) }
    }

    private fun addFixture(): AddFixture {
        val transactions = mockk<TransactionRepository>(relaxed = true)
        val allocations = mockk<AllocationRepository>(relaxed = true)
        val assets = mockk<AssetRepository>(relaxed = true)
        coEvery { assets.getAssetById(any()) } returns null
        return AddFixture(
            useCase = AddTransactionUseCase(
                transactionRepository = transactions,
                allocationRepository = allocations,
                allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true),
                assetRepository = assets,
                onChainBalanceRepository = mockk<OnChainBalanceRepository>(relaxed = true),
                transactionRunner = DirectTransactionIntegrityRunner
            ),
            transactionRepository = transactions
        )
    }

    private fun transaction(
        amount: Double = 1.0,
        dateMillis: Long = 1_000L,
        source: TransactionSource = TransactionSource.MANUAL,
        counterparty: String? = null,
        comment: String? = null
    ) = Transaction(
        id = "transaction-1",
        assetId = "asset-1",
        amount = amount,
        dateMillis = dateMillis,
        source = source,
        externalId = null,
        counterparty = counterparty,
        comment = comment,
        createdAt = 1_000L
    )

    private data class AddFixture(
        val useCase: AddTransactionUseCase,
        val transactionRepository: TransactionRepository
    )
}

private object DirectTransactionIntegrityRunner : ExecutionTransitionTransactionRunner {
    override suspend fun <T> run(block: suspend () -> T): T = block()
}
