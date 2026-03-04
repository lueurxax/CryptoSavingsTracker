//
//  BudgetPlanAnalytics.swift
//  CryptoSavingsTracker
//
//  Lightweight telemetry for monthly savings budget flow hardening.
//

import Foundation

enum BudgetPlanAnalytics {
    enum Event: String {
        case snapshotStaleResultDropped = "budget_snapshot_stale_result_dropped"
        case parseFailure = "budget_parse_failure"
        case parseFailureType = "budget_parse_failure_type"
        case saveBlockedReasonShown = "budget_save_blocked_reason_shown"
        case useMinimumTap = "budget_use_minimum_tap"
        case blockedRatesImpression = "budget_blocked_rates_impression"
        case displayValidationMismatchDetected = "budget_display_validation_mismatch_detected"
    }

    static func log(_ event: Event, properties: [String: String] = [:]) {
        let payload = properties
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")

        let suffix = payload.isEmpty ? "" : " \(payload)"
        AppLog.info("[\(event.rawValue)]\(suffix)", category: .monthlyPlanning)
    }
}
