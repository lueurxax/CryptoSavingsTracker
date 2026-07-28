package com.xax.CryptoSavingsTracker.domain.reminders

import com.xax.CryptoSavingsTracker.domain.model.Goal
import java.util.UUID

/**
 * Schedules and cancels goal reminders.
 *
 * Android implementation uses WorkManager.
 */
interface GoalReminderScheduler {
    fun schedule(goal: Goal)
    fun cancel(goalId: String)

    fun cancelRequest(workRequestId: UUID) {
        throw UnsupportedOperationException("Request-specific reminder cancellation is not implemented")
    }
}
