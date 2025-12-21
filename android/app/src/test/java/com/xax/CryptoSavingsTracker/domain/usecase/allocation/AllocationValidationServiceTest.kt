package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.util.Locale

class AllocationValidationServiceTest {
    @Test
    fun validateAllocation_blocksWhenExceedsAvailableBalance() = runTest {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = null,
            chainId = null,
            createdAt = 1L,
            updatedAt = 1L
        )

        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 100.0
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(
            Allocation(
                id = "a1",
                assetId = asset.id,
                goalId = "g1",
                amount = 60.0,
                createdAt = 1L,
                lastModifiedAt = 1L
            )
        )
        coEvery { allocationRepository.getAllocationByAssetAndGoal(asset.id, "g2") } returns null
        coEvery { onChainBalanceRepository.getBalance(any(), any()) } returns Result.failure(IllegalStateException("No key"))

        val service = AllocationValidationService(
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )

        val message = service.validateAllocation(
            assetId = asset.id,
            goalId = "g2",
            amount = 50.0
        )

        assertThat(message).isNotNull()
        assertThat(message).contains("exceeds available balance")
    }

    @Test
    fun validateAllocation_includesOnChainInBalance() = runTest {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()

        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 0.0
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns emptyList()
        coEvery { allocationRepository.getAllocationByAssetAndGoal(asset.id, "g1") } returns null
        coEvery { onChainBalanceRepository.getBalance(asset, any()) } returns Result.success(
            OnChainBalance(
                assetId = asset.id,
                chainId = asset.chainId!!,
                address = asset.address!!,
                currency = asset.currency,
                balance = 10.0,
                fetchedAtMillis = 1L,
                isStale = true
            )
        )

        val service = AllocationValidationService(
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository
        )

        val ok = service.validateAllocation(
            assetId = asset.id,
            goalId = "g1",
            amount = 9.0
        )
        val tooMuch = service.validateAllocation(
            assetId = asset.id,
            goalId = "g1",
            amount = 11.0
        )

        assertThat(ok).isNull()
        assertThat(tooMuch).isNotNull()
    }

    @Test
    fun validateAllocation_cryptoErrorUsesSixDecimals() = runTest {
        val previousLocale = Locale.getDefault()
        Locale.setDefault(Locale.US)
        try {
            val asset = Asset(
                id = "asset-1",
                currency = "BTC",
                address = "bc1qexample",
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )

            val allocationRepository = mockk<AllocationRepository>()
            val transactionRepository = mockk<TransactionRepository>()
            val assetRepository = mockk<AssetRepository>()
            val onChainBalanceRepository = mockk<OnChainBalanceRepository>()

            coEvery { assetRepository.getAssetById(asset.id) } returns asset
            coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 0.0
            coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns emptyList()
            coEvery { allocationRepository.getAllocationByAssetAndGoal(asset.id, "g1") } returns null
            coEvery { onChainBalanceRepository.getBalance(asset, any()) } returns Result.success(
                OnChainBalance(
                    assetId = asset.id,
                    chainId = asset.chainId!!,
                    address = asset.address!!,
                    currency = asset.currency,
                    balance = 0.004106,
                    fetchedAtMillis = 1L,
                    isStale = true
                )
            )

            val service = AllocationValidationService(
                allocationRepository = allocationRepository,
                transactionRepository = transactionRepository,
                assetRepository = assetRepository,
                onChainBalanceRepository = onChainBalanceRepository
            )

            val message = service.validateAllocation(
                assetId = asset.id,
                goalId = "g1",
                amount = 0.01
            )

            assertThat(message).isNotNull()
            assertThat(message).contains("0.004106")
        } finally {
            Locale.setDefault(previousLocale)
        }
    }
}
