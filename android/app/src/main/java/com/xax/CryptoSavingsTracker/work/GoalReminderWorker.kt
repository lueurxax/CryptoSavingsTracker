package com.xax.CryptoSavingsTracker.work

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
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class GoalReminderWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val goalRepository: GoalRepository
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val goalId = inputData.getString(KEY_GOAL_ID) ?: return Result.failure()

        val goal = goalRepository.getGoalById(goalId) ?: return Result.success()
        if (goal.lifecycleStatus != GoalLifecycleStatus.ACTIVE || !goal.isReminderEnabled) return Result.success()

        if (!canPostNotifications()) return Result.success()

        ensureChannel()
        postNotification(goalId = goal.id, title = "Goal reminder", message = "Contribute to “${goal.name}”.")

        return Result.success()
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
        val granted = ContextCompat.checkSelfPermission(applicationContext, android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        return granted && NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
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

    private fun postNotification(goalId: String, title: String, message: String) {
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

        NotificationManagerCompat.from(applicationContext).notify(goalId.hashCode(), notification)
    }

    companion object {
        const val KEY_GOAL_ID = "goal_id"
        private const val CHANNEL_ID = "goal_reminders"
    }
}

