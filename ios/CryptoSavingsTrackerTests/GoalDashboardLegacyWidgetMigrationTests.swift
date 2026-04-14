//
//  GoalDashboardLegacyWidgetMigrationTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
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

    @Test("History-oriented legacy widgets remap to retained review activity")
    func historyWidgetsRemapToReviewActivity() {
        let json = """
        [
          { "id": "00000000-0000-0000-0000-000000000010", "type": "Progress Ring", "size": "medium", "position": 0 },
          { "id": "00000000-0000-0000-0000-000000000011", "type": "Balance History", "size": "large", "position": 1 }
        ]
        """

        let result = GoalDashboardLegacyWidgetMigration.migrate(widgetsJSON: json)

        #expect(result.applied == true)
        #expect(result.utilityActionOrder.first == "review_activity")
        #expect(!result.utilityActionOrder.contains("view_history"))
    }

    @Test("Scene assembler default utilities exclude hidden history CTA")
    func sceneAssemblerUsesRetainedUtilityActionsOnly() {
        let goal = Goal(
            name: "Assembler Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let viewModel = DashboardViewModel(container: nil)
        let scene = GoalDashboardSceneAssembler().assemble(
            goal: goal,
            dashboardViewModel: viewModel,
            generatedAt: Date(),
            lastSuccessfulRefreshAt: nil
        )

        let actionIDs = scene.utilities.actions.map(\.id)
        #expect(!actionIDs.contains("view_history"))
        #expect(actionIDs == GoalDashboardContract.defaultUtilityActionOrder)
        #expect(actionIDs.contains("review_activity"))
    }
}
