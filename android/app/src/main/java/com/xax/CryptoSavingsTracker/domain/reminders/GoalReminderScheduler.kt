package com.xax.CryptoSavingsTracker.domain.reminders

import com.xax.CryptoSavingsTracker.domain.model.Goal

/**
 * Schedules and cancels goal reminders.
 *
 * Android implementation uses WorkManager.
 */
interface GoalReminderScheduler {
    fun schedule(goal: Goal)
    fun cancel(goalId: String)
}

