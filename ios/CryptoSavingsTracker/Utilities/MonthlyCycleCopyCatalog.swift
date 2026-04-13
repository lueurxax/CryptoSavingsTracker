//
//  MonthlyCycleCopyCatalog.swift
//  CryptoSavingsTracker
//
//  User-facing copy catalog for monthly cycle action blocking/recovery reasons.
//

import Foundation

enum MonthlyCycleCopyCatalog {
    static func startBlockedMissingPlan() -> String {
        "Complete planning first before starting tracking."
    }

    static func startBlockedAlreadyExecuting(month: String) -> String {
        "Tracking is already active for \(month)."
    }

    static func startBlockedClosedMonth() -> String {
        "This month is already closed."
    }

    static func finishBlockedNoExecuting() -> String {
        "No active month is being tracked."
    }

    static func undoStartExpired(month: String) -> String {
        "Back to Planning is no longer available for \(month) because the undo window ended."
    }

    static func undoCompletionExpired(month: String) -> String {
        "Undo Finish is no longer available for \(month) because the undo window ended."
    }

    static func recordConflict() -> String {
        "Monthly state is out of sync. Refresh Monthly Planning and try again."
    }
}
