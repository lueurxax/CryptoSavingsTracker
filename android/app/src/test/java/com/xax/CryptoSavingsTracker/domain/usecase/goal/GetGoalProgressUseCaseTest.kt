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
                fetchedAtMillis = 1L,
                isStale = true
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
        assertThat(progress!!.fundedAmount).isWithin(0.0001).of(410.6)
        assertThat(progress.allocatedAmount).isWithin(0.0001).of(410.6)
        assertThat(progress.progressPercent).isEqualTo(41)
    }
}

