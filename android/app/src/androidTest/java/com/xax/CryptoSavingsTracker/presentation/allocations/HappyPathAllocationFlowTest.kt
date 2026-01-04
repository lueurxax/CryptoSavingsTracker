package com.xax.CryptoSavingsTracker.presentation.allocations

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.MainActivity
import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AssetDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.GoalDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.presentation.onboarding.ONBOARDING_COMPLETED_KEY
import com.xax.CryptoSavingsTracker.presentation.onboarding.ONBOARDING_PREFS_NAME
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class HappyPathAllocationFlowTest {

    companion object {
        @JvmStatic
        @org.junit.BeforeClass
        fun setUpClass() {
            // Skip onboarding before activity launches
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            context.getSharedPreferences(ONBOARDING_PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(ONBOARDING_COMPLETED_KEY, true)
                .commit()
        }
    }

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @javax.inject.Inject lateinit var goalDao: GoalDao
    @javax.inject.Inject lateinit var assetDao: AssetDao
    @javax.inject.Inject lateinit var allocationDao: AllocationDao

    private val goalId = "goal-1"
    private val assetId = "asset-1"

    @Before
    fun setUp() {
        hiltRule.inject()
        seedGoalAndAsset()
    }

    @Test
    fun addAllocation_fromOnChainBalance_updatesGoalProgressAndAllocationSummary() {
        // App starts at Dashboard, navigate to Goals tab
        // Use hasClickAction to distinguish the tab from any text labels
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("Goals").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNode(hasText("Goals") and hasClickAction()).performClick()

        // Wait for Goal A to appear
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("Goal A").fetchSemanticsNodes().isNotEmpty()
        }
        // Open Goal from list
        composeRule.onNodeWithText("Goal A").performClick()
        composeRule.onNodeWithText("Goal Details").assertIsDisplayed()

        // Go to allocations
        composeRule.onNodeWithText("Manage").performClick()
        composeRule.onNodeWithText("Allocations").assertIsDisplayed()

        // Add allocation
        composeRule.onNodeWithContentDescription("Add Allocation").performClick()
        composeRule.onNodeWithText("Add Allocation").assertIsDisplayed()

        // Select BTC asset (available on-chain) and use MAX
        composeRule.onAllNodesWithText("BTC", substring = true)[0].performClick()
        composeRule.onNodeWithText("MAX").performClick()
        composeRule.onNode(hasText("Add Allocation") and hasClickAction()).performClick()

        // Back on allocations list: should not be 0% funded
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("41% funded").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("41% funded").assertIsDisplayed()

        // Back to goal detail: should show non-zero progress percent
        composeRule.onNodeWithContentDescription("Back").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("41%").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("41%").assertIsDisplayed()
    }

    private fun seedGoalAndAsset() = runBlocking {
        goalDao.insert(
            GoalEntity(
                id = goalId,
                name = "Goal A",
                currency = "USD",
                targetAmount = 1000.0,
                deadlineEpochDay = 10_000,
                startDateEpochDay = 9_000,
                lifecycleStatus = "active",
                emoji = "\uD83D\uDE00"
            )
        )
        assetDao.insert(
            AssetEntity(
                id = assetId,
                currency = "BTC",
                address = "bc1qexampleaddress",
                chainId = "bitcoin"
            )
        )
        // Ensure no allocations exist so the test validates the "Add Allocation" happy path.
        allocationDao.deleteByGoalId(goalId)
    }
}
