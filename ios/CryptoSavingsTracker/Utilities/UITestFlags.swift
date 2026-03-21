//
//  UITestFlags.swift
//  CryptoSavingsTracker
//
//  Helpers for UI test detection.
//

import Foundation

enum UITestFlags {
    private static let args = ProcessInfo.processInfo.arguments
    private static let environment = ProcessInfo.processInfo.environment
    private static var remainingSimulatedGoalSaveFailures = shouldSimulateGoalSaveFailure ? 1 : 0

    enum FamilyShareScenario: String {
        case ownerNotShared = "owner_not_shared"
        case ownerSharedActive = "owner_shared_active"
        case inviteePending = "invitee_pending"
        case inviteeActive = "invitee_active"
        case inviteeBlockedOwner = "invitee_blocked_owner"
        case inviteeMultiOwner = "invitee_multi_owner"
        case inviteeMultiOwnerUnresolved = "invitee_multi_owner_unresolved"
        case inviteeEmpty = "invitee_empty"
        case inviteeStale = "invitee_stale"
        case inviteeRevoked = "invitee_revoked"
        case inviteeRemoved = "invitee_removed"
        case inviteeUnavailable = "invitee_unavailable"
    }

    static var isEnabled: Bool {
        args.contains(where: { $0.hasPrefix("UITEST") })
    }

    static var shouldSeedGoals: Bool {
        args.contains("UITEST_SEED_GOALS")
    }

    static var shouldSeedManyGoals: Bool {
        args.contains("UITEST_SEED_MANY_GOALS")
    }

    static var shouldSeedSharedAsset: Bool {
        args.contains("UITEST_SEED_SHARED_ASSET")
    }

    static var shouldSeedBudgetShortfall: Bool {
        args.contains("UITEST_SEED_BUDGET_SHORTFALL")
    }

    static var shouldSeedStaleDrafts: Bool {
        args.contains("UITEST_SEED_STALE_DRAFTS")
    }

    static var shouldSimulateGoalSaveFailure: Bool {
        args.contains("UITEST_SIMULATE_GOAL_SAVE_FAILURE")
    }

    static var familyShareScenario: FamilyShareScenario? {
        guard let rawValue = environment["UITEST_FAMILY_SHARE_SCENARIO"] else {
            return nil
        }
        return FamilyShareScenario(rawValue: rawValue)
    }

    @MainActor
    static func consumeSimulatedGoalSaveFailureIfNeeded() -> Bool {
        guard shouldSimulateGoalSaveFailure, remainingSimulatedGoalSaveFailures > 0 else {
            return false
        }
        remainingSimulatedGoalSaveFailures -= 1
        return true
    }
}
