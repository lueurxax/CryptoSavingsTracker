//
//  GoalDashboardContract.swift
//  CryptoSavingsTracker
//

import Foundation

enum GoalDashboardModuleID: String, CaseIterable, Sendable {
    case goalSnapshot = "goal_snapshot"
    case nextAction = "next_action"
    case forecastRisk = "forecast_risk"
    case contributionActivity = "contribution_activity"
    case allocationHealth = "allocation_health"
    case utilities = "utilities"
}

enum GoalDashboardContract {
    static let parityVersion = "1.0.0"

    static let resolverStateIDs: [String] = [
        GoalDashboardNextActionResolverState.hardError.rawValue,
        GoalDashboardNextActionResolverState.goalFinishedOrArchived.rawValue,
        GoalDashboardNextActionResolverState.goalPaused.rawValue,
        GoalDashboardNextActionResolverState.overAllocated.rawValue,
        GoalDashboardNextActionResolverState.noAssets.rawValue,
        GoalDashboardNextActionResolverState.noContributions.rawValue,
        GoalDashboardNextActionResolverState.staleData.rawValue,
        GoalDashboardNextActionResolverState.behindSchedule.rawValue,
        GoalDashboardNextActionResolverState.onTrack.rawValue
    ]

    static let statusChipIDs: [String] = [
        GoalDashboardRiskStatus.onTrack.rawValue,
        GoalDashboardRiskStatus.atRisk.rawValue,
        GoalDashboardRiskStatus.offTrack.rawValue
    ]

    static let nextActionReasonCopyKeys: [String] = [
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
    ]

    static let defaultUtilityActionOrder: [String] = [
        "add_asset",
        "add_contribution",
        "edit_goal",
        "view_history"
    ]
}
