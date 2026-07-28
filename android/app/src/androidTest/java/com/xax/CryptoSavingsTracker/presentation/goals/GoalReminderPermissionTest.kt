package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class GoalReminderPermissionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun enablingReminderWhilePermissionRequired_requestsPermissionAndStaysOff() {
        var permissionRequests = 0
        val enabledChanges = mutableListOf<Boolean>()

        composeRule.setContent {
            GoalReminderPermissionToggle(
                checked = false,
                permissionState = GoalReminderPermissionState.REQUIRED,
                permissionDenied = false,
                onRequestPermission = { permissionRequests += 1 },
                onReminderEnabledChange = { enabledChanges += it },
                onPermissionMismatch = {}
            )
        }

        composeRule.onNodeWithTag(GOAL_REMINDER_SWITCH_TAG).performClick()

        composeRule.runOnIdle {
            assertEquals(1, permissionRequests)
            assertTrue(enabledChanges.isEmpty())
        }
        composeRule.onNodeWithTag(GOAL_REMINDER_SWITCH_TAG).assertIsOff()
    }

    @Test
    fun deniedPermission_isExposedNextToReminderToggle() {
        composeRule.setContent {
            GoalReminderPermissionToggle(
                checked = false,
                permissionState = GoalReminderPermissionState.REQUIRED,
                permissionDenied = true,
                onRequestPermission = {},
                onReminderEnabledChange = {},
                onPermissionMismatch = {}
            )
        }

        composeRule.onNodeWithTag(GOAL_REMINDER_PERMISSION_DENIED_TAG).assertIsDisplayed()
    }

    @Test
    fun existingEnabledReminder_isDisabledWhenPermissionWasRevoked() {
        composeRule.setContent {
            var enabled by remember { mutableStateOf(true) }
            var denied by remember { mutableStateOf(false) }

            GoalReminderPermissionToggle(
                checked = enabled,
                permissionState = GoalReminderPermissionState.REQUIRED,
                permissionDenied = denied,
                onRequestPermission = {},
                onReminderEnabledChange = { enabled = it },
                onPermissionMismatch = { denied = true }
            )
        }

        composeRule.onNodeWithTag(GOAL_REMINDER_SWITCH_TAG).assertIsOff()
        composeRule.onNodeWithTag(GOAL_REMINDER_PERMISSION_DENIED_TAG).assertIsDisplayed()
    }
}
