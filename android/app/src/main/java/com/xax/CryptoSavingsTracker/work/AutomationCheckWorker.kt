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
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
import java.time.LocalDate

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
    private val completeExecutionUseCase: CompleteExecutionUseCase,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val today = AutomationWorkerPolicy.utcDate()
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
            if (AutomationWorkerPolicy.isTerminalExecutionUnavailable(e)) {
                Result.success()
            } else if (runAttemptCount < 3) {
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
        AutomationWorkerPolicy.requireSuccess(
            startExecutionUseCase(monthLabel)
        )
    }

    private suspend fun attemptAutoComplete() {
        val monthLabel = currentMonthLabel()

        // Check if there's an active execution
        val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
        if (existingRecord == null || existingRecord.status != ExecutionStatus.EXECUTING) {
            // No active execution, skip
            return
        }
        val session = getExecutionSessionUseCase.currentExecuting().first()
        if (!AutomationWorkerPolicy.shouldAutoComplete(existingRecord, session)) {
            return
        }

        // Complete execution
        AutomationWorkerPolicy.requireSuccess(
            completeExecutionUseCase(existingRecord.id)
        )
    }

    private fun currentMonthLabel(): String {
        return AutomationWorkerPolicy.monthLabel()
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
            val monthLabel = AutomationWorkerPolicy.monthLabel()

            // Check if already started
            val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
            if (existingRecord != null && existingRecord.status != ExecutionStatus.DRAFT) {
                return Result.success()
            }

            // Start execution
            AutomationWorkerPolicy.requireSuccess(
                startExecutionUseCase(monthLabel)
            )

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
    private val completeExecutionUseCase: CompleteExecutionUseCase,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        if (!settings.autoCompleteEnabled) {
            return Result.success()
        }

        return try {
            val monthLabel = AutomationWorkerPolicy.monthLabel()

            // Check if there's an active execution
            val existingRecord = executionRecordRepository.getRecordForMonth(monthLabel).first()
            if (existingRecord == null || existingRecord.status != ExecutionStatus.EXECUTING) {
                return Result.success()
            }
            val session = getExecutionSessionUseCase.currentExecuting().first()
            if (!AutomationWorkerPolicy.shouldAutoComplete(existingRecord, session)) {
                return Result.success()
            }

            // Complete execution
            AutomationWorkerPolicy.requireSuccess(
                completeExecutionUseCase(existingRecord.id)
            )

            Result.success()
        } catch (e: Exception) {
            if (AutomationWorkerPolicy.isTerminalExecutionUnavailable(e)) {
                Result.success()
            } else if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }
}
