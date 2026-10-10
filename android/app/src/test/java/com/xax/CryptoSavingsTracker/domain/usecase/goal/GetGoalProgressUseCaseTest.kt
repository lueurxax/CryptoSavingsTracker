package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.time.LocalDate
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class GetGoalProgressUseCaseTest {
    @Test
    fun getProgress_convertsAssetCurrencyAndIncludesOnChainBalance() = runTest {
        val goal = Goal(
            id = "g1",
            name = "Goal",
            currency = "USD",
            targetAmount = 1000.0,
            deadline = LocalDate.now().plusDays(10),
            startDate = LocalDate.now(),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 1L
        )

        val asset = Asset(
            id = "a1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        val allocation = Allocation(
            id = "alloc-1",
            assetId = asset.id,
            goalId = goal.id,
            amount = 0.004106,
            createdAt = 1L,
            lastModifiedAt = 1L
        )

        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()

        coEvery { goalRepository.getGoalById(goal.id) } returns goal
        coEvery { allocationRepository.getAllocationsForGoal(goal.id) } returns listOf(allocation)
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 0.0
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { onChainBalanceRepository.getBalance(asset, any()) } returns Result.success(
            OnChainBalance(
                assetId = asset.id,
                chainId = asset.chainId!!,
                address = asset.address!!,
                currency = asset.currency,
                balance = 0.004106,
                fetchedAtMillis = Instant.now().toEpochMilli(),
                isStale = false
            )
        )
        coEvery { exchangeRateRepository.fetchRate("BTC", "USD") } returns 100_000.0

        val useCase = GetGoalProgressUseCase(
            goalRepository = goalRepository,
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            exchangeRateRepository = exchangeRateRepository
        )

        val progress = useCase.getProgress(goal.id)

        assertThat(progress).isNotNull()
        assertThat(progress!!.fundedAmount!!).isWithin(0.0001).of(410.6)
        assertThat(progress.allocatedAmount!!).isWithin(0.0001).of(410.6)
        assertThat(progress.progressPercent).isEqualTo(41)
    }

    @Test
    fun getProgress_marksFinancialProgressUnavailableWhenAddressedBalanceFails() = runTest {
        val goal = Goal(
            id = "g1",
            name = "Goal",
            currency = "USD",
            targetAmount = 1_000.0,
            deadline = LocalDate.now().plusDays(10),
            startDate = LocalDate.now(),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 1L
        )
        val asset = Asset(
            id = "a1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        val allocation = Allocation(
            id = "alloc-1",
            assetId = asset.id,
            goalId = goal.id,
            amount = 1.0,
            createdAt = 1L,
            lastModifiedAt = 1L
        )
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val onChainBalanceRepository = mockk<OnChainBalanceRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()

        coEvery { goalRepository.getGoalById(goal.id) } returns goal
        coEvery { allocationRepository.getAllocationsForGoal(goal.id) } returns listOf(allocation)
        coEvery { allocationRepository.getAllocationsForAsset(asset.id) } returns listOf(allocation)
        coEvery { transactionRepository.getManualBalanceForAsset(asset.id) } returns 5.0
        coEvery { assetRepository.getAssetById(asset.id) } returns asset
        coEvery { onChainBalanceRepository.getBalance(asset, any()) } returns
            Result.failure(IllegalStateException("provider offline"))
        coEvery { exchangeRateRepository.fetchRate("BTC", "USD") } returns 100_000.0

        val progress = GetGoalProgressUseCase(
            goalRepository = goalRepository,
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = onChainBalanceRepository,
            exchangeRateRepository = exchangeRateRepository
        ).getProgress(goal.id)

        assertThat(progress).isNotNull()
        assertThat(progress!!.fundedAmount).isNull()
        assertThat(progress.progress).isNull()
        assertThat(progress.progressPercent).isNull()
        assertThat(progress.financialDataIssue).contains("On-chain balance for BTC")
    }

    @Test
    fun getProgress_doesNotPublishPartialTotalsWhenOneRequiredExchangeRateIsMissing() = runTest {
        val goal = Goal(
            id = "g1",
            name = "Goal",
            currency = "USD",
            targetAmount = 1_000.0,
            deadline = LocalDate.now().plusDays(10),
            startDate = LocalDate.now(),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 1L
        )
        val usd = Asset("usd", "USD", null, null, 1L, 1L)
        val btc = Asset("btc", "BTC", null, "bitcoin", 1L, 1L)
        val usdAllocation = Allocation("usd-a", usd.id, goal.id, 100.0, 1L, 1L)
        val btcAllocation = Allocation("btc-a", btc.id, goal.id, 1.0, 1L, 1L)
        val goalRepository = mockk<GoalRepository>()
        val allocationRepository = mockk<AllocationRepository>()
        val transactionRepository = mockk<TransactionRepository>()
        val assetRepository = mockk<AssetRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()

        coEvery { goalRepository.getGoalById(goal.id) } returns goal
        coEvery { allocationRepository.getAllocationsForGoal(goal.id) } returns
            listOf(usdAllocation, btcAllocation)
        coEvery { allocationRepository.getAllocationsForAsset(usd.id) } returns listOf(usdAllocation)
        coEvery { allocationRepository.getAllocationsForAsset(btc.id) } returns listOf(btcAllocation)
        coEvery { transactionRepository.getManualBalanceForAsset(usd.id) } returns 100.0
        coEvery { transactionRepository.getManualBalanceForAsset(btc.id) } returns 1.0
        coEvery { assetRepository.getAssetById(usd.id) } returns usd
        coEvery { assetRepository.getAssetById(btc.id) } returns btc
        coEvery { exchangeRateRepository.fetchRate("BTC", "USD") } throws
            IllegalStateException("rate offline")

        val progress = GetGoalProgressUseCase(
            goalRepository = goalRepository,
            allocationRepository = allocationRepository,
            transactionRepository = transactionRepository,
            assetRepository = assetRepository,
            onChainBalanceRepository = mockk(relaxed = true),
            exchangeRateRepository = exchangeRateRepository
        ).getProgress(goal.id)

        assertThat(progress).isNotNull()
        assertThat(progress!!.allocatedAmount).isNull()
        assertThat(progress.fundedAmount).isNull()
        assertThat(progress.progress).isNull()
        assertThat(progress.financialDataIssue).contains("Exchange rate BTC")
    }
}
