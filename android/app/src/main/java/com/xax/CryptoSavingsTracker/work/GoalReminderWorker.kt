package com.xax.CryptoSavingsTracker.work

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.xax.CryptoSavingsTracker.MainActivity
import com.xax.CryptoSavingsTracker.R
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.UUID

internal inline fun postNotificationSafely(post: () -> Unit): Boolean {
    return try {
        post()
        true
    } catch (_: SecurityException) {
        false
    }
}

internal fun reminderNotificationChannelIsDeliverable(
    channelImportance: Int?,
    isChannelGroupBlocked: Boolean
): Boolean {
    return channelImportance != NotificationManager.IMPORTANCE_NONE && !isChannelGroupBlocked
}

internal enum class GoalReminderDeliveryOutcome {
    POSTED,
    DISABLED_UNDELIVERABLE,
    STALE_GOAL
}

internal suspend fun deliverGoalReminder(
    goal: Goal,
    canPostNotifications: Boolean,
    postNotification: () -> Boolean,
    disableUndeliverableReminder: suspend () -> Boolean
): GoalReminderDeliveryOutcome {
    val posted = canPostNotifications && postNotification()
    if (posted) return GoalReminderDeliveryOutcome.POSTED

    return if (disableUndeliverableReminder()) {
        GoalReminderDeliveryOutcome.DISABLED_UNDELIVERABLE
    } else {
        GoalReminderDeliveryOutcome.STALE_GOAL
    }
}

internal suspend fun disableAndCancelGoalReminder(
    goal: Goal,
    workRequestId: UUID,
    goalRepository: GoalRepository,
    reminderScheduler: GoalReminderScheduler
): Boolean {
    val nextVersion = if (goal.updatedAt == Long.MAX_VALUE) {
        Long.MAX_VALUE
    } else {
        goal.updatedAt + 1
    }
    val disabled = goalRepository.disableReminderIfUnchanged(
        goalId = goal.id,
        expectedUpdatedAt = goal.updatedAt,
        modifiedAt = maxOf(System.currentTimeMillis(), nextVersion)
    )
    if (!disabled) return false

    reminderScheduler.cancelRequest(workRequestId)
    return true
}

@HiltWorker
class GoalReminderWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val goalRepository: GoalRepository,
    private val reminderScheduler: GoalReminderScheduler
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val goalId = inputData.getString(KEY_GOAL_ID) ?: run {
            reminderScheduler.cancelRequest(id)
            return Result.failure()
        }

        val goal = goalRepository.getGoalById(goalId) ?: run {
            reminderScheduler.cancelRequest(id)
            return Result.success()
        }
        if (goal.lifecycleStatus != GoalLifecycleStatus.ACTIVE || !goal.isReminderEnabled) {
            reminderScheduler.cancelRequest(id)
            return Result.success()
        }

        val canPostNotifications = canPostNotifications()
        if (canPostNotifications) {
            ensureChannel()
        }
        deliverGoalReminder(
            goal = goal,
            canPostNotifications = canPostNotifications,
            postNotification = {
                postNotification(
                    goalId = goal.id,
                    title = "Goal reminder",
                    message = "Contribute to “${goal.name}”."
                )
            },
            disableUndeliverableReminder = {
                disableAndCancelGoalReminder(
                    goal = goal,
                    workRequestId = id,
                    goalRepository = goalRepository,
                    reminderScheduler = reminderScheduler
                )
            }
        )

        return Result.success()
    }

    private fun canPostNotifications(): Boolean {
        val appNotificationsEnabled =
            NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
        if (!appNotificationsEnabled) return false

        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                applicationContext,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return false
        }

        if (Build.VERSION.SDK_INT < 26) return true
        val manager =
            applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel(CHANNEL_ID)
        val isChannelGroupBlocked = if (Build.VERSION.SDK_INT >= 28) {
            channel?.group
                ?.let(manager::getNotificationChannelGroup)
                ?.isBlocked == true
        } else {
            false
        }
        return reminderNotificationChannelIsDeliverable(
            channelImportance = channel?.importance,
            isChannelGroupBlocked = isChannelGroupBlocked
        )
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Goal reminders",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Periodic reminders for goals."
        }
        manager.createNotificationChannel(channel)
    }

    @SuppressLint("MissingPermission")
    private fun postNotification(goalId: String, title: String, message: String): Boolean {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            goalId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        return postNotificationSafely {
            NotificationManagerCompat.from(applicationContext).notify(goalId.hashCode(), notification)
        }
    }

    companion object {
        const val KEY_GOAL_ID = "goal_id"
        private const val CHANNEL_ID = "goal_reminders"
    }
}
