package com.xax.CryptoSavingsTracker.domain.usecase.planning

import android.content.Context
import android.content.SharedPreferences
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
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate

class MonthlyPlanningServiceTest {
    @Test
    fun `flex adjustment fails closed for corrupted non-finite persisted float`() {
        val prefs = mockk<SharedPreferences> {
            every { getFloat("flex_adjustment", 1.0f) } returns Float.NaN
        }
        val context = mockk<Context> {
            every {
                getSharedPreferences("monthly_planning_settings", Context.MODE_PRIVATE)
            } returns prefs
        }
        val planningService = MonthlyPlanningService(
            goalRepository = mockk(relaxed = true),
            allocationRepository = mockk(relaxed = true),
            transactionRepository = mockk(relaxed = true),
            exchangeRateRepository = mockk(relaxed = true),
            assetRepository = mockk(relaxed = true),
            onChainBalanceRepository = mockk(relaxed = true),
            context = context
        )

        assertThat(planningService.flexAdjustment).isEqualTo(1.0)
    }

    @Test
    fun `flex adjustment rejects non-finite value before float persistence`() {
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val prefs = mockk<SharedPreferences> {
            every { edit() } returns editor
        }
        val context = mockk<Context> {
            every {
                getSharedPreferences("monthly_planning_settings", Context.MODE_PRIVATE)
            } returns prefs
        }
        val planningService = MonthlyPlanningService(
            goalRepository = mockk(relaxed = true),
            allocationRepository = mockk(relaxed = true),
            transactionRepository = mockk(relaxed = true),
            exchangeRateRepository = mockk(relaxed = true),
            assetRepository = mockk(relaxed = true),
            onChainBalanceRepository = mockk(relaxed = true),
            context = context
        )

        val failure = runCatching {
            planningService.flexAdjustment = Double.NaN
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        verify(exactly = 0) { editor.putFloat(any(), any()) }
    }

    @Test
    fun `execution snapshot reports stale same-currency on-chain balance as incomplete`() = runTest {
        val snapshot = calculateSnapshot { asset ->
            Result.success(
                OnChainBalance(
                    assetId = asset.id,
                    chainId = asset.chainId!!,
                    address = asset.address!!,
                    currency = asset.currency,
                    balance = 100.0,
                    fetchedAtMillis = 1L,
                    isStale = true
                )
            )
        }

        assertThat(snapshot.isComplete).isFalse()
        assertThat(snapshot.issues.map { it.reason })
            .containsExactly(MonthlyPlanningIssueReason.STALE_ON_CHAIN_BALANCE)
        assertThat(snapshot.requirements.single().currentTotal).isEqualTo(0.0)
    }

    @Test
    fun `execution snapshot reports unavailable same-currency on-chain balance as incomplete`() = runTest {
        val snapshot = calculateSnapshot {
            Result.failure(IllegalStateException("provider unavailable"))
        }

        assertThat(snapshot.isComplete).isFalse()
        assertThat(snapshot.issues.map { it.reason })
            .containsExactly(MonthlyPlanningIssueReason.ON_CHAIN_BALANCE_UNAVAILABLE)
        assertThat(snapshot.requirements.single().currentTotal).isEqualTo(0.0)
    }

    @Test
    fun `execution snapshot reports malformed on-chain identity as incomplete`() = runTest {
        val snapshot = calculateSnapshot { asset ->
            Result.success(
                OnChainBalance(
                    assetId = "wrong-asset",
                    chainId = asset.chainId!!,
                    address = asset.address!!,
                    currency = asset.currency,
                    balance = 100.0,
                    fetchedAtMillis = 1_000L,
                    isStale = false
                )
            )
        }

        assertThat(snapshot.isComplete).isFalse()
        assertThat(snapshot.issues.map { it.reason })
            .containsExactly(MonthlyPlanningIssueReason.INVALID_ON_CHAIN_BALANCE)
    }

    @Test
    fun `display requirements fail instead of publishing stale financial values`() = runTest {
        val failure = runCatching {
            service(balanceResult = { asset ->
                Result.success(
                    OnChainBalance(
                        assetId = asset.id,
                        chainId = asset.chainId!!,
                        address = asset.address!!,
                        currency = asset.currency,
                        balance = 100.0,
                        fetchedAtMillis = 1L,
                        isStale = true
                    )
                )
            }).calculateMonthlyRequirements()
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("stale_on_chain_balance")
        assertThat(failure).hasMessageThat().contains("refresh balances")
    }

    @Test
    fun `currency conversion fails closed when exchange rate is unavailable`() = runTest {
        val rates = mockk<ExchangeRateRepository>()
        coEvery { rates.fetchRate("EUR", "USD") } throws IllegalStateException("provider offline")
        val planningService = service(
            balanceResult = { Result.failure(IllegalStateException("unused")) },
            exchangeRateRepository = rates
        )

        val failure = runCatching {
            planningService.convertAmount(
                amount = 100.0,
                fromCurrency = "EUR",
                toCurrency = "USD"
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("Exchange rate EUR")
        assertThat(failure).hasMessageThat().contains("retry")
    }

    @Test
    fun `currency conversion rejects zero negative NaN and infinite rates`() = runTest {
        listOf(
            0.0,
            -1.0,
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        ).forEach { invalidRate ->
            val rates = mockk<ExchangeRateRepository>()
            coEvery { rates.fetchRate("EUR", "USD") } returns invalidRate
            val planningService = service(
                balanceResult = { Result.failure(IllegalStateException("unused")) },
                exchangeRateRepository = rates
            )

            val failure = runCatching {
                planningService.convertAmount(
                    amount = 100.0,
                    fromCurrency = "EUR",
                    toCurrency = "USD"
                )
            }.exceptionOrNull()

            assertThat(failure).isInstanceOf(IllegalStateException::class.java)
            assertThat(failure).hasMessageThat().contains("unavailable")
        }
    }

    private suspend fun calculateSnapshot(
        balanceResult: (Asset) -> Result<OnChainBalance>
    ): MonthlyPlanningSnapshot = service(balanceResult).calculateExecutionSnapshot()

    private fun service(
        balanceResult: (Asset) -> Result<OnChainBalance>,
        exchangeRateRepository: ExchangeRateRepository = mockk()
    ): MonthlyPlanningService {
        val goal = goal()
        val asset = Asset(
            id = "usd-wallet",
            currency = "USD",
            address = "0x1111111111111111111111111111111111111111",
            chainId = "ethereum",
            createdAt = 1_000L,
            updatedAt = 1_000L
        )
        val allocation = Allocation(
            id = "allocation-1",
            assetId = asset.id,
            goalId = goal.id,
            amount = 100.0,
            createdAt = 1_000L,
            lastModifiedAt = 1_000L
        )
        val goals = mockk<GoalRepository> {
            every { getAllGoals() } returns flowOf(listOf(goal))
        }
        val allocations = mockk<AllocationRepository> {
            coEvery { getAllocationsForGoal(goal.id) } returns listOf(allocation)
            coEvery { getAllocationsForAsset(asset.id) } returns listOf(allocation)
        }
        val assets = mockk<AssetRepository> {
            coEvery { getAssetById(asset.id) } returns asset
        }
        val transactions = mockk<TransactionRepository> {
            every { getAllTransactions() } returns flowOf(emptyList())
        }
        val balances = mockk<OnChainBalanceRepository> {
            coEvery { getBalance(asset, forceRefresh = false) } returns balanceResult(asset)
        }

        return MonthlyPlanningService(
            goalRepository = goals,
            allocationRepository = allocations,
            transactionRepository = transactions,
            exchangeRateRepository = exchangeRateRepository,
            assetRepository = assets,
            onChainBalanceRepository = balances,
            context = planningContext()
        )
    }

    private fun goal() = Goal(
        id = "goal-1",
        name = "USD goal",
        currency = "USD",
        targetAmount = 1_000.0,
        deadline = LocalDate.of(2027, 5, 1),
        startDate = LocalDate.of(2026, 1, 1),
        lifecycleStatus = GoalLifecycleStatus.ACTIVE,
        lifecycleStatusChangedAt = null,
        emoji = null,
        description = null,
        link = null,
        reminderFrequency = null,
        reminderTimeMillis = null,
        firstReminderDate = null,
        createdAt = 1_000L,
        updatedAt = 1_000L
    )

    private fun planningContext(): Context {
        val prefs = mockk<SharedPreferences> {
            every { getInt("payment_day", 1) } returns 1
            every { getInt("MonthlyPlanning.UndoGracePeriodHours", 24) } returns 24
            every { getFloat("flex_adjustment", 1.0f) } returns 1.0f
            every { getString("display_currency", "USD") } returns "USD"
        }
        return mockk {
            every {
                getSharedPreferences("monthly_planning_settings", Context.MODE_PRIVATE)
            } returns prefs
        }
    }
}
