package com.xax.CryptoSavingsTracker.presentation.dashboard

import java.math.BigDecimal
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class GoalDashboardSceneWireModel(
    val goalId: String,
    val goalLifecycle: String,
    val currency: String,
    val generatedAt: String,
    val freshness: String,
    val freshnessUpdatedAt: String? = null,
    val freshnessReason: String? = null,
    val snapshot: WireSnapshotSlice,
    val nextAction: WireNextActionSlice,
    val forecastRisk: WireForecastRiskSlice,
    val contributionActivity: WireContributionActivitySlice,
    val allocationHealth: WireAllocationHealthSlice,
    val utilities: WireUtilitiesSlice,
    val telemetryContext: WireTelemetryContext
)

@Serializable
data class WireDashboardCTA(
    val id: String,
    val title: String,
    val copyKey: String,
    val systemImage: String
)

@Serializable
data class WireDiagnosticsPayload(
    val reasonCode: String,
    val lastSuccessfulRefreshAt: String? = null,
    val nextStepCopyKey: String,
    val userMessage: String
)

@Serializable
data class WireSnapshotSlice(
    val moduleState: String,
    val currentAmount: String,
    val targetAmount: String,
    val remainingAmount: String,
    val progressRatio: Double,
    val daysRemaining: Int? = null,
    val status: String? = null,
    val lastUpdatedAt: String? = null
)

@Serializable
data class WireNextActionSlice(
    val resolverState: String,
    val moduleState: String,
    val primaryCta: WireDashboardCTA,
    val secondaryCta: WireDashboardCTA? = null,
    val reasonCopyKey: String,
    val isBlocking: Boolean,
    val diagnostics: WireDiagnosticsPayload? = null
)

@Serializable
data class WireForecastRiskSlice(
    val moduleState: String,
    val status: String? = null,
    val assumptionWindowDays: Int? = null,
    val confidence: String? = null,
    val updatedAt: String? = null,
    val targetDate: String,
    val projectedAmount: String? = null,
    val whyStatusCopyKey: String? = null,
    val errorReasonCode: String? = null
)

@Serializable
data class WireActivityRow(
    val id: String,
    val assetCurrency: String,
    val amount: String,
    val date: String,
    val note: String? = null
)

@Serializable
data class WireContributionActivitySlice(
    val moduleState: String,
    val monthContributionSum: String,
    val recentRows: List<WireActivityRow>,
    val lastContributionAt: String? = null
)

@Serializable
data class WireAssetWeight(
    val assetId: String,
    val assetCurrency: String,
    val amount: String,
    val weightRatio: Double
)

@Serializable
data class WireAllocationHealthSlice(
    val moduleState: String,
    val overAllocated: Boolean,
    val concentrationRatio: Double? = null,
    val topAssets: List<WireAssetWeight>,
    val warningCopyKey: String? = null
)

@Serializable
data class WireDashboardAction(
    val id: String,
    val title: String,
    val copyKey: String,
    val systemImage: String
)

@Serializable
data class WireUtilitiesSlice(
    val moduleState: String,
    val actions: List<WireDashboardAction>,
    val legacyWidgetPrefsApplied: Boolean
)

@Serializable
data class WireTelemetryContext(
    val source: String,
    val generatedAt: String
)

object GoalDashboardSceneWireCodec {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
    }

    fun encodeScene(scene: GoalDashboardSceneModel): String {
        return json.encodeToString(toWireModel(scene))
    }

    fun decodeScene(payload: String): GoalDashboardSceneModel {
        val wire = json.decodeFromString<GoalDashboardSceneWireModel>(payload)
        return fromWireModel(wire)
    }

    fun decodeWireModel(payload: String): GoalDashboardSceneWireModel {
        return json.decodeFromString(payload)
    }

    fun toWireModel(scene: GoalDashboardSceneModel): GoalDashboardSceneWireModel {
        return GoalDashboardSceneWireModel(
            goalId = scene.goalId,
            goalLifecycle = scene.goalLifecycle.wireId,
            currency = scene.currency,
            generatedAt = GoalDashboardWireCodec.encodeDate(scene.generatedAt),
            freshness = scene.freshness.wireId,
            freshnessUpdatedAt = scene.freshnessUpdatedAt?.let(GoalDashboardWireCodec::encodeDate),
            freshnessReason = scene.freshnessReason,
            snapshot = WireSnapshotSlice(
                moduleState = scene.snapshot.moduleState.wireId,
                currentAmount = GoalDashboardWireCodec.encodeDecimal(scene.snapshot.currentAmount),
                targetAmount = GoalDashboardWireCodec.encodeDecimal(scene.snapshot.targetAmount),
                remainingAmount = GoalDashboardWireCodec.encodeDecimal(scene.snapshot.remainingAmount),
                progressRatio = scene.snapshot.progressRatio,
                daysRemaining = scene.snapshot.daysRemaining,
                status = scene.snapshot.status?.wireId,
                lastUpdatedAt = scene.snapshot.lastUpdatedAt?.let(GoalDashboardWireCodec::encodeDate)
            ),
            nextAction = WireNextActionSlice(
                resolverState = scene.nextAction.resolverState.wireId,
                moduleState = scene.nextAction.moduleState.wireId,
                primaryCta = scene.nextAction.primaryCta.toWireCTA(),
                secondaryCta = scene.nextAction.secondaryCta?.toWireCTA(),
                reasonCopyKey = scene.nextAction.reasonCopyKey,
                isBlocking = scene.nextAction.isBlocking,
                diagnostics = scene.nextAction.diagnostics?.let {
                    WireDiagnosticsPayload(
                        reasonCode = it.reasonCode,
                        lastSuccessfulRefreshAt = it.lastSuccessfulRefreshAt?.let(GoalDashboardWireCodec::encodeDate),
                        nextStepCopyKey = it.nextStepCopyKey,
                        userMessage = it.userMessage
                    )
                }
            ),
            forecastRisk = WireForecastRiskSlice(
                moduleState = scene.forecastRisk.moduleState.wireId,
                status = scene.forecastRisk.status?.wireId,
                assumptionWindowDays = scene.forecastRisk.assumptionWindowDays,
                confidence = scene.forecastRisk.confidence?.wireId,
                updatedAt = scene.forecastRisk.updatedAt?.let(GoalDashboardWireCodec::encodeDate),
                targetDate = GoalDashboardWireCodec.encodeDate(scene.forecastRisk.targetDate),
                projectedAmount = scene.forecastRisk.projectedAmount?.let(GoalDashboardWireCodec::encodeDecimal),
                whyStatusCopyKey = scene.forecastRisk.whyStatusCopyKey,
                errorReasonCode = scene.forecastRisk.errorReasonCode
            ),
            contributionActivity = WireContributionActivitySlice(
                moduleState = scene.contributionActivity.moduleState.wireId,
                monthContributionSum = GoalDashboardWireCodec.encodeDecimal(scene.contributionActivity.monthContributionSum),
                recentRows = scene.contributionActivity.recentRows.map {
                    WireActivityRow(
                        id = it.id,
                        assetCurrency = it.assetCurrency,
                        amount = GoalDashboardWireCodec.encodeDecimal(it.amount),
                        date = GoalDashboardWireCodec.encodeDate(it.date),
                        note = it.note
                    )
                },
                lastContributionAt = scene.contributionActivity.lastContributionAt?.let(GoalDashboardWireCodec::encodeDate)
            ),
            allocationHealth = WireAllocationHealthSlice(
                moduleState = scene.allocationHealth.moduleState.wireId,
                overAllocated = scene.allocationHealth.overAllocated,
                concentrationRatio = scene.allocationHealth.concentrationRatio,
                topAssets = scene.allocationHealth.topAssets.map {
                    WireAssetWeight(
                        assetId = it.assetId,
                        assetCurrency = it.assetCurrency,
                        amount = GoalDashboardWireCodec.encodeDecimal(it.amount),
                        weightRatio = it.weightRatio
                    )
                },
                warningCopyKey = scene.allocationHealth.warningCopyKey
            ),
            utilities = WireUtilitiesSlice(
                moduleState = scene.utilities.moduleState.wireId,
                actions = scene.utilities.actions.map {
                    WireDashboardAction(
                        id = it.id,
                        title = it.title,
                        copyKey = it.copyKey,
                        systemImage = it.systemImage
                    )
                },
                legacyWidgetPrefsApplied = scene.utilities.legacyWidgetPrefsApplied
            ),
            telemetryContext = WireTelemetryContext(
                source = scene.telemetryContext.source,
                generatedAt = GoalDashboardWireCodec.encodeDate(scene.telemetryContext.generatedAt)
            )
        )
    }

    fun fromWireModel(model: GoalDashboardSceneWireModel): GoalDashboardSceneModel {
        return GoalDashboardSceneModel(
            goalId = model.goalId,
            goalLifecycle = GoalDashboardLifecycleState.fromWireId(model.goalLifecycle),
            currency = model.currency,
            generatedAt = GoalDashboardWireCodec.decodeDate(model.generatedAt),
            freshness = DataFreshnessState.fromWireId(model.freshness),
            freshnessUpdatedAt = model.freshnessUpdatedAt?.let(GoalDashboardWireCodec::decodeDate),
            freshnessReason = model.freshnessReason,
            snapshot = SnapshotSlice(
                moduleState = GoalDashboardModuleState.fromWireId(model.snapshot.moduleState),
                currentAmount = GoalDashboardWireCodec.decodeDecimal(model.snapshot.currentAmount),
                targetAmount = GoalDashboardWireCodec.decodeDecimal(model.snapshot.targetAmount),
                remainingAmount = GoalDashboardWireCodec.decodeDecimal(model.snapshot.remainingAmount),
                progressRatio = model.snapshot.progressRatio,
                daysRemaining = model.snapshot.daysRemaining,
                status = model.snapshot.status?.let(GoalDashboardRiskStatus::fromWireId),
                lastUpdatedAt = model.snapshot.lastUpdatedAt?.let(GoalDashboardWireCodec::decodeDate)
            ),
            nextAction = NextActionSlice(
                resolverState = GoalDashboardNextActionResolverState.fromWireId(model.nextAction.resolverState),
                moduleState = GoalDashboardModuleState.fromWireId(model.nextAction.moduleState),
                primaryCta = model.nextAction.primaryCta.toDomainCTA(),
                secondaryCta = model.nextAction.secondaryCta?.toDomainCTA(),
                reasonCopyKey = model.nextAction.reasonCopyKey,
                isBlocking = model.nextAction.isBlocking,
                diagnostics = model.nextAction.diagnostics?.let {
                    DiagnosticsPayload(
                        reasonCode = it.reasonCode,
                        lastSuccessfulRefreshAt = it.lastSuccessfulRefreshAt?.let(GoalDashboardWireCodec::decodeDate),
                        nextStepCopyKey = it.nextStepCopyKey,
                        userMessage = it.userMessage
                    )
                }
            ),
            forecastRisk = ForecastRiskSlice(
                moduleState = GoalDashboardModuleState.fromWireId(model.forecastRisk.moduleState),
                status = model.forecastRisk.status?.let(GoalDashboardRiskStatus::fromWireId),
                assumptionWindowDays = model.forecastRisk.assumptionWindowDays,
                confidence = model.forecastRisk.confidence?.let(GoalDashboardForecastConfidence::fromWireId),
                updatedAt = model.forecastRisk.updatedAt?.let(GoalDashboardWireCodec::decodeDate),
                targetDate = GoalDashboardWireCodec.decodeDate(model.forecastRisk.targetDate),
                projectedAmount = model.forecastRisk.projectedAmount?.let(GoalDashboardWireCodec::decodeDecimal),
                whyStatusCopyKey = model.forecastRisk.whyStatusCopyKey,
                errorReasonCode = model.forecastRisk.errorReasonCode
            ),
            contributionActivity = ContributionActivitySlice(
                moduleState = GoalDashboardModuleState.fromWireId(model.contributionActivity.moduleState),
                monthContributionSum = GoalDashboardWireCodec.decodeDecimal(model.contributionActivity.monthContributionSum),
                recentRows = model.contributionActivity.recentRows.map {
                    ActivityRow(
                        id = it.id,
                        assetCurrency = it.assetCurrency,
                        amount = GoalDashboardWireCodec.decodeDecimal(it.amount),
                        date = GoalDashboardWireCodec.decodeDate(it.date),
                        note = it.note
                    )
                },
                lastContributionAt = model.contributionActivity.lastContributionAt?.let(GoalDashboardWireCodec::decodeDate)
            ),
            allocationHealth = AllocationHealthSlice(
                moduleState = GoalDashboardModuleState.fromWireId(model.allocationHealth.moduleState),
                overAllocated = model.allocationHealth.overAllocated,
                concentrationRatio = model.allocationHealth.concentrationRatio,
                topAssets = model.allocationHealth.topAssets.map {
                    AssetWeight(
                        assetId = it.assetId,
                        assetCurrency = it.assetCurrency,
                        amount = GoalDashboardWireCodec.decodeDecimal(it.amount),
                        weightRatio = it.weightRatio
                    )
                },
                warningCopyKey = model.allocationHealth.warningCopyKey
            ),
            utilities = UtilitiesSlice(
                moduleState = GoalDashboardModuleState.fromWireId(model.utilities.moduleState),
                actions = model.utilities.actions.map {
                    DashboardAction(
                        id = it.id,
                        title = it.title,
                        copyKey = it.copyKey,
                        systemImage = it.systemImage
                    )
                },
                legacyWidgetPrefsApplied = model.utilities.legacyWidgetPrefsApplied
            ),
            telemetryContext = DashboardTelemetryContext(
                source = model.telemetryContext.source,
                generatedAt = GoalDashboardWireCodec.decodeDate(model.telemetryContext.generatedAt)
            )
        )
    }
}

private fun DashboardCTA.toWireCTA(): WireDashboardCTA {
    return WireDashboardCTA(
        id = id,
        title = title,
        copyKey = copyKey,
        systemImage = systemImage
    )
}

private fun WireDashboardCTA.toDomainCTA(): DashboardCTA {
    return DashboardCTA(
        id = id,
        title = title,
        copyKey = copyKey,
        systemImage = systemImage
    )
}
