package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.*
import com.xax.CryptoSavingsTracker.domain.repository.*
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.FlexAdjustmentService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate

class StartExecutionUseCaseTest {
    @Test
    fun `start preserves an explicit custom amount at default flex`() = runTest {
        val fixture = Fixture(customAmount = 60.0, flex = 1.0)

        assertThat(fixture.useCase("2026-10").isSuccess).isTrue()

        assertThat(fixture.snapshots.single().requiredAmount).isEqualTo(60.0)
        assertThat(fixture.snapshots.single().customAmount).isEqualTo(60.0)
        assertThat(fixture.plans.single().customAmount).isEqualTo(60.0)
    }

    @Test
    fun `start does not apply saved flex amounts a second time`() = runTest {
        val fixture = Fixture(customAmount = 50.0, flex = 0.5)

        assertThat(fixture.useCase("2026-10").isSuccess).isTrue()

        assertThat(fixture.snapshots.single().requiredAmount).isEqualTo(50.0)
        assertThat(fixture.plans.single().effectiveAmount).isEqualTo(50.0)
    }

    private class Fixture(customAmount: Double, flex: Double) {
        var plans = listOf(
            MonthlyGoalPlan(
                id = "goal-plan", goalId = "goal", monthLabel = "2026-10",
                requiredMonthly = 100.0, remainingAmount = 1_000.0, monthsRemaining = 10,
                currency = "USD", status = RequirementStatus.ON_TRACK, state = MonthlyGoalPlanState.DRAFT,
                customAmount = customAmount, isProtected = false, isSkipped = false,
                createdAtUtcMillis = 1L, lastModifiedAtUtcMillis = 1L
            )
        )
        var snapshots = emptyList<ExecutionSnapshot>()
        val useCase: StartExecutionUseCase

        init {
            val goal = Goal(
                id = "goal", name = "Savings", currency = "USD", targetAmount = 1_000.0,
                deadline = LocalDate.of(2027, 8, 1), startDate = LocalDate.of(2026, 10, 1),
                lifecycleStatus = GoalLifecycleStatus.ACTIVE, lifecycleStatusChangedAt = null,
                emoji = null, description = null, link = null, reminderFrequency = null,
                reminderTimeMillis = null, firstReminderDate = null, createdAt = 1L, updatedAt = 1L
            )
            val requirement = MonthlyRequirement(
                id = "requirement", goalId = goal.id, goalName = goal.name, currency = "USD",
                targetAmount = 1_000.0, currentTotal = 0.0, remainingAmount = 1_000.0,
                monthsRemaining = 10, requiredMonthly = 100.0, progress = 0.0,
                deadline = goal.deadline, status = RequirementStatus.ON_TRACK
            )
            val planRepository = mockk<MonthlyGoalPlanRepository>()
            coEvery { planRepository.getPlansOnce("2026-10") } answers { plans }
            coEvery { planRepository.upsertAll(any()) } answers { plans = firstArg() }
            val monthlyPlanRepository = mockk<MonthlyPlanRepository>()
            coEvery { monthlyPlanRepository.getOrCreatePlan("2026-10") } returns MonthlyPlan(
                "monthly-plan", "2026-10", MonthlyPlanStatus.DRAFT, flex, 100.0,
                MonthlyPlanSettings(), 1L, 1L
            )
            val recordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
            every { recordRepository.getCurrentExecutingRecord() } returns flowOf(null)
            coEvery { recordRepository.getRecordByMonthLabelOnce("2026-10") } returns null
            val snapshotRepository = mockk<ExecutionSnapshotRepository>()
            coEvery { snapshotRepository.replaceForRecord(any(), any()) } answers { snapshots = secondArg() }
            val goals = mockk<GoalRepository>()
            every { goals.getActiveGoals() } returns flowOf(listOf(goal))
            val goalProgress = mockk<GetGoalProgressUseCase>()
            coEvery { goalProgress.getProgress(goal.id) } returns null
            val planning = mockk<MonthlyPlanningService>()
            coEvery { planning.calculateMonthlyRequirements() } returns listOf(requirement)
            every { planning.flexAdjustment } returns flex
            val runner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            }
            useCase = StartExecutionUseCase(
                monthlyPlanRepository, recordRepository, snapshotRepository, runner,
                goals, goalProgress, MonthlyGoalPlanService(planRepository, FlexAdjustmentService()), planning
            )
        }
    }
}
