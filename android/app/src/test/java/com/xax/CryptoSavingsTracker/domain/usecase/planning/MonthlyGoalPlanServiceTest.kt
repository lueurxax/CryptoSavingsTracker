package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate

class MonthlyGoalPlanServiceTest {
    private val flexAdjustmentService = mockk<FlexAdjustmentService>(relaxed = true)

    @Test
    fun syncPlans_preservesUserPreferencesWhileUpdatingCalculations() = runTest {
        val repo = mockk<MonthlyGoalPlanRepository>()
        val service = MonthlyGoalPlanService(repo, flexAdjustmentService)
        val monthLabel = "2025-12"

        val existing = MonthlyGoalPlan(
            id = "p1",
            goalId = "g1",
            monthLabel = monthLabel,
            requiredMonthly = 1.0,
            remainingAmount = 1.0,
            monthsRemaining = 1,
            currency = "USD",
            status = RequirementStatus.ON_TRACK,
            state = MonthlyGoalPlanState.DRAFT,
            customAmount = 123.0,
            isProtected = true,
            isSkipped = false,
            createdAtUtcMillis = 1L,
            lastModifiedAtUtcMillis = 1L
        )

        coEvery { repo.getPlansOnce(monthLabel) } returns listOf(existing)
        val captured = slot<List<MonthlyGoalPlan>>()
        coEvery { repo.upsertAll(capture(captured)) } returns Unit

        val requirements = listOf(
            requirement(goalId = "g1", requiredMonthly = 10.0, remaining = 100.0, monthsRemaining = 10, status = RequirementStatus.ATTENTION),
            requirement(goalId = "g2", requiredMonthly = 20.0, remaining = 200.0, monthsRemaining = 5, status = RequirementStatus.CRITICAL)
        )

        val result = service.syncPlans(monthLabel, requirements)

        assertThat(result).hasSize(2)
        val updatedG1 = result.first { it.goalId == "g1" }
        assertThat(updatedG1.requiredMonthly).isEqualTo(10.0)
        assertThat(updatedG1.remainingAmount).isEqualTo(100.0)
        assertThat(updatedG1.monthsRemaining).isEqualTo(10)
        assertThat(updatedG1.status).isEqualTo(RequirementStatus.ATTENTION)
        assertThat(updatedG1.customAmount).isEqualTo(123.0)
        assertThat(updatedG1.isProtected).isTrue()

        val createdG2 = result.first { it.goalId == "g2" }
        assertThat(createdG2.requiredMonthly).isEqualTo(20.0)
        assertThat(createdG2.customAmount).isNull()

        coVerify(exactly = 1) { repo.upsertAll(any()) }
        assertThat(captured.captured).hasSize(2)
    }

    @Test
    fun applyFlexAdjustment_setsCustomAmountForFlexiblePlans_andPreservesProtectedAndSkipped() = runTest {
        val repo = mockk<MonthlyGoalPlanRepository>()
        val service = MonthlyGoalPlanService(repo, flexAdjustmentService)
        val monthLabel = "2025-12"

        val flexible = plan(goalId = "g1", requiredMonthly = 100.0, customAmount = null, isProtected = false, isSkipped = false)
        val protected = plan(goalId = "g2", requiredMonthly = 100.0, customAmount = 999.0, isProtected = true, isSkipped = false)
        val skipped = plan(goalId = "g3", requiredMonthly = 100.0, customAmount = 888.0, isProtected = false, isSkipped = true)

        coEvery { repo.getPlansOnce(monthLabel) } returns listOf(flexible, protected, skipped)
        val captured = slot<List<MonthlyGoalPlan>>()
        coEvery { repo.upsertAll(capture(captured)) } returns Unit

        // Mock FlexAdjustmentService to return adjusted requirements
        coEvery {
            flexAdjustmentService.applyFlexAdjustment(
                requirements = any(),
                adjustment = any(),
                protectedGoalIds = any(),
                skippedGoalIds = any(),
                strategy = any()
            )
        } answers {
            val reqs = firstArg<List<MonthlyRequirement>>()
            val adjustment = secondArg<Double>()
            reqs.map { req ->
                adjustedRequirement(req, adjustedAmount = req.requiredMonthly * adjustment)
            }
        }

        service.applyFlexAdjustment(monthLabel, adjustment = 0.5)

        val updated = captured.captured.associateBy { it.goalId }
        assertThat(updated.getValue("g1").customAmount).isEqualTo(50.0)
        assertThat(updated.getValue("g2").customAmount).isEqualTo(999.0)
        assertThat(updated.getValue("g3").customAmount).isEqualTo(888.0)
    }

    @Test
    fun applyFlexAdjustment_clearsCustomAmountForFlexiblePlansWhenResetToOne() = runTest {
        val repo = mockk<MonthlyGoalPlanRepository>()
        val service = MonthlyGoalPlanService(repo, flexAdjustmentService)
        val monthLabel = "2025-12"

        val flexible = plan(goalId = "g1", requiredMonthly = 100.0, customAmount = 80.0, isProtected = false, isSkipped = false)
        coEvery { repo.getPlansOnce(monthLabel) } returns listOf(flexible)
        val captured = slot<List<MonthlyGoalPlan>>()
        coEvery { repo.upsertAll(capture(captured)) } returns Unit

        service.applyFlexAdjustment(monthLabel, adjustment = 1.0)

        assertThat(captured.captured.single().customAmount).isNull()
    }

    private fun plan(
        goalId: String,
        requiredMonthly: Double,
        customAmount: Double?,
        isProtected: Boolean,
        isSkipped: Boolean
    ): MonthlyGoalPlan {
        return MonthlyGoalPlan(
            id = "p-$goalId",
            goalId = goalId,
            monthLabel = "2025-12",
            requiredMonthly = requiredMonthly,
            remainingAmount = 0.0,
            monthsRemaining = 1,
            currency = "USD",
            status = RequirementStatus.ON_TRACK,
            state = MonthlyGoalPlanState.DRAFT,
            customAmount = customAmount,
            isProtected = isProtected,
            isSkipped = isSkipped,
            createdAtUtcMillis = 1L,
            lastModifiedAtUtcMillis = 1L
        )
    }

    private fun requirement(
        goalId: String,
        requiredMonthly: Double,
        remaining: Double,
        monthsRemaining: Int,
        status: RequirementStatus
    ): MonthlyRequirement {
        return MonthlyRequirement(
            id = "r-$goalId",
            goalId = goalId,
            goalName = "Goal $goalId",
            currency = "USD",
            targetAmount = 1000.0,
            currentTotal = 0.0,
            remainingAmount = remaining,
            monthsRemaining = monthsRemaining,
            requiredMonthly = requiredMonthly,
            progress = 0.0,
            deadline = LocalDate.now().plusDays(30),
            status = status
        )
    }

    private fun adjustedRequirement(
        req: MonthlyRequirement,
        adjustedAmount: Double
    ): AdjustedRequirement {
        return AdjustedRequirement(
            requirement = req,
            adjustedAmount = adjustedAmount,
            adjustmentReason = "Test",
            isProtected = false,
            isSkipped = false,
            adjustmentFactor = adjustedAmount / req.requiredMonthly,
            redistributionAmount = 0.0,
            impactAnalysis = ImpactAnalysis(
                changeAmount = adjustedAmount - req.requiredMonthly,
                changePercentage = (adjustedAmount - req.requiredMonthly) / req.requiredMonthly,
                estimatedDelay = 0,
                riskLevel = RiskLevel.LOW
            )
        )
    }
}

