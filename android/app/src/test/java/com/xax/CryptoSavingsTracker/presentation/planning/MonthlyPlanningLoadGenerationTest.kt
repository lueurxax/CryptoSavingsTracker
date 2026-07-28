package com.xax.CryptoSavingsTracker.presentation.planning

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.BudgetCalculatorPlan
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalContribution
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.BudgetCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlin.coroutines.Continuation
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MonthlyPlanningLoadGenerationTest {
    @Test
    fun `stale load already inside plan sync cannot overwrite a newer durable plan`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val staleRequirement = requirement(goal, requiredMonthly = 28.0)
                val freshRequirement = requirement(goal, requiredMonthly = 5.0)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>(relaxed = true)
                val goals = mockk<GoalRepository>()
                var paymentDay = 28
                var requirementCall = 0
                var staleSyncContinuation: Continuation<Unit>? = null
                var durableRequiredMonthly: Double? = null

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.paymentDay } answers { paymentDay }
                every { planningService.paymentDay = any() } answers {
                    paymentDay = firstArg()
                }
                every { planningService.displayCurrency } returns "USD"
                every { planningService.displayCurrency = any() } returns Unit
                every { planningService.flexAdjustment } returns 1.0
                coEvery { planningService.calculateMonthlyRequirements() } answers {
                    requirementCall += 1
                    if (requirementCall == 1) {
                        listOf(staleRequirement)
                    } else {
                        listOf(freshRequirement)
                    }
                }
                coEvery {
                    planningService.convertAmount(any(), any(), any())
                } answers { firstArg() }
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), any()) } coAnswers {
                    val syncedRequirement = secondArg<List<MonthlyRequirement>>().single()
                    if (syncedRequirement.requiredMonthly == 28.0) {
                        suspendCoroutine<Unit> { continuation ->
                            staleSyncContinuation = continuation
                        }
                    }
                    durableRequiredMonthly = syncedRequirement.requiredMonthly
                    listOf(monthlyPlan(syncedRequirement))
                }
                every { settings.monthlyBudget } returns null
                every { settings.budgetCurrency } returns "USD"
                every { settings.budgetAppliedMonthLabel } returns null

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = budgetCalculator,
                    goalRepository = goals
                )
                runCurrent()
                assertThat(staleSyncContinuation).isNotNull()

                viewModel.updatePlanningSettings(
                    day = 5,
                    displayCurrency = "USD",
                    budgetAmount = null,
                    budgetCurrency = "USD"
                )
                runCurrent()

                checkNotNull(staleSyncContinuation).resumeWith(Result.success(Unit))
                advanceUntilIdle()

                assertThat(durableRequiredMonthly).isEqualTo(5.0)
                assertThat(viewModel.uiState.value.paymentDay).isEqualTo(5)
                assertThat(viewModel.uiState.value.requirements.single().adjustedRequiredMonthly)
                    .isEqualTo(5.0)
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `plan mutation waits for active sync and stale refresh cannot overwrite it`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val requirement = requirement(goal, requiredMonthly = 10.0)
                val basePlan = monthlyPlan(requirement)
                val protectedPlan = basePlan.copy(isProtected = true)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>(relaxed = true)
                val goals = mockk<GoalRepository>()
                var syncCalls = 0
                var protectedMutationCalls = 0
                var staleSyncContinuation: Continuation<Unit>? = null

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.paymentDay } returns 1
                every { planningService.displayCurrency } returns "USD"
                every { planningService.flexAdjustment } returns 1.0
                coEvery { planningService.calculateMonthlyRequirements() } returns
                    listOf(requirement)
                coEvery {
                    planningService.convertAmount(any(), any(), any())
                } answers { firstArg() }
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), any()) } coAnswers {
                    syncCalls += 1
                    if (syncCalls == 2) {
                        suspendCoroutine<Unit> { continuation ->
                            staleSyncContinuation = continuation
                        }
                    }
                    listOf(basePlan)
                }
                coEvery { goalPlanService.toggleProtected(any(), goal.id) } coAnswers {
                    protectedMutationCalls += 1
                    protectedPlan
                }
                every { settings.monthlyBudget } returns null
                every { settings.budgetCurrency } returns "USD"
                every { settings.budgetAppliedMonthLabel } returns null

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = budgetCalculator,
                    goalRepository = goals
                )
                advanceUntilIdle()
                assertThat(viewModel.uiState.value.requirements.single().isProtected).isFalse()

                viewModel.loadData()
                runCurrent()
                assertThat(staleSyncContinuation).isNotNull()

                viewModel.toggleProtected(goal.id)
                runCurrent()

                assertThat(protectedMutationCalls).isEqualTo(0)

                checkNotNull(staleSyncContinuation).resumeWith(Result.success(Unit))
                advanceUntilIdle()

                assertThat(protectedMutationCalls).isEqualTo(1)
                assertThat(viewModel.uiState.value.requirements.single().isProtected).isTrue()
                assertThat(viewModel.uiState.value.isLoading).isFalse()
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `stale load already inside budget migration cannot overwrite a newer budget`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val requirement = requirement(goal, requiredMonthly = 10.0)
                val basePlan = monthlyPlan(requirement)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val goals = mockk<GoalRepository>()
                var monthlyBudget: Double? = 100.0
                var budgetCurrency = "USD"
                var appliedMonthLabel: String? = null
                var appliedSignature: String? = null
                var staleMigrationContinuation: Continuation<BudgetCalculatorPlan>? = null
                val durableCustomAmounts = mutableListOf<Double>()

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.paymentDay } returns 1
                every { planningService.paymentDay = any() } returns Unit
                every { planningService.displayCurrency } returns "USD"
                every { planningService.displayCurrency = any() } returns Unit
                every { planningService.flexAdjustment } returns 1.0
                every { planningService.flexAdjustment = any() } returns Unit
                coEvery { planningService.calculateMonthlyRequirements() } returns
                    listOf(requirement)
                coEvery {
                    planningService.convertAmount(any(), any(), any())
                } answers { firstArg() }
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), any()) } returns listOf(basePlan)
                coEvery { goalPlanService.applyCustomAmounts(any(), any()) } coAnswers {
                    val amount = secondArg<Map<String, Double>>().getValue(goal.id)
                    durableCustomAmounts += amount
                    listOf(basePlan.copy(customAmount = amount))
                }
                every { settings.monthlyBudget } answers { monthlyBudget }
                every { settings.monthlyBudget = any() } answers {
                    monthlyBudget = firstArg()
                }
                every { settings.budgetCurrency } answers { budgetCurrency }
                every { settings.budgetCurrency = any() } answers {
                    budgetCurrency = firstArg()
                }
                every { settings.budgetAppliedMonthLabel } answers { appliedMonthLabel }
                every { settings.budgetAppliedMonthLabel = any() } answers {
                    appliedMonthLabel = firstArg()
                }
                every { settings.budgetAppliedSignature } answers { appliedSignature }
                every { settings.budgetAppliedSignature = any() } answers {
                    appliedSignature = firstArg()
                }
                every { settings.hasSeenBudgetMigrationNotice } returns true
                coEvery {
                    budgetCalculator.checkFeasibility(listOf(goal), any(), "USD")
                } answers {
                    val amount = secondArg<Double>()
                    FeasibilityResult(
                        isFeasible = true,
                        minimumRequired = amount,
                        currency = "USD",
                        infeasibleGoals = emptyList(),
                        suggestions = emptyList()
                    )
                }
                coEvery {
                    budgetCalculator.generateSchedule(listOf(goal), any(), "USD")
                } coAnswers {
                    val amount = secondArg<Double>()
                    if (amount == 100.0) {
                        suspendCoroutine { continuation ->
                            staleMigrationContinuation = continuation
                        }
                    } else {
                        budgetPlan(goal, amount)
                    }
                }

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = budgetCalculator,
                    goalRepository = goals
                )
                runCurrent()
                assertThat(staleMigrationContinuation).isNotNull()

                viewModel.updatePlanningSettings(
                    day = 1,
                    displayCurrency = "USD",
                    budgetAmount = 200.0,
                    budgetCurrency = "USD"
                )
                runCurrent()

                checkNotNull(staleMigrationContinuation).resumeWith(
                    Result.success(budgetPlan(goal, 100.0))
                )
                advanceUntilIdle()

                assertThat(durableCustomAmounts).containsExactly(200.0)
                assertThat(monthlyBudget).isEqualTo(200.0)
                assertThat(viewModel.uiState.value.budgetAmount).isEqualTo(200.0)
                assertThat(viewModel.uiState.value.isBudgetAppliedForMonth).isTrue()
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `payment day 28 load cannot sync or publish after day 5 load completes`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val staleRequirement = requirement(goal, requiredMonthly = 28.0)
                val freshRequirement = requirement(goal, requiredMonthly = 5.0)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>(relaxed = true)
                val goals = mockk<GoalRepository>()
                var paymentDay = 28
                var displayCurrency = "USD"
                var requirementCall = 0
                var staleContinuation: Continuation<List<MonthlyRequirement>>? = null
                val syncedRequiredMonthlies = mutableListOf<Double>()

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.paymentDay } answers { paymentDay }
                every { planningService.paymentDay = any() } answers {
                    paymentDay = firstArg()
                }
                every { planningService.displayCurrency } answers { displayCurrency }
                every { planningService.displayCurrency = any() } answers {
                    displayCurrency = firstArg()
                }
                every { planningService.flexAdjustment } returns 1.0
                coEvery { planningService.calculateMonthlyRequirements() } coAnswers {
                    requirementCall += 1
                    if (requirementCall == 1) {
                        suspendCoroutine { continuation ->
                            staleContinuation = continuation
                        }
                    } else {
                        listOf(freshRequirement)
                    }
                }
                coEvery {
                    planningService.convertAmount(any(), any(), any())
                } answers { firstArg() }
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), any()) } coAnswers {
                    val requirements = secondArg<List<MonthlyRequirement>>()
                    syncedRequiredMonthlies += requirements.single().requiredMonthly
                    listOf(monthlyPlan(requirements.single()))
                }
                every { settings.monthlyBudget } returns null
                every { settings.budgetCurrency } returns "USD"
                every { settings.budgetAppliedMonthLabel } returns null

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = budgetCalculator,
                    goalRepository = goals
                )
                runCurrent()
                assertThat(staleContinuation).isNotNull()

                viewModel.updatePlanningSettings(
                    day = 5,
                    displayCurrency = "USD",
                    budgetAmount = null,
                    budgetCurrency = "USD"
                )
                runCurrent()

                assertThat(syncedRequiredMonthlies).containsExactly(5.0)
                assertThat(viewModel.uiState.value.paymentDay).isEqualTo(5)
                assertThat(viewModel.uiState.value.requirements.single().adjustedRequiredMonthly)
                    .isEqualTo(5.0)

                checkNotNull(staleContinuation).resumeWith(Result.success(listOf(staleRequirement)))
                advanceUntilIdle()

                assertThat(syncedRequiredMonthlies).containsExactly(5.0)
                assertThat(viewModel.uiState.value.paymentDay).isEqualTo(5)
                assertThat(viewModel.uiState.value.requirements.single().adjustedRequiredMonthly)
                    .isEqualTo(5.0)
                assertThat(viewModel.uiState.value.isLoading).isFalse()
                assertThat(viewModel.uiState.value.error).isNull()
                assertThat(viewModel.uiState.value.budgetFeasibility)
                    .isEqualTo(FeasibilityResult.EMPTY)
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    private fun goal() = Goal(
        id = "goal-1",
        name = "Goal",
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
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun requirement(
        goal: Goal,
        requiredMonthly: Double
    ) = MonthlyRequirement(
        id = "requirement-$requiredMonthly",
        goalId = goal.id,
        goalName = goal.name,
        currency = goal.currency,
        targetAmount = goal.targetAmount,
        currentTotal = 0.0,
        remainingAmount = goal.targetAmount,
        monthsRemaining = 12,
        requiredMonthly = requiredMonthly,
        progress = 0.0,
        deadline = goal.deadline,
        status = RequirementStatus.ON_TRACK
    )

    private fun monthlyPlan(requirement: MonthlyRequirement) = MonthlyGoalPlan(
        id = "monthly-plan-${requirement.requiredMonthly}",
        goalId = requirement.goalId,
        monthLabel = "2026-07",
        requiredMonthly = requirement.requiredMonthly,
        remainingAmount = requirement.remainingAmount,
        monthsRemaining = requirement.monthsRemaining,
        currency = requirement.currency,
        status = requirement.status,
        state = MonthlyGoalPlanState.DRAFT,
        customAmount = null,
        isProtected = false,
        isSkipped = false,
        createdAtUtcMillis = 1L,
        lastModifiedAtUtcMillis = 1L
    )

    private fun budgetPlan(goal: Goal, amount: Double) = BudgetCalculatorPlan(
        monthlyBudget = amount,
        currency = "USD",
        schedule = listOf(
            ScheduledPayment(
                paymentDate = LocalDate.now(),
                paymentNumber = 1,
                contributions = listOf(
                    GoalContribution(
                        goalId = goal.id,
                        goalName = goal.name,
                        amount = amount,
                        runningTotal = amount
                    )
                )
            )
        ),
        isLeveled = false,
        minimumRequired = amount
    )
}
