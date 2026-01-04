package com.xax.CryptoSavingsTracker.work

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.StartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Worker that checks if any automated transitions should occur.
 * Runs daily to check for auto-start (1st of month) and auto-complete (last day of month).
 */
@HiltWorker
class AutomationCheckWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val settings: MonthlyPlanningSettings,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val startExecutionUseCase: StartExecutionUseCase,
    private val completeExecutionUseCase: CompleteExecutionUseCase
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val today = LocalDate.now()
            val dayOfMonth = today.dayOfMonth

            // Check for auto-start on 1st of month
            if (dayOfMonth == 1 && settings.autoStartEnabled) {
                attemptAutoStart()
            }

            // Check for auto-complete on last day of month
            if (isLastDayOfMonth(today) && settings.autoCompleteEnabled) {
                attemptAutoComplete()
            }

            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    private suspend fun attemptAutoStart() {
        val monthLabel = currentMonthLabel()

        // Check if already started
        val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
        if (existingRecord != null && existingRecord.status != ExecutionStatus.DRAFT) {
            // Already started, skip
            return
        }

        // Start execution
        val result = startExecutionUseCase(monthLabel)
        if (result.isSuccess) {
            // Apply grace period if configured
            val record = result.getOrNull()
            if (record != null && settings.undoGracePeriodHours > 0) {
                val gracePeriodMillis = settings.undoGracePeriodHours * 3600L * 1000L
                val canUndoUntil = System.currentTimeMillis() + gracePeriodMillis
                executionRecordRepository.updateCanUndoUntil(record.id, canUndoUntil)
            }
        }
    }

    private suspend fun attemptAutoComplete() {
        val monthLabel = currentMonthLabel()

        // Check if there's an active execution
        val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
        if (existingRecord == null || existingRecord.status != ExecutionStatus.EXECUTING) {
            // No active execution, skip
            return
        }

        // Complete execution
        val result = completeExecutionUseCase(existingRecord.id)
        if (result.isSuccess && settings.undoGracePeriodHours > 0) {
            val gracePeriodMillis = settings.undoGracePeriodHours * 3600L * 1000L
            val canUndoUntil = System.currentTimeMillis() + gracePeriodMillis
            executionRecordRepository.updateCanUndoUntil(existingRecord.id, canUndoUntil)
        }
    }

    private fun currentMonthLabel(): String {
        return LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"))
    }

    private fun isLastDayOfMonth(date: LocalDate): Boolean {
        return date.dayOfMonth == date.lengthOfMonth()
    }
}

/**
 * Worker specifically for auto-starting execution on the 1st of the month.
 * Used for one-time scheduled execution.
 */
@HiltWorker
class AutoStartWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val settings: MonthlyPlanningSettings,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val startExecutionUseCase: StartExecutionUseCase
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        if (!settings.autoStartEnabled) {
            return Result.success()
        }

        return try {
            val monthLabel = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"))

            // Check if already started
            val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
            if (existingRecord != null && existingRecord.status != ExecutionStatus.DRAFT) {
                return Result.success()
            }

            // Start execution
            val result = startExecutionUseCase(monthLabel)
            if (result.isSuccess) {
                val record = result.getOrNull()
                if (record != null && settings.undoGracePeriodHours > 0) {
                    val gracePeriodMillis = settings.undoGracePeriodHours * 3600L * 1000L
                    val canUndoUntil = System.currentTimeMillis() + gracePeriodMillis
                    executionRecordRepository.updateCanUndoUntil(record.id, canUndoUntil)
                }
            }

            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }
}

/**
 * Worker specifically for auto-completing execution on the last day of the month.
 * Used for one-time scheduled execution.
 */
@HiltWorker
class AutoCompleteWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val settings: MonthlyPlanningSettings,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val completeExecutionUseCase: CompleteExecutionUseCase
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        if (!settings.autoCompleteEnabled) {
            return Result.success()
        }

        return try {
            val monthLabel = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"))

            // Check if there's an active execution
            val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
            if (existingRecord == null || existingRecord.status != ExecutionStatus.EXECUTING) {
                return Result.success()
            }

            // Complete execution
            val result = completeExecutionUseCase(existingRecord.id)
            if (result.isSuccess && settings.undoGracePeriodHours > 0) {
                val gracePeriodMillis = settings.undoGracePeriodHours * 3600L * 1000L
                val canUndoUntil = System.currentTimeMillis() + gracePeriodMillis
                executionRecordRepository.updateCanUndoUntil(existingRecord.id, canUndoUntil)
            }

            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }
}
