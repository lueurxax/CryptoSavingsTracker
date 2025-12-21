package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import org.junit.Rule
import org.junit.Test

class UnallocatedAssetsSectionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun sectionRendersWhenItemsPresent() {
        composeRule.setContent {
            UnallocatedAssetsSection(
                items = listOf(
                    UnallocatedAssetWarning(
                        assetId = "a1",
                        currency = "BTC",
                        address = "bc1qexample",
                        chainId = "bitcoin",
                        unallocatedPercentage = 40,
                        unallocatedAmount = 0.004106
                    )
                ),
                onAssetClick = {}
            )
        }

        composeRule.onNodeWithTag("unallocatedAssetsSection").assertIsDisplayed()
        composeRule.onNodeWithTag("unallocatedAssetCard_a1").assertIsDisplayed()
    }
}

