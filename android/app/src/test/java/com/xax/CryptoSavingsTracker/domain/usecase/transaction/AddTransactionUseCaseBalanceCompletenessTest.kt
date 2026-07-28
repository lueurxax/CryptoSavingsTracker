package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceUnavailableException
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class AddTransactionUseCaseBalanceCompletenessTest {
    @Test
    fun `dedicated allocation mutation fails before insert when addressed balance is unavailable`() = runTest {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qwallet",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        val allocation = Allocation(
            id = "allocation-1",
            assetId = asset.id,
            goalId = "goal-1",
            amount = 10.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val transaction = Transaction(
            id = "transaction-1",
            assetId = asset.id,
            amount = 1.0,
            dateMillis = 2L,
            source = TransactionSource.MANUAL,
            externalId = null,
            counterparty = null,
            comment = null,
            createdAt = 2L
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()
        val allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true)

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 10.0
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
        coEvery { allocationRepository.getAllocationById(allocation.id) } returns allocation
        coEvery { onChainBalanceRepository.getBalance(asset, forceRefresh = false) } returns
            Result.failure(IllegalStateException("provider offline"))

        val useCase = AddTransactionUseCase(
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryService = allocationHistoryService,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = ImmediateTransactionRunner
        )

        val failure = runCatching {
            useCase(transaction)
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(AssetBalanceUnavailableException::class.java)
        coVerify(exactly = 0) { transactionRepository.insertTransaction(any()) }
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
    }

    @Test
    fun `ordinary transaction without a dedicated allocation does not require provider balance`() = runTest {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qwallet",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        val transaction = Transaction(
            id = "transaction-1",
            assetId = asset.id,
            amount = 1.0,
            dateMillis = 2L,
            source = TransactionSource.MANUAL,
            externalId = null,
            counterparty = null,
            comment = null,
            createdAt = 2L
        )
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns emptyList()

        AddTransactionUseCase(
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryService = mockk(relaxed = true),
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = ImmediateTransactionRunner
        )(transaction)

        coVerify(exactly = 0) { onChainBalanceRepository.getBalance(any(), any()) }
        coVerify(exactly = 1) { transactionRepository.insertTransaction(transaction) }
    }

    @Test
    fun `backdated manual deposit remains unallocated behind newer allocation history`() = runTest {
        val asset = asset(address = null, chainId = null)
        val allocation = allocation(amount = 10.0)
        val transaction = transaction(amount = 1.0).copy(dateMillis = 100L)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()
        val allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true)
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>(relaxed = true)

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns
            listOf(allocation)
        coEvery {
            allocationHistoryService.hasEvidenceNewerThan(
                assetId = asset.id,
                goalId = allocation.goalId,
                timestampMillis = transaction.dateMillis
            )
        } returns true

        AddTransactionUseCase(
            transactionRepository = transactionRepository,
            allocationRepository = allocationRepository,
            allocationHistoryService = allocationHistoryService,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            transactionRunner = ImmediateTransactionRunner
        )(transaction)

        coVerify(exactly = 1) { transactionRepository.insertTransaction(transaction) }
        coVerify(exactly = 0) { transactionRepository.getManualBalanceForAsset(any()) }
        coVerify(exactly = 0) { onChainBalanceRepository.getBalance(any(), any()) }
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
        coVerify(exactly = 0) {
            allocationHistoryService.createSnapshot(any(), any())
        }
    }

    @Test
    fun `provider identity changed during balance fetch fails inside commit boundary`() = runTest {
        val original = asset(address = "0xwallet-a")
        val changed = original.copy(address = "0xwallet-b", updatedAt = 2L)
        val allocation = allocation(amount = 10.0)
        val transaction = transaction(amount = 1.0)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()

        coEvery { assetRepository.getAssetById(original.id) } returnsMany
            listOf(original, changed)
        coEvery { allocationRepository.getAllocationsForAsset(original.id) } returns
            listOf(allocation)
        coEvery { transactionRepository.getManualBalanceForAsset(original.id) } returns 4.0
        coEvery {
            onChainBalanceRepository.getBalance(original, forceRefresh = false)
        } returns Result.success(
            OnChainBalance(
                assetId = original.id,
                chainId = checkNotNull(original.chainId),
                address = checkNotNull(original.address),
                currency = original.currency,
                balance = 6.0,
                fetchedAtMillis = System.currentTimeMillis(),
                isStale = false
            )
        )

        val failure = runCatching {
            AddTransactionUseCase(
                transactionRepository = transactionRepository,
                allocationRepository = allocationRepository,
                allocationHistoryService = mockk(relaxed = true),
                assetRepository = assetRepository,
                onChainBalanceRepository = onChainBalanceRepository,
                transactionRunner = ImmediateTransactionRunner
            )(transaction)
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("identity changed")
        coVerify(exactly = 0) { transactionRepository.insertTransaction(any()) }
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
    }

    @Test
    fun `allocation changed after preflight fails before transaction insert`() = runTest {
        val asset = asset(address = null, chainId = null)
        val allocation = allocation(amount = 10.0)
        val changedAllocation = allocation.copy(amount = 9.0, lastModifiedAt = 2L)
        val transaction = transaction(amount = 1.0)
        val transactionRepository = mockk<TransactionRepository>(relaxed = true)
        val allocationRepository = mockk<AllocationRepository>(relaxed = true)
        val assetRepository = mockk<AssetRepository>()

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returnsMany
            listOf(listOf(allocation), listOf(changedAllocation))
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 10.0

        val failure = runCatching {
            AddTransactionUseCase(
                transactionRepository = transactionRepository,
                allocationRepository = allocationRepository,
                allocationHistoryService = mockk(relaxed = true),
                assetRepository = assetRepository,
                onChainBalanceRepository = mockk(relaxed = true),
                transactionRunner = ImmediateTransactionRunner
            )(transaction)
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("allocation changed")
        coVerify(exactly = 0) { transactionRepository.insertTransaction(any()) }
        coVerify(exactly = 0) { allocationRepository.upsertAllocation(any()) }
    }

    private fun asset(
        address: String?,
        chainId: String? = "ethereum"
    ) = Asset(
        id = "asset-1",
        currency = "ETH",
        address = address,
        chainId = chainId,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun allocation(amount: Double) = Allocation(
        id = "allocation-1",
        assetId = "asset-1",
        goalId = "goal-1",
        amount = amount,
        createdAt = 1L,
        lastModifiedAt = 1L
    )

    private fun transaction(amount: Double) = Transaction(
        id = "transaction-1",
        assetId = "asset-1",
        amount = amount,
        dateMillis = 2L,
        source = TransactionSource.MANUAL,
        externalId = null,
        counterparty = null,
        comment = null,
        createdAt = 2L
    )
}

private object ImmediateTransactionRunner : ExecutionTransitionTransactionRunner {
    override suspend fun <T> run(block: suspend () -> T): T = block()
}
