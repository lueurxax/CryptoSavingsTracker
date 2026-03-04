package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import java.time.Instant
import org.junit.jupiter.api.Test

class GoalDashboardNextActionResolverTest {
    private val resolver = GoalDashboardNextActionResolver()

    @Test
    fun resolverCoversAllNineStatesDeterministically() {
        val base = GoalDashboardNextActionInput(
            lifecycle = GoalDashboardLifecycleState.ACTIVE,
            freshness = DataFreshnessState.FRESH,
            hasAssets = true,
            hasContributionsThisMonth = true,
            forecastStatus = GoalDashboardRiskStatus.ON_TRACK,
            forecastConfidence = GoalDashboardForecastConfidence.HIGH,
            overAllocated = false,
            lastSuccessfulRefreshAt = Instant.parse("2026-03-04T08:00:00Z"),
            reasonCode = null
        )

        assertThat(resolver.resolve(base.copy(freshness = DataFreshnessState.HARD_ERROR)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.HARD_ERROR)
        assertThat(resolver.resolve(base.copy(lifecycle = GoalDashboardLifecycleState.FINISHED)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.GOAL_FINISHED_OR_ARCHIVED)
        assertThat(resolver.resolve(base.copy(lifecycle = GoalDashboardLifecycleState.PAUSED)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.GOAL_PAUSED)
        assertThat(resolver.resolve(base.copy(overAllocated = true)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.OVER_ALLOCATED)
        assertThat(resolver.resolve(base.copy(hasAssets = false)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.NO_ASSETS)
        assertThat(resolver.resolve(base.copy(hasContributionsThisMonth = false)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.NO_CONTRIBUTIONS)
        assertThat(resolver.resolve(base.copy(freshness = DataFreshnessState.STALE)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.STALE_DATA)
        assertThat(resolver.resolve(base.copy(forecastStatus = GoalDashboardRiskStatus.OFF_TRACK)).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.BEHIND_SCHEDULE)
        assertThat(resolver.resolve(base).resolverState)
            .isEqualTo(GoalDashboardNextActionResolverState.ON_TRACK)
    }

    @Test
    fun hardErrorDiagnosticsPayloadIncludesRequiredFields() {
        val output = resolver.resolve(
            GoalDashboardNextActionInput(
                lifecycle = GoalDashboardLifecycleState.ACTIVE,
                freshness = DataFreshnessState.HARD_ERROR,
                hasAssets = true,
                hasContributionsThisMonth = true,
                forecastStatus = null,
                forecastConfidence = null,
                overAllocated = false,
                lastSuccessfulRefreshAt = Instant.parse("2026-03-04T08:00:00Z"),
                reasonCode = "rates_unavailable"
            )
        )

        assertThat(output.diagnostics).isNotNull()
        val diagnostics = checkNotNull(output.diagnostics)
        assertThat(diagnostics.reasonCode).isEqualTo("rates_unavailable")
        assertThat(diagnostics.lastSuccessfulRefreshAt).isEqualTo(Instant.parse("2026-03-04T08:00:00Z"))
        assertThat(diagnostics.nextStepCopyKey).isEqualTo("dashboard.nextAction.hardError.nextStep")
    }
}
