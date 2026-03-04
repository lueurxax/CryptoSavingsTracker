//
//  GoalDashboardSceneModel.swift
//  CryptoSavingsTracker
//
//  Canonical scene contract for Goal Dashboard v2.
//

import Foundation

enum DataFreshnessState: String, Codable, CaseIterable, Sendable {
    case fresh
    case stale
    case hardError
}

enum GoalDashboardLifecycleState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case finished
    case archived
}

enum GoalDashboardModuleState: String, Codable, CaseIterable, Sendable {
    case loading
    case ready
    case empty
    case error
    case stale
}

enum GoalDashboardRiskStatus: String, Codable, CaseIterable, Sendable {
    case onTrack = "on_track"
    case atRisk = "at_risk"
    case offTrack = "off_track"
}

enum GoalDashboardForecastConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

enum GoalDashboardNextActionResolverState: String, Codable, CaseIterable, Sendable {
    case hardError = "hard_error"
    case goalFinishedOrArchived = "goal_finished_or_archived"
    case goalPaused = "goal_paused"
    case overAllocated = "over_allocated"
    case noAssets = "no_assets"
    case noContributions = "no_contributions"
    case staleData = "stale_data"
    case behindSchedule = "behind_schedule"
    case onTrack = "on_track"
}

struct DashboardTelemetryContext: Codable, Equatable, Sendable {
    let source: String
    let generatedAt: Date
}

struct DashboardCTA: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let copyKey: String
    let systemImage: String
}

struct DiagnosticsPayload: Codable, Equatable, Sendable {
    let reasonCode: String
    let lastSuccessfulRefreshAt: Date?
    let nextStepCopyKey: String
    let userMessage: String
}

struct SnapshotSlice: Codable, Equatable, Sendable {
    let moduleState: GoalDashboardModuleState
    let currentAmount: Decimal
    let targetAmount: Decimal
    let remainingAmount: Decimal
    let progressRatio: Double
    let daysRemaining: Int?
    let status: GoalDashboardRiskStatus?
    let lastUpdatedAt: Date?
}

struct NextActionSlice: Codable, Equatable, Sendable {
    let resolverState: GoalDashboardNextActionResolverState
    let moduleState: GoalDashboardModuleState
    let primaryCta: DashboardCTA
    let secondaryCta: DashboardCTA?
    let reasonCopyKey: String
    let isBlocking: Bool
    let diagnostics: DiagnosticsPayload?
}

struct ForecastRiskSlice: Codable, Equatable, Sendable {
    let moduleState: GoalDashboardModuleState
    let status: GoalDashboardRiskStatus?
    let assumptionWindowDays: Int?
    let confidence: GoalDashboardForecastConfidence?
    let updatedAt: Date?
    let targetDate: Date
    let projectedAmount: Decimal?
    let whyStatusCopyKey: String?
    let errorReasonCode: String?
}

struct ActivityRow: Codable, Equatable, Sendable {
    let id: UUID
    let assetCurrency: String
    let amount: Decimal
    let date: Date
    let note: String?
}

struct ContributionActivitySlice: Codable, Equatable, Sendable {
    let moduleState: GoalDashboardModuleState
    let monthContributionSum: Decimal
    let recentRows: [ActivityRow]
    let lastContributionAt: Date?
}

struct AssetWeight: Codable, Equatable, Sendable {
    let assetId: UUID
    let assetCurrency: String
    let amount: Decimal
    let weightRatio: Double
}

struct AllocationHealthSlice: Codable, Equatable, Sendable {
    let moduleState: GoalDashboardModuleState
    let overAllocated: Bool
    let concentrationRatio: Double?
    let topAssets: [AssetWeight]
    let warningCopyKey: String?
}

struct DashboardAction: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let copyKey: String
    let systemImage: String
}

struct UtilitiesSlice: Codable, Equatable, Sendable {
    let moduleState: GoalDashboardModuleState
    let actions: [DashboardAction]
    let legacyWidgetPrefsApplied: Bool
}

struct GoalDashboardSceneModel: Codable, Equatable, Sendable {
    let goalId: UUID
    let goalLifecycle: GoalDashboardLifecycleState
    let currency: String
    let generatedAt: Date
    let freshness: DataFreshnessState
    let freshnessUpdatedAt: Date?
    let freshnessReason: String?

    let snapshot: SnapshotSlice
    let nextAction: NextActionSlice
    let forecastRisk: ForecastRiskSlice
    let contributionActivity: ContributionActivitySlice
    let allocationHealth: AllocationHealthSlice
    let utilities: UtilitiesSlice

    let telemetryContext: DashboardTelemetryContext
}

extension GoalDashboardLifecycleState {
    init(goalLifecycleStatus: GoalLifecycleStatus) {
        switch goalLifecycleStatus {
        case .active:
            self = .active
        case .cancelled:
            self = .paused
        case .finished:
            self = .finished
        case .deleted:
            self = .archived
        }
    }
}
