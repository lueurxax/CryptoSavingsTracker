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
    private val repository: MonthlyGoalPlanRepository
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
     */
    suspend fun applyFlexAdjustment(monthLabel: String, adjustment: Double): List<MonthlyGoalPlan> {
        val clamped = min(1.5, max(0.0, adjustment))
        val plans = repository.getPlansOnce(monthLabel)
        val nonDraft = plans.filter { it.state != MonthlyGoalPlanState.DRAFT }
        if (nonDraft.isNotEmpty()) {
            throw IllegalStateException("Can only adjust draft plans")
        }

        val updated = plans.map { plan ->
            when {
                plan.isSkipped -> plan
                plan.isProtected -> plan
                else -> {
                    val epsilon = 0.0000001
                    if (kotlin.math.abs(clamped - 1.0) <= epsilon) {
                        plan.copy(customAmount = null)
                    } else {
                        val adjustedAmount = plan.requiredMonthly * clamped
                        if (adjustedAmount <= 0) {
                            throw IllegalStateException("Adjusted amount must be positive")
                        }
                        plan.copy(customAmount = adjustedAmount)
                    }
                }
            }
        }
        repository.upsertAll(updated)
        return updated
    }
}
