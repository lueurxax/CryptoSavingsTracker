package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.xax.CryptoSavingsTracker.domain.model.Goal
import java.math.BigDecimal
import java.time.Instant
import javax.inject.Inject

data class GoalDashboardSceneInput(
    val goal: Goal,
    val generatedAt: Instant,
    val currentAmount: BigDecimal,
    val targetAmount: BigDecimal,
    val remainingAmount: BigDecimal,
    val progressRatio: Double,
    val daysRemaining: Int?,
    val freshness: DataFreshnessState,
    val freshnessUpdatedAt: Instant?,
    val freshnessReason: String?,
    val reasonCode: String?,
    val assumptionWindowDays: Int?,
    val forecastConfidence: GoalDashboardForecastConfidence?,
    val forecastStatus: GoalDashboardRiskStatus?,
    val forecastUpdatedAt: Instant?,
    val projectedAmount: BigDecimal?,
    val forecastWhyCopyKey: String?,
    val forecastErrorReasonCode: String?,
    val monthContributionSum: BigDecimal,
    val recentRows: List<ActivityRow>,
    val lastContributionAt: Instant?,
    val overAllocated: Boolean,
    val concentrationRatio: Double?,
    val topAssets: List<AssetWeight>,
    val allocationWarningCopyKey: String?,
    val hasAssets: Boolean,
    val hasContributionsThisMonth: Boolean,
    val lastSuccessfulRefreshAt: Instant?,
    val legacyWidgetPrefsApplied: Boolean
)

class GoalDashboardSceneAssembler @Inject constructor(
    private val nextActionResolver: GoalDashboardNextActionResolver
) {
    fun assemble(input: GoalDashboardSceneInput): GoalDashboardSceneModel {
        val lifecycle = input.goal.lifecycleStatus.toDashboardLifecycleState()
        val snapshotModuleState = moduleStateFromFreshness(input.freshness)
        val nextAction = nextActionResolver.resolve(
            GoalDashboardNextActionInput(
                lifecycle = lifecycle,
                freshness = input.freshness,
                hasAssets = input.hasAssets,
                hasContributionsThisMonth = input.hasContributionsThisMonth,
                forecastStatus = input.forecastStatus,
                forecastConfidence = input.forecastConfidence,
                overAllocated = input.overAllocated,
                lastSuccessfulRefreshAt = input.lastSuccessfulRefreshAt,
                reasonCode = input.reasonCode
            )
        )

        val forecastModuleState = when {
            input.forecastErrorReasonCode != null -> GoalDashboardModuleState.ERROR
            input.projectedAmount == null && input.forecastStatus == null -> GoalDashboardModuleState.EMPTY
            input.freshness == DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
            input.freshness == DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            else -> GoalDashboardModuleState.READY
        }

        val contributionModuleState = when {
            input.freshness == DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
            input.freshness == DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            input.recentRows.isEmpty() -> GoalDashboardModuleState.EMPTY
            else -> GoalDashboardModuleState.READY
        }

        val allocationModuleState = when {
            !input.hasAssets -> GoalDashboardModuleState.EMPTY
            input.freshness == DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
            input.freshness == DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            else -> GoalDashboardModuleState.READY
        }

        val utilityActions = defaultUtilityActions()
        val utilitiesModuleState = when (input.freshness) {
            DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
            DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            DataFreshnessState.FRESH -> if (utilityActions.isEmpty()) GoalDashboardModuleState.EMPTY else GoalDashboardModuleState.READY
        }

        val forecastWhyCopy = input.forecastWhyCopyKey
            ?: input.forecastStatus?.let { "dashboard.forecast.why.${it.wireId}" }

        return GoalDashboardSceneModel(
            goalId = input.goal.id,
            goalLifecycle = lifecycle,
            currency = input.goal.currency,
            generatedAt = input.generatedAt,
            freshness = input.freshness,
            freshnessUpdatedAt = input.freshnessUpdatedAt,
            freshnessReason = input.freshnessReason,
            snapshot = SnapshotSlice(
                moduleState = snapshotModuleState,
                currentAmount = input.currentAmount,
                targetAmount = input.targetAmount,
                remainingAmount = input.remainingAmount,
                progressRatio = input.progressRatio,
                daysRemaining = input.daysRemaining,
                status = input.forecastStatus,
                lastUpdatedAt = input.freshnessUpdatedAt
            ),
            nextAction = nextAction,
            forecastRisk = ForecastRiskSlice(
                moduleState = forecastModuleState,
                status = input.forecastStatus,
                assumptionWindowDays = input.assumptionWindowDays,
                confidence = input.forecastConfidence,
                updatedAt = input.forecastUpdatedAt ?: input.freshnessUpdatedAt,
                targetDate = input.goal.deadline.atStartOfDay(java.time.ZoneOffset.UTC).toInstant(),
                projectedAmount = input.projectedAmount,
                whyStatusCopyKey = forecastWhyCopy,
                errorReasonCode = input.forecastErrorReasonCode
            ),
            contributionActivity = ContributionActivitySlice(
                moduleState = contributionModuleState,
                monthContributionSum = input.monthContributionSum,
                recentRows = input.recentRows,
                lastContributionAt = input.lastContributionAt
            ),
            allocationHealth = AllocationHealthSlice(
                moduleState = allocationModuleState,
                overAllocated = input.overAllocated,
                concentrationRatio = input.concentrationRatio,
                topAssets = input.topAssets,
                warningCopyKey = input.allocationWarningCopyKey
            ),
            utilities = UtilitiesSlice(
                moduleState = utilitiesModuleState,
                actions = utilityActions,
                legacyWidgetPrefsApplied = input.legacyWidgetPrefsApplied
            ),
            telemetryContext = DashboardTelemetryContext(
                source = "goal_dashboard_screen",
                generatedAt = input.generatedAt
            )
        )
    }

    private fun moduleStateFromFreshness(freshness: DataFreshnessState): GoalDashboardModuleState {
        return when (freshness) {
            DataFreshnessState.FRESH -> GoalDashboardModuleState.READY
            DataFreshnessState.STALE -> GoalDashboardModuleState.STALE
            DataFreshnessState.HARD_ERROR -> GoalDashboardModuleState.ERROR
        }
    }

    private fun defaultUtilityActions(): List<DashboardAction> {
        return listOf(
            DashboardAction(
                id = "add_asset",
                title = "Add Asset",
                copyKey = "dashboard.utilities.addAsset",
                systemImage = "plus.circle.fill"
            ),
            DashboardAction(
                id = "add_contribution",
                title = "Add Contribution",
                copyKey = "dashboard.utilities.addContribution",
                systemImage = "arrow.down.circle.fill"
            ),
            DashboardAction(
                id = "edit_goal",
                title = "Edit Goal",
                copyKey = "dashboard.utilities.editGoal",
                systemImage = "pencil.circle.fill"
            ),
            DashboardAction(
                id = "view_history",
                title = "View History",
                copyKey = "dashboard.utilities.viewHistory",
                systemImage = "clock.arrow.circlepath"
            )
        )
    }
}
