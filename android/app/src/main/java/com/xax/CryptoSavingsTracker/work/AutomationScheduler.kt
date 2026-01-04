package com.xax.CryptoSavingsTracker.work

import android.content.Context
import androidx.work.*
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service responsible for scheduling automated monthly planning transitions.
 * Matches iOS AutomationScheduler for feature parity.
 *
 * Uses WorkManager for reliable background execution that survives app restarts
 * and device reboots.
 */
@Singleton
class AutomationScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val settings: MonthlyPlanningSettings
) {
    private val workManager: WorkManager by lazy { WorkManager.getInstance(context) }

    /**
     * Schedule or cancel automation workers based on current settings.
     * Call this when settings change or on app startup.
     */
    fun updateSchedule() {
        // Cancel existing workers
        workManager.cancelUniqueWork(WORK_AUTO_START)
        workManager.cancelUniqueWork(WORK_AUTO_COMPLETE)
        workManager.cancelUniqueWork(WORK_DAILY_CHECK)

        // Schedule daily check worker (runs every day to check for auto-start/complete)
        if (settings.autoStartEnabled || settings.autoCompleteEnabled) {
            scheduleDailyCheck()
        }
    }

    /**
     * Schedule a daily check worker that runs at 8 AM to check for automation triggers.
     */
    private fun scheduleDailyCheck() {
        val initialDelay = calculateInitialDelay(targetHour = 8, targetMinute = 0)

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
            .build()

        val dailyCheckRequest = PeriodicWorkRequestBuilder<AutomationCheckWorker>(
            repeatInterval = 1,
            repeatIntervalTimeUnit = TimeUnit.DAYS
        )
            .setInitialDelay(initialDelay, TimeUnit.MILLISECONDS)
            .setConstraints(constraints)
            .addTag(TAG_AUTOMATION)
            .build()

        workManager.enqueueUniquePeriodicWork(
            WORK_DAILY_CHECK,
            ExistingPeriodicWorkPolicy.UPDATE,
            dailyCheckRequest
        )
    }

    /**
     * Schedule a one-time auto-start check for the first of next month.
     */
    fun scheduleAutoStartForNextMonth() {
        if (!settings.autoStartEnabled) return

        val firstOfNextMonth = LocalDate.now().plusMonths(1).withDayOfMonth(1)
        val targetDateTime = LocalDateTime.of(firstOfNextMonth, LocalTime.of(8, 0))
        val delay = ChronoUnit.MILLIS.between(LocalDateTime.now(), targetDateTime)

        if (delay <= 0) return

        val request = OneTimeWorkRequestBuilder<AutoStartWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .addTag(TAG_AUTOMATION)
            .build()

        workManager.enqueueUniqueWork(
            WORK_AUTO_START,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    /**
     * Schedule a one-time auto-complete check for the last day of current month.
     */
    fun scheduleAutoCompleteForEndOfMonth() {
        if (!settings.autoCompleteEnabled) return

        val lastOfMonth = LocalDate.now().withDayOfMonth(LocalDate.now().lengthOfMonth())
        val targetDateTime = LocalDateTime.of(lastOfMonth, LocalTime.of(20, 0)) // 8 PM
        val delay = ChronoUnit.MILLIS.between(LocalDateTime.now(), targetDateTime)

        if (delay <= 0) return

        val request = OneTimeWorkRequestBuilder<AutoCompleteWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .addTag(TAG_AUTOMATION)
            .build()

        workManager.enqueueUniqueWork(
            WORK_AUTO_COMPLETE,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    /**
     * Trigger an immediate automation check (useful for testing or manual trigger).
     */
    fun triggerImmediateCheck() {
        val request = OneTimeWorkRequestBuilder<AutomationCheckWorker>()
            .addTag(TAG_AUTOMATION)
            .build()

        workManager.enqueue(request)
    }

    /**
     * Cancel all automation workers.
     */
    fun cancelAll() {
        workManager.cancelAllWorkByTag(TAG_AUTOMATION)
    }

    /**
     * Check if automation is currently scheduled.
     */
    fun isAutomationScheduled(): Boolean {
        return settings.autoStartEnabled || settings.autoCompleteEnabled
    }

    private fun calculateInitialDelay(targetHour: Int, targetMinute: Int): Long {
        val now = LocalDateTime.now()
        var target = now.withHour(targetHour).withMinute(targetMinute).withSecond(0).withNano(0)

        if (target.isBefore(now) || target.isEqual(now)) {
            target = target.plusDays(1)
        }

        return ChronoUnit.MILLIS.between(now, target)
    }

    companion object {
        const val TAG_AUTOMATION = "monthly_automation"
        const val WORK_DAILY_CHECK = "automation_daily_check"
        const val WORK_AUTO_START = "automation_auto_start"
        const val WORK_AUTO_COMPLETE = "automation_auto_complete"
    }
}
