package com.xax.CryptoSavingsTracker.data.local.reminders

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.work.GoalReminderWorker
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GoalReminderSchedulerImpl @Inject constructor(
    @ApplicationContext private val context: Context
) : GoalReminderScheduler {

    private val workManager: WorkManager by lazy { WorkManager.getInstance(context) }

    override fun schedule(goal: Goal) {
        if (goal.lifecycleStatus != GoalLifecycleStatus.ACTIVE || !goal.isReminderEnabled) {
            cancel(goal.id)
            return
        }

        val frequency = goal.reminderFrequency ?: run {
            cancel(goal.id)
            return
        }

        val periodDays = frequency.periodDays()
        val initialDelayMillis = computeInitialDelayMillis(goal = goal, periodDays = periodDays)

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
            .build()

        val request = PeriodicWorkRequestBuilder<GoalReminderWorker>(periodDays.toLong(), TimeUnit.DAYS)
            .setInputData(workDataOf(GoalReminderWorker.KEY_GOAL_ID to goal.id))
            .setConstraints(constraints)
            .setInitialDelay(initialDelayMillis, TimeUnit.MILLISECONDS)
            .addTag(TAG_GOAL_REMINDERS)
            .build()

        workManager.enqueueUniquePeriodicWork(
            workName(goal.id),
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    override fun cancel(goalId: String) {
        workManager.cancelUniqueWork(workName(goalId))
    }

    private fun computeInitialDelayMillis(goal: Goal, periodDays: Int): Long {
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)

        val reminderTimeMillis = goal.reminderTimeMillis ?: return 0L
        val reminderTime = extractLocalTime(reminderTimeMillis, zone)

        val firstDate = goal.firstReminderDate ?: LocalDate.now(zone)
        var next = firstDate.atTime(reminderTime).atZone(zone)

        if (!next.isAfter(now)) {
            val elapsedMillis = ChronoUnit.MILLIS.between(next, now).coerceAtLeast(0)
            val elapsedDays = elapsedMillis / MILLIS_PER_DAY
            val periodsElapsed = (elapsedDays / periodDays) + 1
            next = next.plusDays(periodsElapsed * periodDays.toLong())
        }

        return ChronoUnit.MILLIS.between(now, next).coerceAtLeast(0)
    }

    private fun extractLocalTime(reminderTimeMillis: Long, zone: ZoneId): LocalTime {
        return if (reminderTimeMillis in 0 until MILLIS_PER_DAY) {
            LocalTime.ofNanoOfDay(reminderTimeMillis * 1_000_000)
        } else {
            Instant.ofEpochMilli(reminderTimeMillis).atZone(zone).toLocalTime()
        }
    }

    private fun ReminderFrequency.periodDays(): Int = when (this) {
        ReminderFrequency.DAILY -> 1
        ReminderFrequency.WEEKLY -> 7
        ReminderFrequency.BIWEEKLY -> 14
        ReminderFrequency.MONTHLY -> 30
    }

    private fun workName(goalId: String): String = "goal_reminder_$goalId"

    private companion object {
        const val TAG_GOAL_REMINDERS = "goal_reminders"
        const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L
    }
}

