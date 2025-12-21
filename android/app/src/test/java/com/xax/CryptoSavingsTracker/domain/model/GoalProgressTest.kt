package com.xax.CryptoSavingsTracker.domain.model

import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class GoalProgressTest {
    @Test
    fun progressFromFunded_capsAtOne() = runTest {
        val goal = Goal(
            id = "g1",
            name = "Goal",
            currency = "USD",
            targetAmount = 100.0,
            deadline = LocalDate.now().plusDays(1),
            startDate = LocalDate.now(),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 1L
        )

        assertThat(goal.progressFromFunded(0.0)).isWithin(0.0000001).of(0.0)
        assertThat(goal.progressFromFunded(50.0)).isWithin(0.0000001).of(0.5)
        assertThat(goal.progressFromFunded(200.0)).isWithin(0.0000001).of(1.0)
        assertThat(goal.progressPercentFromFunded(50.0)).isEqualTo(50)
        assertThat(goal.progressPercentFromFunded(200.0)).isEqualTo(100)
    }
}

