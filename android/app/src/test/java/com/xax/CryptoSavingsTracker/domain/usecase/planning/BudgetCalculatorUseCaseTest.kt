package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class BudgetCalculatorUseCaseTest {
    @Test
    fun `schedule cache invalidates when funded progress changes for the same goal id`() = runTest {
        val goal = goal().copy(currency = "USD", targetAmount = 1_000.0)
        val exchangeRates = mockk<ExchangeRateRepository>()
        val progress = mockk<GetGoalProgressUseCase>()
        val settings = mockk<MonthlyPlanningSettings>()
        var fundedAmount = 0.0
        coEvery { progress.getProgress(goal.id) } answers {
            GoalWithProgress(
                goal = goal,
                allocatedAmount = fundedAmount,
                fundedAmount = fundedAmount,
                progress = fundedAmount / goal.targetAmount
            )
        }
        every { settings.paymentDay } returns 1
        val calculator = BudgetCalculatorUseCase(
            exchangeRateRepository = exchangeRates,
            getGoalProgressUseCase = progress,
            settings = settings
        )

        val beforeContribution = calculator.generateSchedule(
            goals = listOf(goal),
            budget = 100.0,
            currency = "USD"
        )
        fundedAmount = 400.0
        val afterContribution = calculator.generateSchedule(
            goals = listOf(goal),
            budget = 100.0,
            currency = "USD"
        )

        assertThat(beforeContribution.goalRemainingById[goal.id]).isEqualTo(1_000.0)
        assertThat(afterContribution.goalRemainingById[goal.id]).isEqualTo(600.0)
    }

    @Test
    fun `schedule cache invalidates when the same goal id gets a shorter deadline`() = runTest {
        val longDeadlineGoal = goal().copy(
            currency = "USD",
            targetAmount = 1_000.0,
            deadline = LocalDate.now().plusMonths(18)
        )
        val shortDeadlineGoal = longDeadlineGoal.copy(
            deadline = LocalDate.now().plusMonths(2)
        )
        val exchangeRates = mockk<ExchangeRateRepository>()
        val progress = mockk<GetGoalProgressUseCase>()
        val settings = mockk<MonthlyPlanningSettings>()
        coEvery { progress.getProgress(longDeadlineGoal.id) } returns GoalWithProgress(
            goal = longDeadlineGoal,
            allocatedAmount = 0.0,
            fundedAmount = 0.0,
            progress = 0.0
        )
        every { settings.paymentDay } returns 1
        val calculator = BudgetCalculatorUseCase(
            exchangeRateRepository = exchangeRates,
            getGoalProgressUseCase = progress,
            settings = settings
        )

        val longSchedule = calculator.generateSchedule(
            goals = listOf(longDeadlineGoal),
            budget = 100.0,
            currency = "USD"
        )
        val shortSchedule = calculator.generateSchedule(
            goals = listOf(shortDeadlineGoal),
            budget = 100.0,
            currency = "USD"
        )

        assertThat(shortSchedule.schedule).isNotEqualTo(longSchedule.schedule)
        assertThat(
            shortSchedule.schedule.all { payment ->
                !payment.paymentDate.isAfter(shortDeadlineGoal.deadline)
            }
        ).isTrue()
    }

    @Test
    fun `minimum budget rejects every non-positive or non-finite conversion rate`() = runTest {
        val invalidRates = listOf(
            0.0,
            -1.0,
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        )

        invalidRates.forEach { invalidRate ->
            val goal = goal()
            val exchangeRates = mockk<ExchangeRateRepository>()
            val progress = mockk<GetGoalProgressUseCase>()
            val settings = mockk<MonthlyPlanningSettings>()
            coEvery { exchangeRates.fetchRate("EUR", "USD") } returns invalidRate
            coEvery { progress.getProgress(goal.id) } returns GoalWithProgress(
                goal = goal,
                allocatedAmount = 0.0,
                fundedAmount = 0.0,
                progress = 0.0
            )
            every { settings.paymentDay } returns 1

            val failure = runCatching {
                BudgetCalculatorUseCase(
                    exchangeRateRepository = exchangeRates,
                    getGoalProgressUseCase = progress,
                    settings = settings
                ).calculateMinimumBudget(listOf(goal), "USD")
            }.exceptionOrNull()

            assertThat(failure).isNotNull()
            assertThat(failure).hasMessageThat().contains("invalid")
        }
    }

    private fun goal() = Goal(
        id = "goal-1",
        name = "Goal",
        currency = "EUR",
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
}
