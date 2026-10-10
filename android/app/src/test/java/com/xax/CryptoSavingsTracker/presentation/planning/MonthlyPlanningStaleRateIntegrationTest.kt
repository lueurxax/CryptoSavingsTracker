package com.xax.CryptoSavingsTracker.presentation.planning

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.CoinGeckoApi
import com.xax.CryptoSavingsTracker.data.repository.ExchangeRateRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.BudgetCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.io.IOException
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MonthlyPlanningStaleRateIntegrationTest {
    @Test
    fun `expired repository fallback cannot be synchronized into a monthly plan`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val asset = Asset(
                    id = "btc-manual",
                    currency = "BTC",
                    address = null,
                    chainId = null,
                    createdAt = 1_000L,
                    updatedAt = 1_000L
                )
                val allocation = Allocation(
                    id = "allocation-1",
                    assetId = asset.id,
                    goalId = goal.id,
                    amount = 1.0,
                    createdAt = 1_000L,
                    lastModifiedAt = 1_000L
                )
                val transaction = Transaction(
                    id = "transaction-1",
                    assetId = asset.id,
                    amount = 1.0,
                    dateMillis = 1_000L,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = 1_000L
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
                    every { getAllTransactions() } returns flowOf(listOf(transaction))
                }
                val rateRepository = expiredOfflineRateRepository()
                val planningService = MonthlyPlanningService(
                    goalRepository = goals,
                    allocationRepository = allocations,
                    transactionRepository = transactions,
                    exchangeRateRepository = rateRepository,
                    assetRepository = assets,
                    onChainBalanceRepository = mockk<OnChainBalanceRepository>(relaxed = true),
                    context = planningContext()
                )
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                coEvery { goalPlanService.syncPlans(any(), any()) } returns emptyList()
                val executionSession = mockk<GetExecutionSessionUseCase> {
                    every { currentExecuting() } returns flowOf(null)
                }
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true) {
                    every { monthlyBudget } returns null
                    every { budgetCurrency } returns "USD"
                    every { budgetAppliedMonthLabel } returns null
                }

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = mockk<BudgetCalculatorUseCase>(relaxed = true),
                    goalRepository = goals
                )
                advanceUntilIdle()

                coVerify(exactly = 0) {
                    goalPlanService.syncPlans(any(), any())
                }
                assertThat(viewModel.uiState.value.error).contains("exchange_rate_unavailable")
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    private fun expiredOfflineRateRepository(): ExchangeRateRepositoryImpl {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } throws IOException("offline")
        val oldTimestamp = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1_000
        val prefs = mockk<SharedPreferences>()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val context = mockk<Context> {
            every {
                getSharedPreferences("exchange_rate_cache", Context.MODE_PRIVATE)
            } returns prefs
        }
        every { prefs.getString("cached_rates", null) } returns
            """{"BTC":{"USD":123.0}}"""
        every { prefs.getString("cached_times", null) } returns
            """{"BTC-USD":$oldTimestamp}"""
        every { prefs.edit() } returns editor
        every { editor.putString(any(), any()) } returns editor

        return ExchangeRateRepositoryImpl(
            coinGeckoApi = api,
            rateLimiter = TokenBucketRateLimiter(
                maxTokens = 100.0,
                refillTokensPerSecond = 100.0
            ),
            apiKeyStore = mockk<ApiKeyStore>(relaxed = true),
            context = context
        )
    }

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

    private fun goal() = Goal(
        id = "goal-1",
        name = "USD goal",
        currency = "USD",
        targetAmount = 1_000.0,
        deadline = LocalDate.now().plusMonths(12),
        startDate = LocalDate.now(),
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
}
