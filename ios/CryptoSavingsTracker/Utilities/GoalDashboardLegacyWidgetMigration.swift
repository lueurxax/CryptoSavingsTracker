//
//  GoalDashboardLegacyWidgetMigration.swift
//  CryptoSavingsTracker
//

import Foundation

struct GoalDashboardLegacyWidgetMigrationResult: Equatable, Sendable {
    let utilityActionOrder: [String]
    let applied: Bool
    let resetToDefaultPreset: Bool
}

enum GoalDashboardLegacyWidgetMigration {
    static func migrate(widgetsJSON: String) -> GoalDashboardLegacyWidgetMigrationResult {
        let defaultOrder = GoalDashboardContract.defaultUtilityActionOrder
        guard !widgetsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return GoalDashboardLegacyWidgetMigrationResult(
                utilityActionOrder: defaultOrder,
                applied: false,
                resetToDefaultPreset: false
            )
        }

        guard let data = widgetsJSON.data(using: .utf8) else {
            AppLog.warning("dashboard_widgets: invalid UTF-8, reset to default preset", category: .ui)
            return GoalDashboardLegacyWidgetMigrationResult(
                utilityActionOrder: defaultOrder,
                applied: false,
                resetToDefaultPreset: true
            )
        }

        guard let rawItems = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            AppLog.warning("dashboard_widgets: malformed JSON, reset to default preset", category: .ui)
            return GoalDashboardLegacyWidgetMigrationResult(
                utilityActionOrder: defaultOrder,
                applied: false,
                resetToDefaultPreset: true
            )
        }

        var mapped: [String] = []
        var resetNeeded = false
        let sorted = rawItems.sorted { lhs, rhs in
            let lPos = lhs["position"] as? Int ?? Int.max
            let rPos = rhs["position"] as? Int ?? Int.max
            return lPos < rPos
        }

        for item in sorted {
            guard let type = item["type"] as? String else {
                resetNeeded = true
                continue
            }
            if let size = item["size"] as? String,
               !["small", "medium", "large", "full"].contains(size) {
                resetNeeded = true
            }
            if let position = item["position"] as? Int, position < 0 {
                resetNeeded = true
            }

            guard let actionID = mappedActionID(forLegacyWidgetType: type) else {
                AppLog.warning("dashboard_widgets: unknown widget type '\(type)' ignored", category: .ui)
                continue
            }
            if !mapped.contains(actionID) {
                mapped.append(actionID)
            }
        }

        let ordered = mapped + defaultOrder.filter { !mapped.contains($0) }
        return GoalDashboardLegacyWidgetMigrationResult(
            utilityActionOrder: ordered,
            applied: !mapped.isEmpty,
            resetToDefaultPreset: resetNeeded
        )
    }

    private static func mappedActionID(forLegacyWidgetType type: String) -> String? {
        switch type {
        case DashboardWidgetType.progressRing.rawValue:
            return "review_activity"
        case DashboardWidgetType.lineChart.rawValue:
            return "review_activity"
        case DashboardWidgetType.stackedBar.rawValue:
            return "add_asset"
        case DashboardWidgetType.forecast.rawValue:
            return "add_contribution"
        case DashboardWidgetType.heatmap.rawValue:
            return "add_contribution"
        case DashboardWidgetType.summary.rawValue:
            return "edit_goal"
        default:
            return nil
        }
    }
}
