//
//  GoalDashboardCopyCatalog.swift
//  CryptoSavingsTracker
//

import Foundation

enum GoalDashboardCopyCatalog {
    static let hardErrorUserMessage = "We could not refresh goal data. Retry now or review diagnostics."

    private static let values: [String: String] = [
        "dashboard.nextAction.hardError.reason": "Data sync failed. Retry now or inspect diagnostics.",
        "dashboard.nextAction.hardError.nextStep": "Retry sync first. If it still fails, verify connection and currency rates.",
        "dashboard.nextAction.finished.reason": "This goal is closed. Review activity or create a new goal.",
        "dashboard.nextAction.paused.reason": "This goal is paused. Resume tracking to continue progress.",
        "dashboard.nextAction.overAllocated.reason": "Allocated amounts exceed available balance on at least one asset.",
        "dashboard.nextAction.noAssets.reason": "No assets are linked to this goal yet.",
        "dashboard.nextAction.noContributions.reason": "No contributions were recorded this month.",
        "dashboard.nextAction.stale.reason": "Dashboard data is stale. Refresh before making decisions.",
        "dashboard.nextAction.behind.reason": "Current pace is below target. Add a contribution or edit the goal.",
        "dashboard.nextAction.onTrack.reason": "Goal is on track. Log the next contribution or review recent activity.",
        "dashboard.utilities.reviewActivity": "Review recent activity for this goal.",
        "dashboard.forecast.empty": "Forecast needs more activity data."
    ]

    static func text(for key: String) -> String {
        values[key] ?? key
    }

    // DASH-COPY-ERR-001: diagnostics copy quality checklist.
    static func diagnosticsChecklistViolations() -> [String] {
        var violations: [String] = []
        let reason = text(for: "dashboard.nextAction.hardError.reason")
        let nextStep = text(for: "dashboard.nextAction.hardError.nextStep")
        let userMessage = hardErrorUserMessage

        if containsInternalJargon(reason) || containsInternalJargon(nextStep) || containsInternalJargon(userMessage) {
            violations.append("copy contains internal jargon")
        }
        if reason.split(separator: ".").first?.isEmpty ?? true {
            violations.append("reason copy is missing a concise user-facing sentence")
        }
        if !startsWithVerb(nextStep) {
            violations.append("next-step guidance must start with a verb")
        }
        if containsVagueError(reason) && !startsWithVerb(nextStep) {
            violations.append("vague error copy must be followed by actionable next step")
        }
        return violations
    }

    private static func containsInternalJargon(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let forbidden = ["viewmodel", "service", "repository", "stacktrace", "nserror", "exception"]
        return forbidden.contains(where: lowered.contains)
    }

    private static func containsVagueError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("unknown error") || lowered.contains("unexpected issue")
    }

    private static func startsWithVerb(_ text: String) -> Bool {
        let verbs = ["retry", "verify", "check", "open", "refresh", "reconnect", "inspect"]
        guard let firstWord = text.split(separator: " ").first?.lowercased() else {
            return false
        }
        return verbs.contains(firstWord)
    }
}
