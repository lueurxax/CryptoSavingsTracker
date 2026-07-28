package com.xax.CryptoSavingsTracker.presentation.onboarding

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import org.junit.Rule
import org.junit.Test

class OnboardingErrorMessageTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun persistenceFailure_isVisibleToTheUser() {
        composeRule.setContent {
            OnboardingErrorMessage(error = "Failed to persist ETH")
        }

        composeRule.onNodeWithTag(ONBOARDING_ERROR_TAG)
            .assertIsDisplayed()
            .assertTextContains("Failed to persist ETH")
    }
}
