//
//  UITestFlags.swift
//  CryptoSavingsTracker
//
//  Helpers for UI test detection.
//

import Foundation

enum UITestFlags {
    private static let args = ProcessInfo.processInfo.arguments
    private static var remainingSimulatedGoalSaveFailures = shouldSimulateGoalSaveFailure ? 1 : 0

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

    @MainActor
    static func consumeSimulatedGoalSaveFailureIfNeeded() -> Bool {
        guard shouldSimulateGoalSaveFailure, remainingSimulatedGoalSaveFailures > 0 else {
            return false
        }
        remainingSimulatedGoalSaveFailures -= 1
        return true
    }
}
