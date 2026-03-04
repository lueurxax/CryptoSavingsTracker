package com.xax.CryptoSavingsTracker.presentation.dashboard

import java.time.Instant
import javax.inject.Inject

data class GoalDashboardNextActionInput(
    val lifecycle: GoalDashboardLifecycleState,
    val freshness: DataFreshnessState,
    val hasAssets: Boolean,
    val hasContributionsThisMonth: Boolean,
    val forecastStatus: GoalDashboardRiskStatus?,
    val forecastConfidence: GoalDashboardForecastConfidence?,
    val overAllocated: Boolean,
    val lastSuccessfulRefreshAt: Instant?,
    val reasonCode: String?
)

class GoalDashboardNextActionResolver @Inject constructor() {
    fun resolve(input: GoalDashboardNextActionInput): NextActionSlice {
        val state = resolveState(input)
        val payload = payloadFor(
            state = state,
            lastSuccessfulRefreshAt = input.lastSuccessfulRefreshAt,
            reasonCode = input.reasonCode
        )
        val moduleState = when (input.freshness) {
            DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
            DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            DataFreshnessState.FRESH -> GoalDashboardModuleState.READY
        }
        return NextActionSlice(
            resolverState = state,
            moduleState = moduleState,
            primaryCta = payload.primary,
            secondaryCta = payload.secondary,
            reasonCopyKey = payload.reasonCopyKey,
            isBlocking = payload.isBlocking,
            diagnostics = payload.diagnostics
        )
    }

    private fun resolveState(input: GoalDashboardNextActionInput): GoalDashboardNextActionResolverState {
        if (input.freshness == DataFreshnessState.HARD_ERROR) {
            return GoalDashboardNextActionResolverState.HARD_ERROR
        }
        if (input.lifecycle == GoalDashboardLifecycleState.FINISHED || input.lifecycle == GoalDashboardLifecycleState.ARCHIVED) {
            return GoalDashboardNextActionResolverState.GOAL_FINISHED_OR_ARCHIVED
        }
        if (input.lifecycle == GoalDashboardLifecycleState.PAUSED) {
            return GoalDashboardNextActionResolverState.GOAL_PAUSED
        }
        if (input.overAllocated) {
            return GoalDashboardNextActionResolverState.OVER_ALLOCATED
        }
        if (!input.hasAssets) {
            return GoalDashboardNextActionResolverState.NO_ASSETS
        }
        if (!input.hasContributionsThisMonth) {
            return GoalDashboardNextActionResolverState.NO_CONTRIBUTIONS
        }
        if (input.freshness == DataFreshnessState.STALE) {
            return GoalDashboardNextActionResolverState.STALE_DATA
        }
        if (input.forecastStatus == GoalDashboardRiskStatus.OFF_TRACK) {
            return GoalDashboardNextActionResolverState.BEHIND_SCHEDULE
        }
        if (input.forecastStatus == GoalDashboardRiskStatus.ON_TRACK && input.forecastConfidence == GoalDashboardForecastConfidence.LOW) {
            return GoalDashboardNextActionResolverState.STALE_DATA
        }
        return GoalDashboardNextActionResolverState.ON_TRACK
    }

    private fun payloadFor(
        state: GoalDashboardNextActionResolverState,
        lastSuccessfulRefreshAt: Instant?,
        reasonCode: String?
    ): NextActionPayload {
        return when (state) {
            GoalDashboardNextActionResolverState.HARD_ERROR -> NextActionPayload(
                primary = cta(
                    id = "retry_data_sync",
                    title = "Retry Data Sync",
                    copyKey = "dashboard.nextAction.hardError.primary",
                    systemImage = "arrow.clockwise"
                ),
                secondary = cta(
                    id = "view_diagnostics",
                    title = "View Diagnostics",
                    copyKey = "dashboard.nextAction.hardError.secondary",
                    systemImage = "doc.text.magnifyingglass"
                ),
                reasonCopyKey = "dashboard.nextAction.hardError.reason",
                isBlocking = true,
                diagnostics = DiagnosticsPayload(
                    reasonCode = reasonCode ?: "unknown_hard_error",
                    lastSuccessfulRefreshAt = lastSuccessfulRefreshAt,
                    nextStepCopyKey = "dashboard.nextAction.hardError.nextStep",
                    userMessage = GoalDashboardCopyCatalog.hardErrorUserMessage
                )
            )

            GoalDashboardNextActionResolverState.GOAL_FINISHED_OR_ARCHIVED -> NextActionPayload(
                primary = cta(
                    id = "view_goal_history",
                    title = "View Goal History",
                    copyKey = "dashboard.nextAction.finished.primary",
                    systemImage = "clock.arrow.circlepath"
                ),
                secondary = cta(
                    id = "create_new_goal",
                    title = "Create New Goal",
                    copyKey = "dashboard.nextAction.finished.secondary",
                    systemImage = "plus.circle"
                ),
                reasonCopyKey = "dashboard.nextAction.finished.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.GOAL_PAUSED -> NextActionPayload(
                primary = cta(
                    id = "resume_goal",
                    title = "Resume Goal",
                    copyKey = "dashboard.nextAction.paused.primary",
                    systemImage = "play.circle"
                ),
                secondary = cta(
                    id = "edit_goal",
                    title = "Edit Goal",
                    copyKey = "dashboard.nextAction.paused.secondary",
                    systemImage = "pencil.circle"
                ),
                reasonCopyKey = "dashboard.nextAction.paused.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.OVER_ALLOCATED -> NextActionPayload(
                primary = cta(
                    id = "rebalance_allocations",
                    title = "Rebalance Allocations",
                    copyKey = "dashboard.nextAction.overAllocated.primary",
                    systemImage = "arrow.left.arrow.right.circle"
                ),
                secondary = cta(
                    id = "open_allocation_health",
                    title = "Open Allocation Health",
                    copyKey = "dashboard.nextAction.overAllocated.secondary",
                    systemImage = "gauge.with.dots.needle.33percent"
                ),
                reasonCopyKey = "dashboard.nextAction.overAllocated.reason",
                isBlocking = true
            )

            GoalDashboardNextActionResolverState.NO_ASSETS -> NextActionPayload(
                primary = cta(
                    id = "add_first_asset",
                    title = "Add First Asset",
                    copyKey = "dashboard.nextAction.noAssets.primary",
                    systemImage = "plus.circle.fill"
                ),
                secondary = cta(
                    id = "edit_goal",
                    title = "Edit Goal",
                    copyKey = "dashboard.nextAction.noAssets.secondary",
                    systemImage = "pencil.circle"
                ),
                reasonCopyKey = "dashboard.nextAction.noAssets.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.NO_CONTRIBUTIONS -> NextActionPayload(
                primary = cta(
                    id = "add_first_contribution",
                    title = "Add First Contribution",
                    copyKey = "dashboard.nextAction.noContributions.primary",
                    systemImage = "arrow.down.circle.fill"
                ),
                secondary = cta(
                    id = "open_activity",
                    title = "Open Activity",
                    copyKey = "dashboard.nextAction.noContributions.secondary",
                    systemImage = "list.bullet.rectangle"
                ),
                reasonCopyKey = "dashboard.nextAction.noContributions.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.STALE_DATA -> NextActionPayload(
                primary = cta(
                    id = "refresh_data",
                    title = "Refresh Data",
                    copyKey = "dashboard.nextAction.stale.primary",
                    systemImage = "arrow.clockwise"
                ),
                secondary = cta(
                    id = "continue_last_data",
                    title = "Continue With Last Data",
                    copyKey = "dashboard.nextAction.stale.secondary",
                    systemImage = "clock.badge.exclamationmark"
                ),
                reasonCopyKey = "dashboard.nextAction.stale.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.BEHIND_SCHEDULE -> NextActionPayload(
                primary = cta(
                    id = "plan_this_month",
                    title = "Plan This Month",
                    copyKey = "dashboard.nextAction.behind.primary",
                    systemImage = "calendar.badge.exclamationmark"
                ),
                secondary = cta(
                    id = "add_contribution",
                    title = "Add Contribution",
                    copyKey = "dashboard.nextAction.behind.secondary",
                    systemImage = "arrow.down.circle"
                ),
                reasonCopyKey = "dashboard.nextAction.behind.reason",
                isBlocking = false
            )

            GoalDashboardNextActionResolverState.ON_TRACK -> NextActionPayload(
                primary = cta(
                    id = "log_contribution",
                    title = "Log Contribution",
                    copyKey = "dashboard.nextAction.onTrack.primary",
                    systemImage = "plus.circle"
                ),
                secondary = cta(
                    id = "open_forecast",
                    title = "Open Forecast",
                    copyKey = "dashboard.nextAction.onTrack.secondary",
                    systemImage = "chart.line.uptrend.xyaxis"
                ),
                reasonCopyKey = "dashboard.nextAction.onTrack.reason",
                isBlocking = false
            )
        }
    }

    private fun cta(id: String, title: String, copyKey: String, systemImage: String): DashboardCTA {
        return DashboardCTA(
            id = id,
            title = title,
            copyKey = copyKey,
            systemImage = systemImage
        )
    }
}

private data class NextActionPayload(
    val primary: DashboardCTA,
    val secondary: DashboardCTA?,
    val reasonCopyKey: String,
    val isBlocking: Boolean,
    val diagnostics: DiagnosticsPayload? = null
)
