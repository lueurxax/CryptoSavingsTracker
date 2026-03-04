package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import org.junit.jupiter.api.Test

class GoalDashboardSceneAssemblerTest {
    private val assembler = GoalDashboardSceneAssembler(GoalDashboardNextActionResolver())

    @Test
    fun assemblesFreshnessAndProvenanceFields() {
        val generatedAt = Instant.parse("2026-03-04T08:00:00Z")
        val scene = assembler.assemble(
            GoalDashboardSceneInput(
                goal = testGoal(),
                generatedAt = generatedAt,
                currentAmount = BigDecimal("1500.25"),
                targetAmount = BigDecimal("3000"),
                remainingAmount = BigDecimal("1499.75"),
                progressRatio = 0.5000833333,
                daysRemaining = 90,
                freshness = DataFreshnessState.STALE,
                freshnessUpdatedAt = generatedAt,
                freshnessReason = "missing_exchange_rate",
                reasonCode = "missing_exchange_rate",
                assumptionWindowDays = 30,
                forecastConfidence = GoalDashboardForecastConfidence.MEDIUM,
                forecastStatus = GoalDashboardRiskStatus.AT_RISK,
                forecastUpdatedAt = generatedAt,
                projectedAmount = BigDecimal("2400"),
                forecastWhyCopyKey = "dashboard.forecast.why.at_risk",
                forecastErrorReasonCode = null,
                monthContributionSum = BigDecimal("100"),
                recentRows = emptyList(),
                lastContributionAt = null,
                overAllocated = false,
                concentrationRatio = 0.4,
                topAssets = emptyList(),
                allocationWarningCopyKey = null,
                hasAssets = true,
                hasContributionsThisMonth = true,
                lastSuccessfulRefreshAt = Instant.parse("2026-03-03T08:00:00Z"),
                legacyWidgetPrefsApplied = false
            )
        )

        assertThat(scene.freshness).isEqualTo(DataFreshnessState.STALE)
        assertThat(scene.freshnessUpdatedAt).isEqualTo(generatedAt)
        assertThat(scene.freshnessReason).isEqualTo("missing_exchange_rate")
        assertThat(scene.telemetryContext.source).isEqualTo("goal_dashboard_screen")
        assertThat(scene.nextAction.resolverState).isEqualTo(GoalDashboardNextActionResolverState.STALE_DATA)
    }

    private fun testGoal(): Goal {
        return Goal(
            id = "8d45a045-37a1-4cb6-8f80-12e5fdf6f2aa",
            name = "Goal",
            currency = "USD",
            targetAmount = 3000.0,
            deadline = LocalDate.parse("2026-06-02"),
            startDate = LocalDate.parse("2025-01-01"),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = "🎯",
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 0L,
            updatedAt = 0L
        )
    }
}
