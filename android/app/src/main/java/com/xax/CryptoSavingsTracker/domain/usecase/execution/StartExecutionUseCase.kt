package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyPlanRepository
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import kotlinx.coroutines.flow.first
import java.util.UUID
import javax.inject.Inject

class StartExecutionUseCase @Inject constructor(
    private val monthlyPlanRepository: MonthlyPlanRepository,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val goalRepository: GoalRepository,
    private val goalProgressUseCase: GetGoalProgressUseCase,
    private val monthlyGoalPlanService: MonthlyGoalPlanService,
    private val monthlyPlanningService: MonthlyPlanningService
) {
    suspend operator fun invoke(monthLabel: String = MonthLabelUtils.nowUtc()): Result<ExecutionRecord> = runCatching {
        val existingExecuting = executionRecordRepository.getCurrentExecutingRecord().first()
        if (existingExecuting != null) {
            throw IllegalStateException("An execution is already in progress for ${existingExecuting.monthLabel}")
        }

        val now = System.currentTimeMillis()
        val plan = monthlyPlanRepository.getOrCreatePlan(monthLabel)
        val planId = plan.id
        val requirements = monthlyPlanningService.calculateMonthlyRequirements()
        val requirementsByGoalId = requirements.associateBy { it.goalId }
        monthlyGoalPlanService.syncPlans(monthLabel, requirements)
        val perGoalPlans = monthlyGoalPlanService
            .applyFlexAdjustment(monthLabel, monthlyPlanningService.flexAdjustment)
            .associateBy { it.goalId }

        val existing = executionRecordRepository.getRecordByMonthLabelOnce(monthLabel)
        val record = if (existing == null) {
            ExecutionRecord(
                id = UUID.randomUUID().toString(),
                planId = planId,
                monthLabel = monthLabel,
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = now,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                createdAtMillis = now,
                updatedAtMillis = now
            )
        } else {
            if (existing.status == ExecutionStatus.CLOSED) {
                throw IllegalStateException("Execution for $monthLabel is closed. Undo or create a new month.")
            }
            existing.copy(
                planId = planId,
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = existing.startedAtMillis ?: now,
                closedAtMillis = null,
                canUndoUntilMillis = null,
                updatedAtMillis = now
            )
        }

        executionRecordRepository.upsert(record)

        val activeGoals = goalRepository.getActiveGoals().first()
        val snapshots = activeGoals.map { goal ->
            val goalPlan = perGoalPlans[goal.id]
            val baseMonthlyRequired = requirementsByGoalId[goal.id]?.requiredMonthly
            val plannedMonthly = goalPlan?.effectiveAmount ?: baseMonthlyRequired

            val progress = goalProgressUseCase.getProgress(goal.id)
            val fundedAtStart = progress?.fundedAmount ?: 0.0
            val fallbackAmount = (goal.targetAmount - fundedAtStart).coerceAtLeast(0.0)
            val requiredAmount = plannedMonthly ?: fallbackAmount

            ExecutionSnapshot(
                id = UUID.randomUUID().toString(),
                executionRecordId = record.id,
                goalId = goal.id,
                goalName = goal.name,
                currency = goal.currency,
                targetAmount = goal.targetAmount,
                currentTotalAtStart = fundedAtStart,
                requiredAmount = requiredAmount,
                isProtected = goalPlan?.isProtected == true,
                isSkipped = goalPlan?.isSkipped == true,
                customAmount = goalPlan?.customAmount,
                createdAtMillis = now
            )
        }

        executionSnapshotRepository.replaceForRecord(record.id, snapshots)
        record
    }
}
