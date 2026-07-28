package com.xax.CryptoSavingsTracker.accessibility

import android.content.Context
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.MainActivity
import com.xax.CryptoSavingsTracker.data.local.database.dao.GoalDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.presentation.onboarding.ONBOARDING_COMPLETED_KEY
import com.xax.CryptoSavingsTracker.presentation.onboarding.ONBOARDING_PREFS_NAME
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate
import javax.inject.Inject

@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class VisualRuntimeAccessibilityTest {

    companion object {
        @JvmStatic
        @BeforeClass
        fun setUpClass() {
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

    @Inject
    lateinit var goalDao: GoalDao

    @Before
    fun setUp() {
        hiltRule.inject()
        seedActiveGoal()
    }

    @Test
    fun planning_dashboard_settings_cover_runtime_accessibility_contract() {
        assertPlanningFlowContract()
        assertDashboardFlowContract()
        assertSettingsFlowContract()
    }

    private fun assertPlanningFlowContract() {
        composeRule.onNode(hasText("Planning") and hasClickAction()).performClick()
        waitForTag("planning.header_card")
        composeRule.onNodeWithTag("planning.header_card").performScrollTo().assertIsDisplayed()
        waitForTag("planning.goal_row")
        val goalRows = composeRule.onAllNodesWithTag("planning.goal_row").fetchSemanticsNodes()
        assertTrue("Expected at least one planning.goal_row node.", goalRows.isNotEmpty())

        assertScreenReaderLabels("Monthly Total")
        assertFocusOrderByTag("planning.header_card", "planning.goal_row")
        assertContrastProxyByTag("planning.header_card")
        assertReducedMotionProxyByTag("planning.header_card")
        assertNonColorSemantics("Monthly Required")
    }

    private fun assertDashboardFlowContract() {
        composeRule.onNode(hasText("Dashboard") and hasClickAction()).performClick()
        composeRule.onNodeWithTag("dashboard.summary_card").assertIsDisplayed()

        assertScreenReaderLabels("Portfolio Total (USD)")
        assertFocusOrderByText("Portfolio Total (USD)", "Assets")
        assertContrastProxyByTag("dashboard.summary_card")
        assertReducedMotionProxyByTag("dashboard.summary_card")
        assertNonColorSemantics("Portfolio Total (USD)")
    }

    private fun assertSettingsFlowContract() {
        composeRule.onNodeWithContentDescription("Settings").performClick()
        composeRule.onNodeWithTag("settings.section_row").assertIsDisplayed()

        assertScreenReaderLabels("Version")
        assertFocusOrderByText("Data", "About")
        assertContrastProxyByTag("settings.section_row")
        assertReducedMotionProxyByTag("settings.section_row")
        assertNonColorSemantics("Version")
    }

    private fun assertScreenReaderLabels(text: String) {
        val nodes = composeRule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes()
        assertTrue("Expected at least one screen-reader label for '$text'.", nodes.isNotEmpty())
    }

    private fun assertFocusOrderByTag(firstTag: String, secondTag: String) {
        val first = composeRule.onNodeWithTag(firstTag).fetchSemanticsNode().boundsInRoot
        val second = composeRule.onAllNodesWithTag(secondTag).fetchSemanticsNodes().first().boundsInRoot
        assertOrdered(first, second)
    }

    private fun assertFocusOrderByText(firstText: String, secondText: String) {
        val first = composeRule.onAllNodesWithText(firstText, substring = true)
            .fetchSemanticsNodes().first().boundsInRoot
        val second = composeRule.onAllNodesWithText(secondText, substring = true)
            .fetchSemanticsNodes().first().boundsInRoot
        assertOrdered(first, second)
    }

    private fun assertOrdered(first: Rect, second: Rect) {
        assertTrue(
            "Expected first focusable element to appear before second.",
            first.top <= second.top + 1f
        )
    }

    private fun assertContrastProxyByTag(tag: String) {
        composeRule.onNodeWithTag(tag).assertIsDisplayed()
    }

    private fun assertReducedMotionProxyByTag(tag: String) {
        composeRule.waitForIdle()
        composeRule.onNodeWithTag(tag).assertIsDisplayed()
    }

    private fun assertNonColorSemantics(text: String) {
        val nodes = composeRule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes()
        assertFalse("Expected explicit non-color semantic text marker.", nodes.isEmpty())
        val firstNode = nodes.first()
        val hasText = runCatching {
            firstNode.config[SemanticsProperties.Text].isNotEmpty()
        }.getOrDefault(false)
        assertTrue("Expected text semantics for non-color cue.", hasText)
    }

    private fun waitForTag(tag: String) {
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun seedActiveGoal() = runBlocking {
        val today = LocalDate.now()
        goalDao.insert(
            GoalEntity(
                id = "accessibility-goal",
                name = "Accessibility Goal",
                currency = "USD",
                targetAmount = 1_200.0,
                deadlineEpochDay = today.plusMonths(12).toEpochDay().toInt(),
                startDateEpochDay = today.toEpochDay().toInt(),
                lifecycleStatus = "active"
            )
        )
    }
}
