package com.xax.CryptoSavingsTracker.work

import android.app.NotificationManager
import androidx.work.ExistingPeriodicWorkPolicy
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.reminders.GOAL_REMINDER_REPLACEMENT_POLICY
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.coVerifyOrder
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.util.UUID

class GoalReminderNotificationSafetyTest {
    @Test
    fun `rescheduling replaces the old request with an independent work generation`() {
        assertThat(GOAL_REMINDER_REPLACEMENT_POLICY)
            .isEqualTo(ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE)
    }

    @Test
    fun `permission revoked between check and notify is handled without crashing`() {
        var attempts = 0

        val posted = postNotificationSafely {
            attempts += 1
            throw SecurityException("POST_NOTIFICATIONS revoked")
        }

        assertThat(posted).isFalse()
        assertThat(attempts).isEqualTo(1)
    }

    @Test
    fun `successful notify reports that the notification was posted`() {
        val posted = postNotificationSafely {}

        assertThat(posted).isTrue()
    }

    @Test
    fun `disabled reminder channel is undeliverable even when app notifications are enabled`() = runTest {
        var postAttempts = 0
        var disableCalls = 0
        val channelIsDeliverable = reminderNotificationChannelIsDeliverable(
            channelImportance = NotificationManager.IMPORTANCE_NONE,
            isChannelGroupBlocked = false
        )

        val outcome = deliverGoalReminder(
            goal = reminderGoal(),
            canPostNotifications = channelIsDeliverable,
            postNotification = {
                postAttempts += 1
                true
            },
            disableUndeliverableReminder = {
                disableCalls += 1
                true
            }
        )

        assertThat(outcome).isEqualTo(GoalReminderDeliveryOutcome.DISABLED_UNDELIVERABLE)
        assertThat(postAttempts).isEqualTo(0)
        assertThat(disableCalls).isEqualTo(1)
        assertThat(
            reminderNotificationChannelIsDeliverable(
                channelImportance = NotificationManager.IMPORTANCE_DEFAULT,
                isChannelGroupBlocked = true
            )
        ).isFalse()
    }

    @Test
    fun `missing permission disables persisted reminder before canceling periodic work`() = runTest {
        val goal = reminderGoal()
        val workRequestId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val repository = mockk<GoalRepository>()
        val scheduler = mockk<GoalReminderScheduler>()
        coEvery {
            repository.disableReminderIfUnchanged(
                goalId = goal.id,
                expectedUpdatedAt = goal.updatedAt,
                modifiedAt = match { it > goal.updatedAt }
            )
        } returns true
        every { scheduler.cancelRequest(workRequestId) } returns Unit

        val outcome = deliverGoalReminder(
            goal = goal,
            canPostNotifications = false,
            postNotification = { error("Notification must not be attempted") },
            disableUndeliverableReminder = {
                disableAndCancelGoalReminder(
                    goal = goal,
                    workRequestId = workRequestId,
                    goalRepository = repository,
                    reminderScheduler = scheduler
                )
            }
        )

        assertThat(outcome).isEqualTo(GoalReminderDeliveryOutcome.DISABLED_UNDELIVERABLE)
        coVerifyOrder {
            repository.disableReminderIfUnchanged(
                goalId = goal.id,
                expectedUpdatedAt = goal.updatedAt,
                modifiedAt = match { it > goal.updatedAt }
            )
            scheduler.cancelRequest(workRequestId)
        }
    }

    @Test
    fun `concurrent goal edit prevents stale worker from canceling the new reminder`() = runTest {
        val goal = reminderGoal()
        val workRequestId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val repository = mockk<GoalRepository>()
        val scheduler = mockk<GoalReminderScheduler>(relaxed = true)
        coEvery {
            repository.disableReminderIfUnchanged(
                goalId = goal.id,
                expectedUpdatedAt = goal.updatedAt,
                modifiedAt = any()
            )
        } returns false

        val outcome = deliverGoalReminder(
            goal = goal,
            canPostNotifications = false,
            postNotification = { error("Notification must not be attempted") },
            disableUndeliverableReminder = {
                disableAndCancelGoalReminder(
                    goal = goal,
                    workRequestId = workRequestId,
                    goalRepository = repository,
                    reminderScheduler = scheduler
                )
            }
        )

        assertThat(outcome).isEqualTo(GoalReminderDeliveryOutcome.STALE_GOAL)
        coVerify(exactly = 1) {
            repository.disableReminderIfUnchanged(
                goalId = goal.id,
                expectedUpdatedAt = goal.updatedAt,
                modifiedAt = any()
            )
        }
        verify(exactly = 0) { scheduler.cancel(any()) }
        verify(exactly = 0) { scheduler.cancelRequest(any()) }
    }

    @Test
    fun `re-enable between CAS and stale worker cancel keeps the new request scheduled`() = runTest {
        val goal = reminderGoal()
        val staleWorkRequestId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val replacementWorkRequestId = UUID.fromString("00000000-0000-0000-0000-000000000002")
        val activeRequests = linkedSetOf(staleWorkRequestId)
        var reminderEnabled = true
        val repository = mockk<GoalRepository>()
        val scheduler = mockk<GoalReminderScheduler>()
        coEvery {
            repository.disableReminderIfUnchanged(
                goalId = goal.id,
                expectedUpdatedAt = goal.updatedAt,
                modifiedAt = any()
            )
        } answers {
            reminderEnabled = false
            reminderEnabled = true
            activeRequests += replacementWorkRequestId
            true
        }
        every { scheduler.cancelRequest(any()) } answers {
            activeRequests -= firstArg<UUID>()
            Unit
        }

        val disabled = disableAndCancelGoalReminder(
            goal = goal,
            workRequestId = staleWorkRequestId,
            goalRepository = repository,
            reminderScheduler = scheduler
        )

        assertThat(disabled).isTrue()
        assertThat(reminderEnabled).isTrue()
        assertThat(activeRequests).containsExactly(replacementWorkRequestId)
        verify(exactly = 1) { scheduler.cancelRequest(staleWorkRequestId) }
        verify(exactly = 0) { scheduler.cancel(any()) }
    }

    @Test
    fun `permission revoked during notify disables and cancels reminder`() = runTest {
        val goal = reminderGoal()
        var disableCalls = 0

        val outcome = deliverGoalReminder(
            goal = goal,
            canPostNotifications = true,
            postNotification = { false },
            disableUndeliverableReminder = {
                disableCalls += 1
                true
            }
        )

        assertThat(outcome).isEqualTo(GoalReminderDeliveryOutcome.DISABLED_UNDELIVERABLE)
        assertThat(disableCalls).isEqualTo(1)
    }

    @Test
    fun `successful notification leaves persisted reminder enabled`() = runTest {
        val goal = reminderGoal()
        var disableCalls = 0

        val outcome = deliverGoalReminder(
            goal = goal,
            canPostNotifications = true,
            postNotification = { true },
            disableUndeliverableReminder = {
                disableCalls += 1
                true
            }
        )

        assertThat(outcome).isEqualTo(GoalReminderDeliveryOutcome.POSTED)
        assertThat(disableCalls).isEqualTo(0)
    }

    private fun reminderGoal() = Goal(
        id = "goal-1",
        name = "Emergency fund",
        currency = "USD",
        targetAmount = 10_000.0,
        deadline = LocalDate.of(2030, 1, 1),
        startDate = LocalDate.of(2026, 1, 1),
        lifecycleStatus = GoalLifecycleStatus.ACTIVE,
        lifecycleStatusChangedAt = null,
        emoji = null,
        description = null,
        link = null,
        reminderFrequency = ReminderFrequency.WEEKLY,
        reminderTimeMillis = 1_000L,
        firstReminderDate = LocalDate.of(2026, 1, 1),
        createdAt = 1L,
        updatedAt = 2L
    )
}
