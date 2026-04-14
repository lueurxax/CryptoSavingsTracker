//
//  GoalDashboardNavigationContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing

struct GoalDashboardNavigationContractTests {
    @Test("Goal detail shell has no nested tab bar and keeps dashboard as a separate surface")
    func canonicalEntryFromGoalDetail() throws {
        let root = repositoryRoot()
        let detailContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift"
        )
        let dashboardAdapter = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/DashboardViewForGoal.swift"
        )

        #expect(!detailContainer.contains("TabView(selection: $selectedView)"))
        #expect(!detailContainer.contains(".tabItem {"))
        #expect(detailContainer.contains("switch selectedView"))
        #expect(detailContainer.contains("GoalDetailView(goal: goal)"))
        #expect(detailContainer.contains("DashboardViewForGoal(goal: goal)"))
        #expect(dashboardAdapter.contains("GoalDashboardScreen(goal: goal)"))
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

    @Test("Public coordinator graph excludes planner and flex destinations")
    func publicCoordinatorGraphExcludesHiddenRoutes() throws {
        let root = repositoryRoot()
        let coordinator = try readSource(
            root,
            "ios/CryptoSavingsTracker/Navigation/Coordinator.swift"
        )

        #expect(!coordinator.contains("case monthlyPlanning"))
        #expect(!coordinator.contains("case monthlyPlanningSettings"))
        #expect(!coordinator.contains("case flexAdjustment"))
        #expect(!coordinator.contains("showMonthlyPlanning"))
        #expect(!coordinator.contains("SettingsCoordinator"))
        #expect(!coordinator.contains("DashboardCoordinator"))
        #expect(!coordinator.contains("MonthlyPlanningContainer()"))
        #expect(!coordinator.contains("MonthlyPlanningSettingsView"))
        #expect(!coordinator.contains("FlexAdjustmentView"))
    }

    @Test("Goal dashboard allocation CTA stays inside retained asset allocation flow")
    func goalDashboardAllocationActionUsesRetainedFlow() throws {
        let root = repositoryRoot()
        let screen = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift"
        )

        #expect(screen.contains("case .rebalanceAllocations:"))
        #expect(screen.contains("openAllocationFlow()"))
        #expect(!screen.contains("Open goal details and adjust asset allocations."))
    }

    @Test("Public goal dashboard structurally disables forecast assembly in release MVP")
    func goalDashboardForecastAssemblyIsContainedInPublicMode() throws {
        let root = repositoryRoot()
        let assembler = try readSource(
            root,
            "ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift"
        )

        #expect(assembler.contains("let forecastModulesEnabled = HiddenRuntimeMode.current.showsForecastModules"))
        #expect(assembler.contains("includeForecastState: forecastModulesEnabled"))
        #expect(assembler.contains("guard isEnabled else {"))
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
