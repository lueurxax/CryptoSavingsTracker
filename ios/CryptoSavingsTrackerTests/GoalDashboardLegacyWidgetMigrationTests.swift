//
//  GoalDashboardLegacyWidgetMigrationTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalDashboardLegacyWidgetMigrationTests {
    @Test("Malformed legacy widgets payload resets to default without crash")
    func malformedPayloadFallsBack() {
        let result = GoalDashboardLegacyWidgetMigration.migrate(widgetsJSON: "{invalid")

        #expect(result.utilityActionOrder == GoalDashboardContract.defaultUtilityActionOrder)
        #expect(result.applied == false)
        #expect(result.resetToDefaultPreset == true)
    }

    @Test("Known widgets map to utility ordering")
    func knownWidgetsMapToUtilitiesOrder() {
        let json = """
        [
          { "id": "00000000-0000-0000-0000-000000000001", "type": "Asset Composition", "size": "medium", "position": 0 },
          { "id": "00000000-0000-0000-0000-000000000002", "type": "Forecast", "size": "full", "position": 1 },
          { "id": "00000000-0000-0000-0000-000000000003", "type": "Summary Stats", "size": "medium", "position": 2 }
        ]
        """

        let result = GoalDashboardLegacyWidgetMigration.migrate(widgetsJSON: json)

        #expect(result.applied == true)
        #expect(result.utilityActionOrder.prefix(3) == ["add_asset", "add_contribution", "edit_goal"])
    }
}
