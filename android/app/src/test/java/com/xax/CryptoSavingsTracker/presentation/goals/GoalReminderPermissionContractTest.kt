package com.xax.CryptoSavingsTracker.presentation.goals

import com.google.common.truth.Truth.assertThat
import androidx.lifecycle.LifecycleOwner
import io.mockk.mockk
import org.junit.jupiter.api.Test

class GoalReminderPermissionContractTest {
    @Test
    fun `Android 13 denial requests permission and keeps reminder disabled`() {
        val permissionState = goalReminderPermissionState(
            sdkInt = 33,
            isPermissionGranted = false
        )

        assertThat(goalReminderEnableEffect(permissionState))
            .isEqualTo(GoalReminderEnableEffect.REQUEST_PERMISSION)

        val denial = goalReminderPermissionResult(granted = false)
        assertThat(denial.enableReminder).isFalse()
        assertThat(denial.showDenial).isTrue()
    }

    @Test
    fun `granted notification permission enables reminder without denial`() {
        val permissionState = goalReminderPermissionState(
            sdkInt = 34,
            isPermissionGranted = true
        )

        assertThat(goalReminderEnableEffect(permissionState))
            .isEqualTo(GoalReminderEnableEffect.ENABLE)

        val result = goalReminderPermissionResult(granted = true)
        assertThat(result.enableReminder).isTrue()
        assertThat(result.showDenial).isFalse()
    }

    @Test
    fun `permission callback publishes granted state before enabling reminder`() {
        val effects = mutableListOf<String>()

        applyGoalReminderPermissionResult(
            granted = true,
            onPermissionStateChanged = { effects += "permission:$it" },
            onDenialChanged = { effects += "denied:$it" },
            onReminderEnabledChanged = { effects += "enabled:$it" }
        )

        assertThat(effects).containsExactly(
            "permission:${GoalReminderPermissionState.GRANTED}",
            "denied:false",
            "enabled:true"
        ).inOrder()
    }

    @Test
    fun `existing enabled reminder is disabled when notification permission is missing`() {
        val result = reconcileEnabledReminderWithPermission(
            reminderEnabled = true,
            permissionState = GoalReminderPermissionState.REQUIRED
        )

        assertThat(result.enableReminder).isFalse()
        assertThat(result.showDenial).isTrue()
    }

    @Test
    fun `existing enabled reminder remains enabled when notification permission is granted`() {
        val result = reconcileEnabledReminderWithPermission(
            reminderEnabled = true,
            permissionState = GoalReminderPermissionState.GRANTED
        )

        assertThat(result.enableReminder).isTrue()
        assertThat(result.showDenial).isFalse()
    }

    @Test
    fun `resume observer rereads notification permission after returning from settings`() {
        var currentPermission = GoalReminderPermissionState.GRANTED
        val observedStates = mutableListOf<GoalReminderPermissionState>()
        val observer = GoalReminderPermissionLifecycleObserver(
            readPermissionState = { currentPermission },
            onPermissionStateChanged = observedStates::add
        )
        val owner = mockk<LifecycleOwner>()

        observer.onResume(owner)
        currentPermission = GoalReminderPermissionState.REQUIRED
        observer.onResume(owner)

        assertThat(observedStates).containsExactly(
            GoalReminderPermissionState.GRANTED,
            GoalReminderPermissionState.REQUIRED
        ).inOrder()
    }

    @Test
    fun `save rereads permission and rejects a stale enabled reminder after revocation`() {
        var currentPermission = GoalReminderPermissionState.GRANTED
        val readPermissionState = { currentPermission }
        currentPermission = GoalReminderPermissionState.REQUIRED

        val result = goalReminderSaveResult(
            reminderEnabled = true,
            readPermissionState = readPermissionState
        )

        assertThat(result.enableReminder).isFalse()
        assertThat(result.showDenial).isTrue()
    }
}
