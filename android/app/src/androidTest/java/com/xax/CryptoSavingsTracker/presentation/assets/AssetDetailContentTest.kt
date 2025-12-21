package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AssetDetailContentTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun balanceText_showsTotalIncludingOnChain() {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1_700_000_000_000,
            updatedAt = 1_700_000_000_000
        )

        val onChain = OnChainBalance(
            assetId = asset.id,
            chainId = "bitcoin",
            address = "bc1qexample",
            currency = "BTC",
            balance = 0.004106,
            fetchedAtMillis = 1_700_000_000_000,
            isStale = false
        )

        composeRule.setContent {
            MaterialTheme {
                AssetDetailContent(
                    asset = asset,
                    manualBalance = 0.0,
                    currentBalance = 0.004106,
                    currentBalanceUsd = null,
                    isUsdLoading = false,
                    usdError = null,
                    onRefreshUsdBalance = {},
                    recentTransactions = emptyList(),
                    onChainBalance = onChain,
                    isOnChainLoading = false,
                    onChainError = null,
                    onRefreshOnChainBalance = {},
                    onAddTransaction = {},
                    onViewTransactions = {}
                )
            }
        }

        composeRule.onNodeWithTag("assetDetailCurrentBalance")
            .assertTextContains("0.004106", substring = true)
            .assertTextContains("BTC", substring = true)
    }
}
