package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import javax.inject.Inject

/**
 * Use case for updating an existing goal
 */
class UpdateGoalUseCase @Inject constructor(
    private val repository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    /**
     * Update a goal with new values
     */
    suspend operator fun invoke(goal: Goal): Result<Goal> {
        // Validation
        if (goal.name.isBlank()) {
            return Result.failure(IllegalArgumentException("Goal name cannot be empty"))
        }
        if (!goal.targetAmount.isFinite() || goal.targetAmount <= 0) {
            return Result.failure(
                IllegalArgumentException("Target amount must be finite and greater than 0")
            )
        }
        if (goal.deadline.isBefore(goal.startDate)) {
            return Result.failure(IllegalArgumentException("Deadline must be after start date"))
        }

        val normalized = normalizeReminderDefaults(goal)
        val updatedGoal = normalized.copy(updatedAt = System.currentTimeMillis())

        return try {
            repository.updateGoal(updatedGoal)
            if (updatedGoal.lifecycleStatus == GoalLifecycleStatus.ACTIVE) {
                reminderScheduler.schedule(updatedGoal)
            } else {
                reminderScheduler.cancel(updatedGoal.id)
            }
            Result.success(updatedGoal)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Update goal status
     */
    suspend fun updateStatus(goalId: String, status: GoalLifecycleStatus): Result<Unit> {
        return try {
            val updated = transactionRunner.run {
                val current = repository.getGoalById(goalId)
                    ?: throw IllegalStateException("Goal not found")
                val now = System.currentTimeMillis()
                val retired = status != GoalLifecycleStatus.ACTIVE
                val updatedGoal = current.copy(
                    lifecycleStatus = status,
                    lifecycleStatusChangedAt = now,
                    reminderFrequency = current.reminderFrequency.takeUnless { retired },
                    reminderTimeMillis = current.reminderTimeMillis.takeUnless { retired },
                    firstReminderDate = current.firstReminderDate.takeUnless { retired },
                    updatedAt = now
                )

                repository.updateGoal(updatedGoal)
                if (status == GoalLifecycleStatus.CANCELLED) {
                    val allocations = allocationRepository.getAllocationsForGoal(goalId)
                    for (allocation in allocations) {
                        allocationHistoryService.createDeletionSnapshot(
                            assetId = allocation.assetId,
                            goalId = allocation.goalId,
                            timestampMillis = now
                        )
                    }
                    allocationRepository.deleteAllocationsForGoal(goalId)
                }
                if (retired) {
                    removeFromActiveExecution(goalId)
                }
                updatedGoal
            }

            if (status == GoalLifecycleStatus.ACTIVE) {
                reminderScheduler.schedule(normalizeReminderDefaults(updated))
            } else {
                reminderScheduler.cancel(goalId)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private suspend fun removeFromActiveExecution(goalId: String) {
        val record = executionRecordRepository.getCurrentExecutingRecord().first() ?: return
        val currentSnapshots = executionSnapshotRepository.getByRecordId(record.id).first()
        if (currentSnapshots.none { it.goalId == goalId }) return

        val remainingSnapshots = currentSnapshots.filterNot { it.goalId == goalId }
        executionSnapshotRepository.replaceForRecord(record.id, remainingSnapshots)
        if (remainingSnapshots.isEmpty()) {
            executionAssetRateRepository.deleteByRecordId(record.id)
            executionRecordRepository.revertToDraft(record.id)
        }
    }

    private fun normalizeReminderDefaults(goal: Goal): Goal {
        val reminderFrequency = goal.reminderFrequency ?: return goal.copy(
            reminderTimeMillis = null,
            firstReminderDate = null
        )

        val zone = ZoneId.systemDefault()
        val firstDate = goal.firstReminderDate ?: LocalDate.now(zone)
        val reminderTimeMillis = goal.reminderTimeMillis ?: firstDate
            .atTime(DEFAULT_REMINDER_TIME)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()

        return goal.copy(
            reminderFrequency = reminderFrequency,
            reminderTimeMillis = reminderTimeMillis,
            firstReminderDate = goal.firstReminderDate ?: firstDate
        )
    }

    private companion object {
        val DEFAULT_REMINDER_TIME: LocalTime = LocalTime.of(9, 0)
    }
}
