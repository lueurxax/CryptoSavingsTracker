//
//  GoalDashboardSceneWireCodec.swift
//  CryptoSavingsTracker
//

import Foundation

enum GoalDashboardSceneWireCodecError: Error, LocalizedError {
    case invalidEnum(field: String, value: String)
    case invalidUUID(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidEnum(let field, let value):
            return "Invalid enum value for \(field): \(value)"
        case .invalidUUID(let field, let value):
            return "Invalid UUID value for \(field): \(value)"
        }
    }
}

struct GoalDashboardSceneWireModel: Codable, Equatable, Sendable {
    struct WireCTA: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let copyKey: String
        let systemImage: String
    }

    struct WireDiagnostics: Codable, Equatable, Sendable {
        let reasonCode: String
        let lastSuccessfulRefreshAt: String?
        let nextStepCopyKey: String
        let userMessage: String
    }

    struct WireSnapshotSlice: Codable, Equatable, Sendable {
        let moduleState: String
        let currentAmount: String
        let targetAmount: String
        let remainingAmount: String
        let progressRatio: Double
        let daysRemaining: Int?
        let status: String?
        let lastUpdatedAt: String?
    }

    struct WireNextActionSlice: Codable, Equatable, Sendable {
        let resolverState: String
        let moduleState: String
        let primaryCta: WireCTA
        let secondaryCta: WireCTA?
        let reasonCopyKey: String
        let isBlocking: Bool
        let diagnostics: WireDiagnostics?
    }

    struct WireForecastRiskSlice: Codable, Equatable, Sendable {
        let moduleState: String
        let status: String?
        let assumptionWindowDays: Int?
        let confidence: String?
        let updatedAt: String?
        let targetDate: String
        let projectedAmount: String?
        let whyStatusCopyKey: String?
        let errorReasonCode: String?
    }

    struct WireActivityRow: Codable, Equatable, Sendable {
        let id: String
        let assetCurrency: String
        let amount: String
        let date: String
        let note: String?
    }

    struct WireContributionActivitySlice: Codable, Equatable, Sendable {
        let moduleState: String
        let monthContributionSum: String
        let recentRows: [WireActivityRow]
        let lastContributionAt: String?
    }

    struct WireAssetWeight: Codable, Equatable, Sendable {
        let assetId: String
        let assetCurrency: String
        let amount: String
        let weightRatio: Double
    }

    struct WireAllocationHealthSlice: Codable, Equatable, Sendable {
        let moduleState: String
        let overAllocated: Bool
        let concentrationRatio: Double?
        let topAssets: [WireAssetWeight]
        let warningCopyKey: String?
    }

    struct WireUtilitiesSlice: Codable, Equatable, Sendable {
        let moduleState: String
        let actions: [WireCTA]
        let legacyWidgetPrefsApplied: Bool
    }

    struct WireTelemetryContext: Codable, Equatable, Sendable {
        let source: String
        let generatedAt: String
    }

    let goalId: String
    let goalLifecycle: String
    let currency: String
    let generatedAt: String
    let freshness: String
    let freshnessUpdatedAt: String?
    let freshnessReason: String?

    let snapshot: WireSnapshotSlice
    let nextAction: WireNextActionSlice
    let forecastRisk: WireForecastRiskSlice
    let contributionActivity: WireContributionActivitySlice
    let allocationHealth: WireAllocationHealthSlice
    let utilities: WireUtilitiesSlice
    let telemetryContext: WireTelemetryContext
}

enum GoalDashboardSceneWireCodec {
    static func encode(scene: GoalDashboardSceneModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(toWireModel(scene: scene))
    }

    static func decodeScene(data: Data) throws -> GoalDashboardSceneModel {
        let model = try decodeWireModel(data: data)
        return try fromWireModel(model)
    }

    static func decodeWireModel(data: Data) throws -> GoalDashboardSceneWireModel {
        try JSONDecoder().decode(GoalDashboardSceneWireModel.self, from: data)
    }

    static func toWireModel(scene: GoalDashboardSceneModel) -> GoalDashboardSceneWireModel {
        GoalDashboardSceneWireModel(
            goalId: scene.goalId.uuidString.lowercased(),
            goalLifecycle: scene.goalLifecycle.rawValue,
            currency: scene.currency,
            generatedAt: GoalDashboardWireCodec.encode(date: scene.generatedAt),
            freshness: scene.freshness.rawValue,
            freshnessUpdatedAt: scene.freshnessUpdatedAt.map(GoalDashboardWireCodec.encode(date:)),
            freshnessReason: scene.freshnessReason,
            snapshot: .init(
                moduleState: scene.snapshot.moduleState.rawValue,
                currentAmount: GoalDashboardWireCodec.encode(decimal: scene.snapshot.currentAmount),
                targetAmount: GoalDashboardWireCodec.encode(decimal: scene.snapshot.targetAmount),
                remainingAmount: GoalDashboardWireCodec.encode(decimal: scene.snapshot.remainingAmount),
                progressRatio: scene.snapshot.progressRatio,
                daysRemaining: scene.snapshot.daysRemaining,
                status: scene.snapshot.status?.rawValue,
                lastUpdatedAt: scene.snapshot.lastUpdatedAt.map(GoalDashboardWireCodec.encode(date:))
            ),
            nextAction: .init(
                resolverState: scene.nextAction.resolverState.rawValue,
                moduleState: scene.nextAction.moduleState.rawValue,
                primaryCta: toWireCTA(scene.nextAction.primaryCta),
                secondaryCta: scene.nextAction.secondaryCta.map(toWireCTA),
                reasonCopyKey: scene.nextAction.reasonCopyKey,
                isBlocking: scene.nextAction.isBlocking,
                diagnostics: scene.nextAction.diagnostics.map {
                    .init(
                        reasonCode: $0.reasonCode,
                        lastSuccessfulRefreshAt: $0.lastSuccessfulRefreshAt.map(GoalDashboardWireCodec.encode(date:)),
                        nextStepCopyKey: $0.nextStepCopyKey,
                        userMessage: $0.userMessage
                    )
                }
            ),
            forecastRisk: .init(
                moduleState: scene.forecastRisk.moduleState.rawValue,
                status: scene.forecastRisk.status?.rawValue,
                assumptionWindowDays: scene.forecastRisk.assumptionWindowDays,
                confidence: scene.forecastRisk.confidence?.rawValue,
                updatedAt: scene.forecastRisk.updatedAt.map(GoalDashboardWireCodec.encode(date:)),
                targetDate: GoalDashboardWireCodec.encode(date: scene.forecastRisk.targetDate),
                projectedAmount: scene.forecastRisk.projectedAmount.map(GoalDashboardWireCodec.encode(decimal:)),
                whyStatusCopyKey: scene.forecastRisk.whyStatusCopyKey,
                errorReasonCode: scene.forecastRisk.errorReasonCode
            ),
            contributionActivity: .init(
                moduleState: scene.contributionActivity.moduleState.rawValue,
                monthContributionSum: GoalDashboardWireCodec.encode(decimal: scene.contributionActivity.monthContributionSum),
                recentRows: scene.contributionActivity.recentRows.map {
                    .init(
                        id: $0.id.uuidString.lowercased(),
                        assetCurrency: $0.assetCurrency,
                        amount: GoalDashboardWireCodec.encode(decimal: $0.amount),
                        date: GoalDashboardWireCodec.encode(date: $0.date),
                        note: $0.note
                    )
                },
                lastContributionAt: scene.contributionActivity.lastContributionAt.map(GoalDashboardWireCodec.encode(date:))
            ),
            allocationHealth: .init(
                moduleState: scene.allocationHealth.moduleState.rawValue,
                overAllocated: scene.allocationHealth.overAllocated,
                concentrationRatio: scene.allocationHealth.concentrationRatio,
                topAssets: scene.allocationHealth.topAssets.map {
                    .init(
                        assetId: $0.assetId.uuidString.lowercased(),
                        assetCurrency: $0.assetCurrency,
                        amount: GoalDashboardWireCodec.encode(decimal: $0.amount),
                        weightRatio: $0.weightRatio
                    )
                },
                warningCopyKey: scene.allocationHealth.warningCopyKey
            ),
            utilities: .init(
                moduleState: scene.utilities.moduleState.rawValue,
                actions: scene.utilities.actions.map(toWireAction),
                legacyWidgetPrefsApplied: scene.utilities.legacyWidgetPrefsApplied
            ),
            telemetryContext: .init(
                source: scene.telemetryContext.source,
                generatedAt: GoalDashboardWireCodec.encode(date: scene.telemetryContext.generatedAt)
            )
        )
    }

    static func fromWireModel(_ model: GoalDashboardSceneWireModel) throws -> GoalDashboardSceneModel {
        GoalDashboardSceneModel(
            goalId: try uuid(model.goalId, field: "goalId"),
            goalLifecycle: try enumValue(model.goalLifecycle, field: "goalLifecycle"),
            currency: model.currency,
            generatedAt: try GoalDashboardWireCodec.decode(date: model.generatedAt),
            freshness: try enumValue(model.freshness, field: "freshness"),
            freshnessUpdatedAt: try model.freshnessUpdatedAt.map(GoalDashboardWireCodec.decode(date:)),
            freshnessReason: model.freshnessReason,
            snapshot: SnapshotSlice(
                moduleState: try enumValue(model.snapshot.moduleState, field: "snapshot.moduleState"),
                currentAmount: try GoalDashboardWireCodec.decode(decimal: model.snapshot.currentAmount),
                targetAmount: try GoalDashboardWireCodec.decode(decimal: model.snapshot.targetAmount),
                remainingAmount: try GoalDashboardWireCodec.decode(decimal: model.snapshot.remainingAmount),
                progressRatio: model.snapshot.progressRatio,
                daysRemaining: model.snapshot.daysRemaining,
                status: try model.snapshot.status.map { try enumValue($0, field: "snapshot.status") },
                lastUpdatedAt: try model.snapshot.lastUpdatedAt.map(GoalDashboardWireCodec.decode(date:))
            ),
            nextAction: NextActionSlice(
                resolverState: try enumValue(model.nextAction.resolverState, field: "nextAction.resolverState"),
                moduleState: try enumValue(model.nextAction.moduleState, field: "nextAction.moduleState"),
                primaryCta: fromWireCTA(model.nextAction.primaryCta),
                secondaryCta: model.nextAction.secondaryCta.map(fromWireCTA),
                reasonCopyKey: model.nextAction.reasonCopyKey,
                isBlocking: model.nextAction.isBlocking,
                diagnostics: try model.nextAction.diagnostics.map {
                    DiagnosticsPayload(
                        reasonCode: $0.reasonCode,
                        lastSuccessfulRefreshAt: try $0.lastSuccessfulRefreshAt.map(GoalDashboardWireCodec.decode(date:)),
                        nextStepCopyKey: $0.nextStepCopyKey,
                        userMessage: $0.userMessage
                    )
                }
            ),
            forecastRisk: ForecastRiskSlice(
                moduleState: try enumValue(model.forecastRisk.moduleState, field: "forecastRisk.moduleState"),
                status: try model.forecastRisk.status.map { try enumValue($0, field: "forecastRisk.status") },
                assumptionWindowDays: model.forecastRisk.assumptionWindowDays,
                confidence: try model.forecastRisk.confidence.map { try enumValue($0, field: "forecastRisk.confidence") },
                updatedAt: try model.forecastRisk.updatedAt.map(GoalDashboardWireCodec.decode(date:)),
                targetDate: try GoalDashboardWireCodec.decode(date: model.forecastRisk.targetDate),
                projectedAmount: try model.forecastRisk.projectedAmount.map(GoalDashboardWireCodec.decode(decimal:)),
                whyStatusCopyKey: model.forecastRisk.whyStatusCopyKey,
                errorReasonCode: model.forecastRisk.errorReasonCode
            ),
            contributionActivity: ContributionActivitySlice(
                moduleState: try enumValue(model.contributionActivity.moduleState, field: "contributionActivity.moduleState"),
                monthContributionSum: try GoalDashboardWireCodec.decode(decimal: model.contributionActivity.monthContributionSum),
                recentRows: try model.contributionActivity.recentRows.map {
                    ActivityRow(
                        id: try uuid($0.id, field: "contributionActivity.recentRows.id"),
                        assetCurrency: $0.assetCurrency,
                        amount: try GoalDashboardWireCodec.decode(decimal: $0.amount),
                        date: try GoalDashboardWireCodec.decode(date: $0.date),
                        note: $0.note
                    )
                },
                lastContributionAt: try model.contributionActivity.lastContributionAt.map(GoalDashboardWireCodec.decode(date:))
            ),
            allocationHealth: AllocationHealthSlice(
                moduleState: try enumValue(model.allocationHealth.moduleState, field: "allocationHealth.moduleState"),
                overAllocated: model.allocationHealth.overAllocated,
                concentrationRatio: model.allocationHealth.concentrationRatio,
                topAssets: try model.allocationHealth.topAssets.map {
                    AssetWeight(
                        assetId: try uuid($0.assetId, field: "allocationHealth.topAssets.assetId"),
                        assetCurrency: $0.assetCurrency,
                        amount: try GoalDashboardWireCodec.decode(decimal: $0.amount),
                        weightRatio: $0.weightRatio
                    )
                },
                warningCopyKey: model.allocationHealth.warningCopyKey
            ),
            utilities: UtilitiesSlice(
                moduleState: try enumValue(model.utilities.moduleState, field: "utilities.moduleState"),
                actions: model.utilities.actions.map {
                    DashboardAction(id: $0.id, title: $0.title, copyKey: $0.copyKey, systemImage: $0.systemImage)
                },
                legacyWidgetPrefsApplied: model.utilities.legacyWidgetPrefsApplied
            ),
            telemetryContext: DashboardTelemetryContext(
                source: model.telemetryContext.source,
                generatedAt: try GoalDashboardWireCodec.decode(date: model.telemetryContext.generatedAt)
            )
        )
    }

    private static func toWireCTA(_ cta: DashboardCTA) -> GoalDashboardSceneWireModel.WireCTA {
        .init(id: cta.id, title: cta.title, copyKey: cta.copyKey, systemImage: cta.systemImage)
    }

    private static func fromWireCTA(_ cta: GoalDashboardSceneWireModel.WireCTA) -> DashboardCTA {
        .init(id: cta.id, title: cta.title, copyKey: cta.copyKey, systemImage: cta.systemImage)
    }

    private static func toWireAction(_ action: DashboardAction) -> GoalDashboardSceneWireModel.WireCTA {
        .init(id: action.id, title: action.title, copyKey: action.copyKey, systemImage: action.systemImage)
    }

    private static func enumValue<T: RawRepresentable>(_ raw: String, field: String) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: raw) else {
            throw GoalDashboardSceneWireCodecError.invalidEnum(field: field, value: raw)
        }
        return value
    }

    private static func uuid(_ value: String, field: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw GoalDashboardSceneWireCodecError.invalidUUID(field: field, value: value)
        }
        return uuid
    }
}
