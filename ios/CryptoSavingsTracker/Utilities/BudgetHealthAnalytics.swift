//
//  BudgetHealthAnalytics.swift
//  CryptoSavingsTracker
//
//  Lightweight telemetry for Budget Health Card (Section 11 of proposal).
//  Logs through AppLogger; wire to a real backend when one is adopted.
//

import Foundation

enum BudgetHealthAnalytics {

    enum Event: String {
        case cardImpression        = "budget_health_card_impression"
        case primaryCTATap         = "budget_health_primary_cta_tap"
        case editTap               = "budget_health_edit_tap"
        case stateChanged          = "budget_health_state_changed"
        case collapsedStripTap     = "budget_health_collapsed_strip_tap"
    }

    static func log(_ event: Event, properties: [String: String] = [:]) {
        let props = properties.isEmpty
            ? ""
            : " " + properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        AppLog.info("[\(event.rawValue)]\(props)", category: .monthlyPlanning)
    }

    // MARK: - Convenience helpers

    static func logImpression(state: BudgetHealthState, context: String = "expanded") {
        log(.cardImpression, properties: [
            "state": stateLabel(state),
            "scroll_context": context
        ])
    }

    static func logPrimaryCTATap(state: BudgetHealthState) {
        log(.primaryCTATap, properties: [
            "state": stateLabel(state),
            "action": state.primaryActionTitle
        ])
    }

    static func logEditTap() {
        log(.editTap)
    }

    static func logStateChanged(from oldState: BudgetHealthState, to newState: BudgetHealthState) {
        log(.stateChanged, properties: [
            "from_state": stateLabel(oldState),
            "to_state": stateLabel(newState)
        ])
    }

    static func logCollapsedStripTap(state: BudgetHealthState) {
        log(.collapsedStripTap, properties: [
            "state": stateLabel(state),
            "action": state.collapsedActionTitle
        ])
    }

    // MARK: - Private

    private static func stateLabel(_ state: BudgetHealthState) -> String {
        switch state {
        case .noBudget:          return "noBudget"
        case .healthy:           return "healthy"
        case .notApplied:        return "notApplied"
        case .needsRecalculation: return "needsRecalculation"
        case .atRisk:            return "atRisk"
        case .severeRisk:        return "severeRisk"
        case .staleFX:           return "staleFX"
        }
    }
}
