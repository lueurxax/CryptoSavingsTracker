//
//  GoalDashboardNavigationContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing

struct GoalDashboardNavigationContractTests {
    @Test("iOS canonical entry uses GoalDetail -> GoalDashboardScreen")
    func canonicalEntryFromGoalDetail() throws {
        let root = repositoryRoot()
        let detailContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift"
        )

        #expect(detailContainer.contains("GoalDashboardScreen(goal: goal)"))
        #expect(detailContainer.contains(".tag(DetailViewType.dashboard)"))
    }

    @Test("iOS production path has no runtime fallback flag for goal dashboard")
    func noRuntimeFallbackFlagInGoalDashboardPath() throws {
        let root = repositoryRoot()
        let detailContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift"
        )
        let goalDashboardScreen = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift"
        )
        let dashboardAdapter = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/DashboardViewForGoal.swift"
        )

        #expect(!detailContainer.contains("goal_dashboard_v2_enabled"))
        #expect(!goalDashboardScreen.contains("goal_dashboard_v2_enabled"))
        #expect(!dashboardAdapter.contains("goal_dashboard_v2_enabled"))
        #expect(dashboardAdapter.contains("GoalDashboardScreen(goal: goal)"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
