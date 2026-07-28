package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanGoalSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanStatus
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningFundingEvidence
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningSnapshot
import java.time.LocalDate

/**
 * Value-only view of every mutable input used to start an execution.
 *
 * Random presentation IDs are intentionally excluded. Provider/cache timestamps,
 * transaction identities, persisted update timestamps, and FX provenance remain
 * included so a source change cannot be mistaken for the same financial snapshot.
 */
internal data class ExecutionStartInputFingerprint(
    val goals: List<Goal>,
    val requirements: List<ExecutionRequirementFingerprint>,
    val fundingEvidence: List<MonthlyPlanningFundingEvidence>,
    val paymentDay: Int,
    val flexAdjustmentBits: Long,
    val displayCurrency: String,
    val undoGracePeriodHours: Int,
    val monthlyPlan: ExecutionMonthlyPlanFingerprint,
    val goalPlans: List<ExecutionGoalPlanFingerprint>,
    val rateScope: ExecutionRateScopeFingerprint,
    val requiredAssetIds: Set<String>,
    val onChainTransactionAssetIds: Set<String>
)

internal data class ExecutionRequirementFingerprint(
    val goalId: String,
    val goalName: String,
    val currency: String,
    val targetAmountBits: Long,
    val currentTotalBits: Long,
    val remainingAmountBits: Long,
    val monthsRemaining: Int,
    val requiredMonthlyBits: Long,
    val progressBits: Long,
    val deadline: LocalDate,
    val status: RequirementStatus
)

internal data class ExecutionMonthlyPlanFingerprint(
    val id: String,
    val monthLabel: String,
    val status: MonthlyPlanStatus,
    val flexPercentageBits: Long,
    val totalRequiredBits: Long,
    val settings: List<Pair<String, MonthlyPlanGoalSettings>>,
    val createdAtUtcMillis: Long,
    val lastModifiedAtUtcMillis: Long
)

internal data class ExecutionGoalPlanFingerprint(
    val id: String,
    val goalId: String,
    val monthLabel: String,
    val requiredMonthlyBits: Long,
    val remainingAmountBits: Long,
    val monthsRemaining: Int,
    val currency: String,
    val status: RequirementStatus,
    val state: com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState,
    val customAmountBits: Long?,
    val isProtected: Boolean,
    val isSkipped: Boolean,
    val createdAtUtcMillis: Long,
    val lastModifiedAtUtcMillis: Long
)

internal fun executionStartInputFingerprint(
    planning: MonthlyPlanningSnapshot,
    monthlyPlan: MonthlyPlan,
    goalPlans: List<MonthlyGoalPlan>,
    rateScope: ExecutionRateScopeFingerprint,
    requiredAssetIds: Set<String>,
    onChainTransactionAssetIds: Set<String>
): ExecutionStartInputFingerprint {
    val activeGoalIds = planning.goals.mapTo(hashSetOf()) { it.id }
    return ExecutionStartInputFingerprint(
        goals = planning.goals.sortedBy { it.id },
        requirements = planning.requirements
            .map { requirement ->
                ExecutionRequirementFingerprint(
                    goalId = requirement.goalId,
                    goalName = requirement.goalName,
                    currency = requirement.currency.uppercase(),
                    targetAmountBits = requirement.targetAmount.toBits(),
                    currentTotalBits = requirement.currentTotal.toBits(),
                    remainingAmountBits = requirement.remainingAmount.toBits(),
                    monthsRemaining = requirement.monthsRemaining,
                    requiredMonthlyBits = requirement.requiredMonthly.toBits(),
                    progressBits = requirement.progress.toBits(),
                    deadline = requirement.deadline,
                    status = requirement.status
                )
            }
            .sortedBy { it.goalId },
        fundingEvidence = planning.fundingEvidence.sortedWith(
            compareBy<MonthlyPlanningFundingEvidence>(
                { it.goalId },
                { it.allocation.assetId },
                { it.allocation.id }
            )
        ),
        paymentDay = planning.paymentDay,
        flexAdjustmentBits = planning.flexAdjustment.toBits(),
        displayCurrency = planning.displayCurrency.uppercase(),
        undoGracePeriodHours = planning.undoGracePeriodHours,
        monthlyPlan = ExecutionMonthlyPlanFingerprint(
            id = monthlyPlan.id,
            monthLabel = monthlyPlan.monthLabel,
            status = monthlyPlan.status,
            flexPercentageBits = monthlyPlan.flexPercentage.toBits(),
            totalRequiredBits = monthlyPlan.totalRequired.toBits(),
            settings = monthlyPlan.settings.perGoal.toList().sortedBy { it.first },
            createdAtUtcMillis = monthlyPlan.createdAtUtcMillis,
            lastModifiedAtUtcMillis = monthlyPlan.lastModifiedAtUtcMillis
        ),
        goalPlans = goalPlans
            .asSequence()
            .filter { it.goalId in activeGoalIds }
            .map { plan ->
                ExecutionGoalPlanFingerprint(
                    id = plan.id,
                    goalId = plan.goalId,
                    monthLabel = plan.monthLabel,
                    requiredMonthlyBits = plan.requiredMonthly.toBits(),
                    remainingAmountBits = plan.remainingAmount.toBits(),
                    monthsRemaining = plan.monthsRemaining,
                    currency = plan.currency.uppercase(),
                    status = plan.status,
                    state = plan.state,
                    customAmountBits = plan.customAmount?.toBits(),
                    isProtected = plan.isProtected,
                    isSkipped = plan.isSkipped,
                    createdAtUtcMillis = plan.createdAtUtcMillis,
                    lastModifiedAtUtcMillis = plan.lastModifiedAtUtcMillis
                )
            }
            .sortedBy { it.goalId }
            .toList(),
        rateScope = rateScope,
        requiredAssetIds = requiredAssetIds.toSortedSet(),
        onChainTransactionAssetIds = onChainTransactionAssetIds.toSortedSet()
    )
}
