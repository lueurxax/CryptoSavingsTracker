package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import java.math.BigDecimal
import java.time.Instant

enum class DataFreshnessState(val wireId: String) {
    FRESH("fresh"),
    STALE("stale"),
    HARD_ERROR("hardError");

    companion object {
        fun fromWireId(value: String): DataFreshnessState =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid freshness wireId: $value")
    }
}

enum class GoalDashboardLifecycleState(val wireId: String) {
    ACTIVE("active"),
    PAUSED("paused"),
    FINISHED("finished"),
    ARCHIVED("archived");

    companion object {
        fun fromWireId(value: String): GoalDashboardLifecycleState =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid lifecycle wireId: $value")
    }
}

enum class GoalDashboardModuleState(val wireId: String) {
    LOADING("loading"),
    READY("ready"),
    EMPTY("empty"),
    ERROR("error"),
    STALE("stale");

    companion object {
        fun fromWireId(value: String): GoalDashboardModuleState =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid moduleState wireId: $value")
    }
}

enum class GoalDashboardRiskStatus(val wireId: String) {
    ON_TRACK("on_track"),
    AT_RISK("at_risk"),
    OFF_TRACK("off_track");

    companion object {
        fun fromWireId(value: String): GoalDashboardRiskStatus =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid riskStatus wireId: $value")
    }
}

enum class GoalDashboardForecastConfidence(val wireId: String) {
    LOW("low"),
    MEDIUM("medium"),
    HIGH("high");

    companion object {
        fun fromWireId(value: String): GoalDashboardForecastConfidence =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid forecastConfidence wireId: $value")
    }
}

enum class GoalDashboardNextActionResolverState(val wireId: String) {
    HARD_ERROR("hard_error"),
    GOAL_FINISHED_OR_ARCHIVED("goal_finished_or_archived"),
    GOAL_PAUSED("goal_paused"),
    OVER_ALLOCATED("over_allocated"),
    NO_ASSETS("no_assets"),
    NO_CONTRIBUTIONS("no_contributions"),
    STALE_DATA("stale_data"),
    BEHIND_SCHEDULE("behind_schedule"),
    ON_TRACK("on_track");

    companion object {
        fun fromWireId(value: String): GoalDashboardNextActionResolverState =
            entries.firstOrNull { it.wireId == value }
                ?: error("Invalid resolverState wireId: $value")
    }
}

data class DashboardTelemetryContext(
    val source: String,
    val generatedAt: Instant
)

data class DashboardCTA(
    val id: String,
    val title: String,
    val copyKey: String,
    val systemImage: String
)

data class DiagnosticsPayload(
    val reasonCode: String,
    val lastSuccessfulRefreshAt: Instant?,
    val nextStepCopyKey: String,
    val userMessage: String
)

data class SnapshotSlice(
    val moduleState: GoalDashboardModuleState,
    val currentAmount: BigDecimal,
    val targetAmount: BigDecimal,
    val remainingAmount: BigDecimal,
    val progressRatio: Double,
    val daysRemaining: Int?,
    val status: GoalDashboardRiskStatus?,
    val lastUpdatedAt: Instant?
)

data class NextActionSlice(
    val resolverState: GoalDashboardNextActionResolverState,
    val moduleState: GoalDashboardModuleState,
    val primaryCta: DashboardCTA,
    val secondaryCta: DashboardCTA?,
    val reasonCopyKey: String,
    val isBlocking: Boolean,
    val diagnostics: DiagnosticsPayload?
)

data class ForecastRiskSlice(
    val moduleState: GoalDashboardModuleState,
    val status: GoalDashboardRiskStatus?,
    val assumptionWindowDays: Int?,
    val confidence: GoalDashboardForecastConfidence?,
    val updatedAt: Instant?,
    val targetDate: Instant,
    val projectedAmount: BigDecimal?,
    val whyStatusCopyKey: String?,
    val errorReasonCode: String?
)

data class ActivityRow(
    val id: String,
    val assetCurrency: String,
    val amount: BigDecimal,
    val date: Instant,
    val note: String?
)

data class ContributionActivitySlice(
    val moduleState: GoalDashboardModuleState,
    val monthContributionSum: BigDecimal,
    val recentRows: List<ActivityRow>,
    val lastContributionAt: Instant?
)

data class AssetWeight(
    val assetId: String,
    val assetCurrency: String,
    val amount: BigDecimal,
    val weightRatio: Double
)

data class AllocationHealthSlice(
    val moduleState: GoalDashboardModuleState,
    val overAllocated: Boolean,
    val concentrationRatio: Double?,
    val topAssets: List<AssetWeight>,
    val warningCopyKey: String?
)

data class DashboardAction(
    val id: String,
    val title: String,
    val copyKey: String,
    val systemImage: String
)

data class UtilitiesSlice(
    val moduleState: GoalDashboardModuleState,
    val actions: List<DashboardAction>,
    val legacyWidgetPrefsApplied: Boolean
)

data class GoalDashboardSceneModel(
    val goalId: String,
    val goalLifecycle: GoalDashboardLifecycleState,
    val currency: String,
    val generatedAt: Instant,
    val freshness: DataFreshnessState,
    val freshnessUpdatedAt: Instant?,
    val freshnessReason: String?,
    val snapshot: SnapshotSlice,
    val nextAction: NextActionSlice,
    val forecastRisk: ForecastRiskSlice,
    val contributionActivity: ContributionActivitySlice,
    val allocationHealth: AllocationHealthSlice,
    val utilities: UtilitiesSlice,
    val telemetryContext: DashboardTelemetryContext
)

fun GoalLifecycleStatus.toDashboardLifecycleState(): GoalDashboardLifecycleState {
    return when (this) {
        GoalLifecycleStatus.ACTIVE -> GoalDashboardLifecycleState.ACTIVE
        GoalLifecycleStatus.CANCELLED -> GoalDashboardLifecycleState.PAUSED
        GoalLifecycleStatus.FINISHED -> GoalDashboardLifecycleState.FINISHED
        GoalLifecycleStatus.DELETED -> GoalDashboardLifecycleState.ARCHIVED
    }
}

object GoalDashboardModuleContract {
    val moduleIds: List<String> = listOf(
        "goal_snapshot",
        "next_action",
        "forecast_risk",
        "contribution_activity",
        "allocation_health",
        "utilities"
    )

    val stateIds: List<String> = GoalDashboardModuleState.entries.map { it.wireId }
    val resolverStateIds: List<String> = GoalDashboardNextActionResolverState.entries.map { it.wireId }
    val statusChipIds: List<String> = GoalDashboardRiskStatus.entries.map { it.wireId }
    val copyKeys: List<String> = listOf(
        "dashboard.nextAction.hardError.reason",
        "dashboard.nextAction.hardError.nextStep",
        "dashboard.nextAction.finished.reason",
        "dashboard.nextAction.paused.reason",
        "dashboard.nextAction.overAllocated.reason",
        "dashboard.nextAction.noAssets.reason",
        "dashboard.nextAction.noContributions.reason",
        "dashboard.nextAction.stale.reason",
        "dashboard.nextAction.behind.reason",
        "dashboard.nextAction.onTrack.reason"
    )
}
