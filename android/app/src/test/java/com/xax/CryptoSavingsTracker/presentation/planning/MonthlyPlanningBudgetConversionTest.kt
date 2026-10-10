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
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
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
import kotlin.coroutines.Continuation
import kotlin.coroutines.suspendCoroutine

@OptIn(ExperimentalCoroutinesApi::class)
class MonthlyPlanningBudgetConversionTest {
    @Test
    fun `budget apply keeps plan unmodified and exposes retry error when conversion fails`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal()
                val requirement = requirement(goal)
                val monthlyPlan = monthlyPlan(goal, requirement)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val goals = mockk<GoalRepository>()

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.displayCurrency } returns "USD"
                coEvery { planningService.calculateMonthlyRequirements() } returns listOf(requirement)
                coEvery {
                    planningService.convertAmount(any(), "USD", "USD")
                } answers { firstArg<Double>() }
                every { planningService.paymentDay } returns 1
                every { planningService.flexAdjustment } returns 1.0
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), listOf(requirement)) } returns
                    listOf(monthlyPlan)
                every { settings.monthlyBudget } returns null
                every { settings.budgetCurrency } returns "USD"
                every { settings.budgetAppliedMonthLabel } returns null

                val budgetPlan = BudgetCalculatorPlan(
                    monthlyBudget = 100.0,
                    currency = "EUR",
                    schedule = listOf(
                        ScheduledPayment(
                            paymentDate = LocalDate.now(),
                            paymentNumber = 1,
                            contributions = listOf(
                                GoalContribution(
                                    goalId = goal.id,
                                    goalName = goal.name,
                                    amount = 100.0,
                                    runningTotal = 100.0
                                )
                            )
                        )
                    ),
                    isLeveled = false,
                    minimumRequired = 100.0
                )
                coEvery {
                    budgetCalculator.checkFeasibility(listOf(goal), 100.0, "EUR")
                } returns FeasibilityResult(
                    isFeasible = true,
                    minimumRequired = 100.0,
                    currency = "EUR",
                    infeasibleGoals = emptyList(),
                    suggestions = emptyList()
                )
                coEvery {
                    budgetCalculator.generateSchedule(listOf(goal), 100.0, "EUR")
                } returns budgetPlan
                coEvery {
                    planningService.convertAmount(100.0, "EUR", "USD")
                } throws IllegalStateException(
                    "Exchange rate EUR → USD is unavailable; refresh rates and retry"
                )

                val viewModel = MonthlyPlanningViewModel(
                    monthlyPlanningService = planningService,
                    monthlyGoalPlanService = goalPlanService,
                    getExecutionSessionUseCase = executionSession,
                    settings = settings,
                    budgetCalculatorUseCase = budgetCalculator,
                    goalRepository = goals
                )
                advanceUntilIdle()

                viewModel.applyBudgetPlan(amount = 100.0, currency = "EUR")
                advanceUntilIdle()

                assertThat(viewModel.uiState.value.isBudgetAppliedForMonth).isFalse()
                assertThat(viewModel.uiState.value.error).contains("retry")
                coVerify(exactly = 0) {
                    goalPlanService.applyCustomAmounts(any(), any())
                }
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `persisted plan edit clears stale total and exposes retry error when refresh conversion fails`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val goal = goal().copy(currency = "EUR")
                val requirement = requirement(goal)
                val monthlyPlan = monthlyPlan(goal, requirement)
                val protectedPlan = monthlyPlan.copy(isProtected = true)
                val planningService = mockk<MonthlyPlanningService>(relaxed = true)
                val goalPlanService = mockk<MonthlyGoalPlanService>()
                val executionSession = mockk<GetExecutionSessionUseCase>()
                val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val goals = mockk<GoalRepository>()
                var successfulConversionsRemaining = 2

                every { executionSession.currentExecuting() } returns flowOf(null)
                every { planningService.displayCurrency } returns "USD"
                coEvery { planningService.calculateMonthlyRequirements() } returns listOf(requirement)
                coEvery {
                    planningService.convertAmount(100.0, "EUR", "USD")
                } answers {
                    if (successfulConversionsRemaining > 0) {
                        successfulConversionsRemaining -= 1
                        200.0
                    } else {
                        throw IllegalStateException(
                            "Exchange rate EUR → USD is unavailable; refresh rates and retry"
                        )
                    }
                }
                every { planningService.paymentDay } returns 1
                every { planningService.flexAdjustment } returns 1.0
                every { goals.getAllGoals() } returns flowOf(listOf(goal))
                coEvery { goalPlanService.syncPlans(any(), listOf(requirement)) } returns
                    listOf(monthlyPlan)
                coEvery { goalPlanService.toggleProtected(any(), goal.id) } returns protectedPlan
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
                assertThat(viewModel.uiState.value.totalRequired).isEqualTo(200.0)

                viewModel.toggleProtected(goal.id)
                advanceUntilIdle()

                coVerify(exactly = 1) {
                    goalPlanService.toggleProtected(any(), goal.id)
                }
                assertThat(viewModel.uiState.value.requirements.single().isProtected).isTrue()
                assertThat(viewModel.uiState.value.totalRequired).isNull()
                assertThat(viewModel.uiState.value.error).contains("retry")
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `budget preview failure clears loading and publishes preview error`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                coEvery {
                    budgetCalculator.checkFeasibility(any(), 100.0, "EUR")
                } throws IllegalStateException("Exchange rate is invalid")
                val fixture = viewModelFixture(budgetCalculator)
                advanceUntilIdle()

                fixture.viewModel.previewBudget(amount = 100.0, currency = "EUR")
                advanceUntilIdle()

                assertThat(fixture.viewModel.uiState.value.isBudgetPreviewLoading).isFalse()
                assertThat(fixture.viewModel.uiState.value.budgetPreviewPlan).isNull()
                assertThat(fixture.viewModel.uiState.value.budgetPreviewTimeline).isEmpty()
                assertThat(fixture.viewModel.uiState.value.budgetPreviewError)
                    .contains("invalid")
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `budget minimum failure clears loading and publishes settings error`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                coEvery {
                    budgetCalculator.calculateMinimumBudget(any(), "EUR")
                } throws IllegalStateException("Minimum exchange rate is unavailable")
                val fixture = viewModelFixture(budgetCalculator)
                advanceUntilIdle()

                fixture.viewModel.loadBudgetMinimum("EUR")
                advanceUntilIdle()

                assertThat(fixture.viewModel.uiState.value.isBudgetMinimumLoading).isFalse()
                assertThat(fixture.viewModel.uiState.value.budgetMinimum).isNull()
                assertThat(fixture.viewModel.uiState.value.budgetMinimumError)
                    .contains("unavailable")
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `delayed EUR minimum cannot replace newer USD minimum`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val minimumContinuations = mutableMapOf<String, Continuation<Double>>()
                coEvery {
                    budgetCalculator.calculateMinimumBudget(any(), any())
                } coAnswers {
                    val currency = secondArg<String>()
                    suspendCoroutine { continuation ->
                        minimumContinuations[currency] = continuation
                    }
                }
                val fixture = viewModelFixture(budgetCalculator)
                advanceUntilIdle()

                fixture.viewModel.loadBudgetMinimum("EUR")
                runCurrent()
                fixture.viewModel.loadBudgetMinimum("USD")
                runCurrent()

                minimumContinuations.getValue("USD").resumeWith(Result.success(200.0))
                runCurrent()
                assertThat(fixture.viewModel.uiState.value.budgetMinimum).isEqualTo(200.0)
                assertThat(fixture.viewModel.uiState.value.isBudgetMinimumLoading).isFalse()
                assertThat(fixture.viewModel.uiState.value.budgetMinimumError).isNull()

                minimumContinuations.getValue("EUR").resumeWith(Result.success(100.0))
                advanceUntilIdle()

                assertThat(fixture.viewModel.uiState.value.budgetMinimum).isEqualTo(200.0)
                assertThat(fixture.viewModel.uiState.value.isBudgetMinimumLoading).isFalse()
                assertThat(fixture.viewModel.uiState.value.budgetMinimumError).isNull()
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `older non cooperative preview failure cannot replace newer successful preview`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val feasibilityContinuations =
                    mutableMapOf<Double, Continuation<FeasibilityResult>>()
                val newerFeasibility = FeasibilityResult(
                    isFeasible = true,
                    minimumRequired = 150.0,
                    currency = "USD",
                    infeasibleGoals = emptyList(),
                    suggestions = emptyList()
                )
                val newerPlan = budgetPlan(amount = 200.0, currency = "USD")
                coEvery {
                    budgetCalculator.checkFeasibility(any(), any(), "USD")
                } coAnswers {
                    val amount = secondArg<Double>()
                    suspendCoroutine { continuation ->
                        feasibilityContinuations[amount] = continuation
                    }
                }
                coEvery {
                    budgetCalculator.generateSchedule(any(), 200.0, "USD")
                } returns newerPlan
                every {
                    budgetCalculator.buildTimelineBlocks(newerPlan, any())
                } returns emptyList()
                val fixture = viewModelFixture(budgetCalculator)
                advanceUntilIdle()

                fixture.viewModel.previewBudget(amount = 100.0, currency = "USD")
                runCurrent()
                fixture.viewModel.previewBudget(amount = 200.0, currency = "USD")
                runCurrent()

                feasibilityContinuations.getValue(200.0).resumeWith(
                    Result.success(newerFeasibility)
                )
                runCurrent()
                val stateAfterNewerSuccess = fixture.viewModel.uiState.value
                assertThat(stateAfterNewerSuccess.budgetFeasibility)
                    .isEqualTo(newerFeasibility)
                assertThat(stateAfterNewerSuccess.budgetPreviewPlan).isEqualTo(newerPlan)
                assertThat(stateAfterNewerSuccess.isBudgetPreviewLoading).isFalse()
                assertThat(stateAfterNewerSuccess.budgetPreviewError).isNull()

                feasibilityContinuations.getValue(100.0).resumeWith(
                    Result.failure(IllegalStateException("stale preview failure"))
                )
                advanceUntilIdle()

                val finalState = fixture.viewModel.uiState.value
                assertThat(finalState.budgetFeasibility).isEqualTo(newerFeasibility)
                assertThat(finalState.budgetPreviewPlan).isEqualTo(newerPlan)
                assertThat(finalState.isBudgetPreviewLoading).isFalse()
                assertThat(finalState.budgetPreviewError).isNull()
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `apply rechecks feasibility and does not persist an infeasible budget`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val infeasible = FeasibilityResult(
                    isFeasible = false,
                    minimumRequired = 150.0,
                    currency = "USD",
                    infeasibleGoals = emptyList(),
                    suggestions = emptyList()
                )
                val generatedPlan = budgetPlan(amount = 100.0, currency = "USD")
                coEvery {
                    budgetCalculator.checkFeasibility(any(), 100.0, "USD")
                } returns infeasible
                coEvery {
                    budgetCalculator.generateSchedule(any(), 100.0, "USD")
                } returns generatedPlan
                val fixture = viewModelFixture(budgetCalculator)
                coEvery {
                    fixture.goalPlanService.applyCustomAmounts(any(), any())
                } returns emptyList()
                advanceUntilIdle()

                fixture.viewModel.applyBudgetPlan(amount = 100.0, currency = "USD")
                advanceUntilIdle()

                assertThat(fixture.viewModel.uiState.value.budgetFeasibility)
                    .isEqualTo(infeasible)
                assertThat(fixture.viewModel.uiState.value.isBudgetAppliedForMonth).isFalse()
                assertThat(fixture.viewModel.uiState.value.error).contains("feasible")
                coVerify(exactly = 0) {
                    fixture.goalPlanService.applyCustomAmounts(any(), any())
                }
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `positive budget contribution cannot persist a zero converted custom amount`() {
        val scheduler = TestCoroutineScheduler()
        val dispatcher = StandardTestDispatcher(scheduler)
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val budgetCalculator = mockk<BudgetCalculatorUseCase>()
                val budgetPlan = BudgetCalculatorPlan(
                    monthlyBudget = 100.0,
                    currency = "EUR",
                    schedule = listOf(
                        ScheduledPayment(
                            paymentDate = LocalDate.now(),
                            paymentNumber = 1,
                            contributions = listOf(
                                GoalContribution(
                                    goalId = "goal-1",
                                    goalName = "Goal",
                                    amount = 100.0,
                                    runningTotal = 100.0
                                )
                            )
                        )
                    ),
                    isLeveled = false,
                    minimumRequired = 100.0
                )
                coEvery {
                    budgetCalculator.checkFeasibility(any(), 100.0, "EUR")
                } returns FeasibilityResult(
                    isFeasible = true,
                    minimumRequired = 100.0,
                    currency = "EUR",
                    infeasibleGoals = emptyList(),
                    suggestions = emptyList()
                )
                coEvery {
                    budgetCalculator.generateSchedule(any(), 100.0, "EUR")
                } returns budgetPlan
                val fixture = viewModelFixture(budgetCalculator)
                coEvery {
                    fixture.planningService.convertAmount(100.0, "EUR", "USD")
                } returns 0.0
                advanceUntilIdle()

                fixture.viewModel.applyBudgetPlan(amount = 100.0, currency = "EUR")
                advanceUntilIdle()

                assertThat(fixture.viewModel.uiState.value.isBudgetAppliedForMonth).isFalse()
                assertThat(fixture.viewModel.uiState.value.error).contains("invalid")
                coVerify(exactly = 0) {
                    fixture.goalPlanService.applyCustomAmounts(any(), any())
                }
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    private data class ViewModelFixture(
        val viewModel: MonthlyPlanningViewModel,
        val planningService: MonthlyPlanningService,
        val goalPlanService: MonthlyGoalPlanService
    )

    private fun viewModelFixture(
        budgetCalculator: BudgetCalculatorUseCase
    ): ViewModelFixture {
        val goal = goal()
        val requirement = requirement(goal)
        val monthlyPlan = monthlyPlan(goal, requirement)
        val planningService = mockk<MonthlyPlanningService>(relaxed = true)
        val goalPlanService = mockk<MonthlyGoalPlanService>()
        val executionSession = mockk<GetExecutionSessionUseCase>()
        val settings = mockk<MonthlyPlanningSettings>(relaxed = true)
        val goals = mockk<GoalRepository>()

        every { executionSession.currentExecuting() } returns flowOf(null)
        every { planningService.displayCurrency } returns "USD"
        coEvery { planningService.calculateMonthlyRequirements() } returns listOf(requirement)
        coEvery {
            planningService.convertAmount(any(), any(), any())
        } answers { firstArg<Double>() }
        every { planningService.paymentDay } returns 1
        every { planningService.flexAdjustment } returns 1.0
        every { goals.getAllGoals() } returns flowOf(listOf(goal))
        coEvery { goalPlanService.syncPlans(any(), listOf(requirement)) } returns
            listOf(monthlyPlan)
        every { settings.monthlyBudget } returns null
        every { settings.budgetCurrency } returns "USD"
        every { settings.budgetAppliedMonthLabel } returns null

        return ViewModelFixture(
            viewModel = MonthlyPlanningViewModel(
                monthlyPlanningService = planningService,
                monthlyGoalPlanService = goalPlanService,
                getExecutionSessionUseCase = executionSession,
                settings = settings,
                budgetCalculatorUseCase = budgetCalculator,
                goalRepository = goals
            ),
            planningService = planningService,
            goalPlanService = goalPlanService
        )
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

    private fun requirement(goal: Goal) = MonthlyRequirement(
        id = "requirement-1",
        goalId = goal.id,
        goalName = goal.name,
        currency = goal.currency,
        targetAmount = goal.targetAmount,
        currentTotal = 0.0,
        remainingAmount = goal.targetAmount,
        monthsRemaining = 12,
        requiredMonthly = 100.0,
        progress = 0.0,
        deadline = goal.deadline,
        status = RequirementStatus.ON_TRACK
    )

    private fun monthlyPlan(goal: Goal, requirement: MonthlyRequirement) = MonthlyGoalPlan(
        id = "monthly-plan-1",
        goalId = goal.id,
        monthLabel = "2026-07",
        requiredMonthly = requirement.requiredMonthly,
        remainingAmount = requirement.remainingAmount,
        monthsRemaining = requirement.monthsRemaining,
        currency = goal.currency,
        status = RequirementStatus.ON_TRACK,
        state = MonthlyGoalPlanState.DRAFT,
        customAmount = null,
        isProtected = false,
        isSkipped = false,
        createdAtUtcMillis = 1L,
        lastModifiedAtUtcMillis = 1L
    )

    private fun budgetPlan(
        amount: Double,
        currency: String
    ) = BudgetCalculatorPlan(
        monthlyBudget = amount,
        currency = currency,
        schedule = listOf(
            ScheduledPayment(
                paymentDate = LocalDate.now(),
                paymentNumber = 1,
                contributions = listOf(
                    GoalContribution(
                        goalId = "goal-1",
                        goalName = "Goal",
                        amount = amount,
                        runningTotal = amount
                    )
                )
            )
        ),
        isLeveled = false,
        minimumRequired = 150.0
    )
}
