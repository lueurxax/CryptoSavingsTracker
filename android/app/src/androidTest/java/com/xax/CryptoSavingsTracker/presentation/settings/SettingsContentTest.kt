package com.xax.CryptoSavingsTracker.presentation.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class SettingsContentTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun exportCsvButton_invokesCallback() {
        var exportClicks = 0

        composeTestRule.setContent {
            SettingsContent(
                uiState = SettingsUiState(),
                onUpdateCoinGeckoApiKey = {},
                onUpdateTatumApiKey = {},
                onSave = {},
                onClearCaches = {},
                onExportCsv = { exportClicks += 1 },
                onTapVersion = {},
                isDeveloperModeEnabled = false,
                versionLabel = "1.0.0"
            )
        }

        composeTestRule.onNodeWithTag("settingsExportCsvButton").assertIsDisplayed().performClick()
        assertEquals(1, exportClicks)
    }

    @Test
    fun apiKeys_areHidden_whenDeveloperModeDisabled() {
        composeTestRule.setContent {
            SettingsContent(
                uiState = SettingsUiState(),
                onUpdateCoinGeckoApiKey = {},
                onUpdateTatumApiKey = {},
                onSave = {},
                onClearCaches = {},
                onExportCsv = {},
                onTapVersion = {},
                isDeveloperModeEnabled = false,
                versionLabel = "1.0.0"
            )
        }

        composeTestRule.onAllNodesWithTag("settingsCoinGeckoKey").assertCountEquals(0)
        composeTestRule.onAllNodesWithTag("settingsTatumKey").assertCountEquals(0)
    }

    @Test
    fun apiKeys_areVisible_whenDeveloperModeEnabled() {
        composeTestRule.setContent {
            SettingsContent(
                uiState = SettingsUiState(),
                onUpdateCoinGeckoApiKey = {},
                onUpdateTatumApiKey = {},
                onSave = {},
                onClearCaches = {},
                onExportCsv = {},
                onTapVersion = {},
                isDeveloperModeEnabled = true,
                versionLabel = "1.0.0"
            )
        }

        composeTestRule.onNodeWithTag("settingsCoinGeckoKey").assertIsDisplayed()
        composeTestRule.onNodeWithTag("settingsTatumKey").assertIsDisplayed()
    }
}
