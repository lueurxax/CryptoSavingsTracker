package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.presentation.planning.MonthlyExecutionContent
import com.xax.CryptoSavingsTracker.presentation.planning.MonthlyExecutionUiState
import org.junit.Rule
import org.junit.Test

class ExecutionUnavailableContentTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun executionContent_doesNotPublishSuccessOrEnableActions_whenProgressIsUnavailable() {
        val session = unavailableSession()

        composeRule.setContent {
            MaterialTheme {
                ActiveExecutionContent(
                    session = session,
                    displayCurrency = "USD",
                    remainingByGoalId = emptyMap(),
                    remainingCurrencyByGoalId = emptyMap(),
                    totalRemainingDisplay = null,
                    hasRateWarning = true,
                    lastRateUpdateMillis = null,
                    currentFocusGoal = null,
                    canUndoStart = true,
                    undoStartDeadlineMillis = session.record.canUndoUntilMillis,
                    canComplete = false,
                    isBusy = false,
                    onComplete = {},
                    onUndoStart = {},
                    onDisplayCurrencySelected = {},
                    onAddToCloseMonth = {},
                    onAssetSelected = {},
                    showAssetPicker = false,
                    assetOptions = emptyList(),
                    onDismissAssetPicker = {}
                )
            }
        }

        composeRule.onNodeWithTag("execution_progress_unavailable").assertIsDisplayed()
        composeRule.onAllNodesWithText("All goals funded! 🎉").assertCountEquals(0)
        composeRule.onAllNodesWithText("Monthly Progress").assertCountEquals(0)
        composeRule.onNodeWithText("Finish", substring = true).assertIsNotEnabled()
        composeRule.onNodeWithText("Cancel tracking").assertIsDisplayed()
    }

    @Test
    fun monthlyContent_doesNotPublishProgressOrEnableCompletion_whenProgressIsUnavailable() {
        val session = unavailableSession()

        composeRule.setContent {
            MaterialTheme {
                MonthlyExecutionContent(
                    uiState = MonthlyExecutionUiState(
                        record = session.record,
                        isProgressAvailable = false,
                        recoveryRequired = true,
                        canComplete = false,
                        showUndoBanner = true,
                        isLoading = false
                    ),
                    onUndoStart = {},
                    onComplete = {},
                    onGoalClick = {}
                )
            }
        }

        composeRule.onNodeWithTag("monthly_execution_progress_unavailable").assertIsDisplayed()
        composeRule.onAllNodesWithText("Monthly Progress").assertCountEquals(0)
        composeRule.onNodeWithText("Complete Month").assertIsNotEnabled()
        composeRule.onNodeWithText("Cancel tracking").assertIsDisplayed()
    }

    private fun unavailableSession(): ExecutionSession {
        val now = System.currentTimeMillis()
        return ExecutionSession(
            record = ExecutionRecord(
                id = "legacy-execution",
                planId = "plan",
                monthLabel = "2026-07",
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = now - 72L * 60L * 60L * 1000L,
                closedAtMillis = null,
                canUndoUntilMillis = now - 1L,
                createdAtMillis = now - 72L * 60L * 60L * 1000L,
                updatedAtMillis = now
            ),
            goals = emptyList(),
            isProgressAvailable = false
        )
    }
}
