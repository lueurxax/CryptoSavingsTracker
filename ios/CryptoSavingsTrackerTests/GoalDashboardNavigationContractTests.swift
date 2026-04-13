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

    @Test("iOS goals list route resolves to active shell and not legacy view constructor")
    func goalsListRouteUsesActiveContentShell() throws {
        let root = repositoryRoot()
        let coordinator = try readSource(
            root,
            "ios/CryptoSavingsTracker/Navigation/Coordinator.swift"
        )

        #expect(coordinator.contains("case .goalsList:"))
        #expect(coordinator.contains("ContentView()"))
        #expect(!coordinator.contains("GoalsListView()"))
    }

    @Test("iOS goal detail route stays on active DetailContainer shell")
    func goalDetailRouteUsesDetailContainerShell() throws {
        let root = repositoryRoot()
        let coordinator = try readSource(
            root,
            "ios/CryptoSavingsTracker/Navigation/Coordinator.swift"
        )

        #expect(coordinator.contains("case .goalDetail(let goal):"))
        #expect(
            coordinator.contains("DetailContainerView(goal: goal, selectedView: .constant(.details))")
        )
        #expect(!coordinator.contains("GoalDetailView("))
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
