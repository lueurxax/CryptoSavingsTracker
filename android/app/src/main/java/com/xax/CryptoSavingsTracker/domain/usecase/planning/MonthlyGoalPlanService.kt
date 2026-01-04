package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlin.math.min

/**
 * Creates/updates per-goal monthly plans from current requirements, preserving user preferences.
 * Mirrors iOS MonthlyPlanService behavior (one persisted row per goal per month).
 */
@Singleton
class MonthlyGoalPlanService @Inject constructor(
    private val repository: MonthlyGoalPlanRepository,
    private val flexAdjustmentService: FlexAdjustmentService
) {
    suspend fun syncPlans(
        monthLabel: String,
        requirements: List<MonthlyRequirement>
    ): List<MonthlyGoalPlan> {
        val existing = repository.getPlansOnce(monthLabel).associateBy { it.goalId }
        val now = System.currentTimeMillis()

        val updated = requirements.map { requirement ->
            val prior = existing[requirement.goalId]
            if (prior == null) {
                MonthlyGoalPlan(
                    id = UUID.randomUUID().toString(),
                    goalId = requirement.goalId,
                    monthLabel = monthLabel,
                    requiredMonthly = requirement.requiredMonthly,
                    remainingAmount = requirement.remainingAmount,
                    monthsRemaining = requirement.monthsRemaining,
                    currency = requirement.currency,
                    status = requirement.status,
                    state = MonthlyGoalPlanState.DRAFT,
                    customAmount = null,
                    isProtected = false,
                    isSkipped = false,
                    createdAtUtcMillis = now,
                    lastModifiedAtUtcMillis = now
                )
            } else {
                prior.copy(
                    requiredMonthly = requirement.requiredMonthly,
                    remainingAmount = requirement.remainingAmount,
                    monthsRemaining = requirement.monthsRemaining,
                    currency = requirement.currency,
                    status = requirement.status,
                    lastModifiedAtUtcMillis = now
                )
            }
        }

        repository.upsertAll(updated)
        return updated
    }

    suspend fun toggleProtected(monthLabel: String, goalId: String): MonthlyGoalPlan {
        val plan = repository.getPlanOnce(monthLabel, goalId)
            ?: throw IllegalStateException("Plan not found")

        val updated = plan.copy(
            isProtected = !plan.isProtected,
            isSkipped = false
        )
        repository.upsert(updated)
        return updated
    }

    suspend fun toggleSkipped(monthLabel: String, goalId: String): MonthlyGoalPlan {
        val plan = repository.getPlanOnce(monthLabel, goalId)
            ?: throw IllegalStateException("Plan not found")

        val updated = plan.copy(
            isSkipped = !plan.isSkipped,
            isProtected = false
        )
        repository.upsert(updated)
        return updated
    }

    suspend fun setCustomAmount(monthLabel: String, goalId: String, amount: Double?): MonthlyGoalPlan {
        val plan = repository.getPlanOnce(monthLabel, goalId)
            ?: throw IllegalStateException("Plan not found")

        val updated = plan.copy(
            customAmount = amount,
            isSkipped = false
        )
        repository.upsert(updated)
        return updated
    }

    /**
     * Apply flex adjustment to all flexible plans (not protected, not skipped).
     * iOS parity: always writes per-plan customAmount for flexible plans.
     *
     * @param monthLabel Current month label
     * @param adjustment Flex adjustment factor (0.0-1.5)
     * @param strategy Redistribution strategy for excess funds
     * @param requirements Original requirements for calculation
     */
    suspend fun applyFlexAdjustment(
        monthLabel: String,
        adjustment: Double,
        strategy: RedistributionStrategy = RedistributionStrategy.BALANCED,
        requirements: List<MonthlyRequirement>? = null
    ): List<MonthlyGoalPlan> {
        val clamped = min(1.5, max(0.0, adjustment))
        val plans = repository.getPlansOnce(monthLabel)
        val nonDraft = plans.filter { it.state != MonthlyGoalPlanState.DRAFT }
        if (nonDraft.isNotEmpty()) {
            throw IllegalStateException("Can only adjust draft plans")
        }

        // If no adjustment needed (factor = 1.0), clear custom amounts
        val epsilon = 0.0000001
        if (kotlin.math.abs(clamped - 1.0) <= epsilon) {
            val updated = plans.map { plan ->
                if (plan.isSkipped || plan.isProtected) plan
                else plan.copy(customAmount = null)
            }
            repository.upsertAll(updated)
            return updated
        }

        // Build requirements from plans if not provided
        val reqs = requirements ?: plans.map { plan ->
            MonthlyRequirement(
                id = plan.id,
                goalId = plan.goalId,
                goalName = plan.goalId,
                currency = plan.currency,
                targetAmount = 0.0,
                currentTotal = 0.0,
                remainingAmount = plan.remainingAmount,
                monthsRemaining = plan.monthsRemaining,
                requiredMonthly = plan.requiredMonthly,
                progress = 0.0,
                deadline = java.time.LocalDate.now().plusMonths(plan.monthsRemaining.toLong()),
                status = plan.status
            )
        }

        val protectedIds = plans.filter { it.isProtected }.map { it.goalId }.toSet()
        val skippedIds = plans.filter { it.isSkipped }.map { it.goalId }.toSet()

        // Use FlexAdjustmentService for redistribution
        val adjustedRequirements = flexAdjustmentService.applyFlexAdjustment(
            requirements = reqs,
            adjustment = clamped,
            protectedGoalIds = protectedIds,
            skippedGoalIds = skippedIds,
            strategy = strategy
        )

        // Map adjusted amounts back to plans
        val adjustmentsByGoalId = adjustedRequirements.associateBy { it.requirement.goalId }
        val updated = plans.map { plan ->
            val adjusted = adjustmentsByGoalId[plan.goalId]
            when {
                plan.isSkipped -> plan
                plan.isProtected -> plan
                adjusted != null -> {
                    val newAmount = adjusted.adjustedAmount
                    if (newAmount <= 0) plan.copy(customAmount = null)
                    else plan.copy(customAmount = newAmount)
                }
                else -> plan
            }
        }

        repository.upsertAll(updated)
        return updated
    }

    /**
     * Simulate flex adjustment without persisting changes.
     * Returns impact analysis for preview in UI.
     */
    suspend fun simulateFlexAdjustment(
        monthLabel: String,
        adjustment: Double,
        strategy: RedistributionStrategy,
        requirements: List<MonthlyRequirement>
    ): AdjustmentSimulation {
        val plans = repository.getPlansOnce(monthLabel)
        val protectedIds = plans.filter { it.isProtected }.map { it.goalId }.toSet()
        val skippedIds = plans.filter { it.isSkipped }.map { it.goalId }.toSet()

        return flexAdjustmentService.simulateAdjustment(
            requirements = requirements,
            adjustment = adjustment,
            protectedGoalIds = protectedIds,
            skippedGoalIds = skippedIds,
            strategy = strategy
        )
    }
}
