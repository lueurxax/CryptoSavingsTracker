//
//  MVPContainmentContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct MVPContainmentContractTests {
    @Test("Transition coordinator shows the migration banner until dismissal")
    @MainActor
    func transitionCoordinatorShowsBannerUntilDismissal() {
        let suiteName = "MVPContainmentContractTests.dismissal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = RetiredFeatureTransitionCoordinator(
            userDefaults: defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_000) }
        )

        coordinator.registerLaunchIfNeeded()
        #expect(coordinator.shouldShowMigrationBanner)

        coordinator.dismissMigrationBanner()
        #expect(!coordinator.shouldShowMigrationBanner)
    }

    @Test("Transition coordinator expires the migration banner after the fallback window")
    @MainActor
    func transitionCoordinatorExpiresBannerAfterFallbackWindow() {
        let suiteName = "MVPContainmentContractTests.expiry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSince1970: 1_000)
        let coordinator = RetiredFeatureTransitionCoordinator(
            userDefaults: defaults,
            nowProvider: { start }
        )
        coordinator.registerLaunchIfNeeded()
        #expect(coordinator.shouldShowMigrationBanner)

        let secondLaunch = RetiredFeatureTransitionCoordinator(
            userDefaults: defaults,
            nowProvider: { start.addingTimeInterval(60) }
        )
        secondLaunch.registerLaunchIfNeeded()
        #expect(secondLaunch.shouldShowMigrationBanner)

        let thirdLaunch = RetiredFeatureTransitionCoordinator(
            userDefaults: defaults,
            nowProvider: { start.addingTimeInterval(120) }
        )
        thirdLaunch.registerLaunchIfNeeded()
        #expect(!thirdLaunch.shouldShowMigrationBanner)
    }

    @Test("Retained Apple hosts no longer embed monthly planning widgets")
    func retainedHostsExcludeMonthlyPlanningWidget() throws {
        let root = repositoryRoot()
        let contentView = try readSource(root, "ios/CryptoSavingsTracker/Views/ContentView.swift")
        let goalsListView = try readSource(root, "ios/CryptoSavingsTracker/Views/GoalsListView.swift")
        let emptyDetailView = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/EmptyDetailView.swift")

        #expect(!contentView.contains("MonthlyPlanningWidget"))
        #expect(!goalsListView.contains("MonthlyPlanningWidget"))
        #expect(!emptyDetailView.contains("MonthlyPlanningWidget"))
    }

    @Test("App startup omits retired startup hooks and goal comparison scene")
    func appStartupExcludesRetiredHooks() throws {
        let root = repositoryRoot()
        let appSource = try readSource(root, "ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift")

        #expect(!appSource.contains("NotificationManager.shared.requestPermission"))
        #expect(!appSource.contains("backfillCompletionEventsIfNeeded"))
        #expect(!appSource.contains("AutomationScheduler"))
        #expect(!appSource.contains("checkAutomation()"))
        #expect(!appSource.contains("FamilyShareReconciliationBarrier.startObservingImports"))
        #expect(!appSource.contains("handleScenePhaseChange"))
        #expect(!appSource.contains("WindowGroup(\"Goal Comparison\""))
        #expect(!appSource.contains("@UIApplicationDelegateAdaptor(FamilyShareAppDelegate.self)"))
    }

    @Test("Retained MVP routes do not refresh family sharing from ContentView or SettingsView")
    func retainedRoutesExcludeFamilyShareRefresh() throws {
        let root = repositoryRoot()
        let contentView = try readSource(root, "ios/CryptoSavingsTracker/Views/ContentView.swift")
        let settingsView = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift")
        let dashboardView = try readSource(root, "ios/CryptoSavingsTracker/Views/DashboardView.swift")

        #expect(!contentView.contains("refreshAllState"))
        #expect(!settingsView.contains("refreshAllState"))
        #expect(!settingsView.contains("FamilyAccessView"))
        #expect(!settingsView.contains("LocalBridgeSyncView"))
        #expect(!settingsView.contains("CSVExportService"))
        #expect(!settingsView.contains("MonthlyPlanningSettingsView"))
        #expect(dashboardView.contains("RetiredFeatureTransitionCoordinator"))
        #expect(dashboardView.contains("mvpMigrationBanner"))
        #expect(settingsView.contains("What changed in this update"))
    }

    @Test("Root dashboard uses the fixed MVP contract and excludes legacy customization paths")
    func rootDashboardUsesFixedMVPContract() throws {
        let root = repositoryRoot()
        let dashboardView = try readSource(root, "ios/CryptoSavingsTracker/Views/DashboardView.swift")

        #expect(dashboardView.contains("Portfolio Overview"))
        #expect(dashboardView.contains("Active Goals"))
        #expect(dashboardView.contains("Recent Activity"))
        #expect(dashboardView.contains("Next Step"))

        #expect(!dashboardView.contains("dashboard_widgets"))
        #expect(!dashboardView.contains("DashboardCustomizationView"))
        #expect(!dashboardView.contains("LegacyDashboardFallbackView"))
        #expect(!dashboardView.contains("VisualSystemRollout"))
        #expect(!dashboardView.contains("CustomWidgetsGrid"))
        #expect(!dashboardView.contains("MobileForecastSection"))
        #expect(!dashboardView.contains("showingCustomize"))
        #expect(!dashboardView.contains("Customize"))
    }

    @Test("UI test seed harness keeps only MVP seed scenarios")
    func uiTestSeedHarnessExcludesRetiredScenarios() throws {
        let root = repositoryRoot()
        let appSource = try readSource(root, "ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift")

        #expect(!appSource.contains("UITEST_SEED_BUDGET_SHORTFALL"))
        #expect(!appSource.contains("UITEST_SEED_STALE_DRAFTS"))
        #expect(!appSource.contains("UITEST_RESHARE_ASSET"))
        #expect(!appSource.contains("UITEST_FAMILY_SHARE_SCENARIO"))
        #expect(!appSource.contains("MonthlyPlanningContainer()"))
    }

    @Test("Retained asset and allocation paths do not emit planner-era asset update notifications")
    func retainedAssetMutationPathsExcludePlannerAssetSignal() throws {
        let root = repositoryRoot()
        let allocationService = try readSource(root, "ios/CryptoSavingsTracker/Services/AllocationService.swift")
        let assetViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift")
        let assetRowView = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetRowView.swift")

        #expect(!allocationService.contains("name: .monthlyPlanningAssetUpdated"))
        #expect(!assetViewModel.contains("name: .monthlyPlanningAssetUpdated"))
        #expect(!assetRowView.contains("name: .monthlyPlanningAssetUpdated"))

        #expect(allocationService.contains("name: .sharedGoalDataDidChange"))
        #expect(assetViewModel.contains("name: .sharedGoalDataDidChange"))
        #expect(assetRowView.contains("name: .sharedGoalDataDidChange"))
    }

    @Test("Goal edit flow excludes planner recalculation and reminder-state restoration")
    func goalEditFlowExcludesPlannerAndReminderRevival() throws {
        let root = repositoryRoot()
        let goalEditViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/GoalEditViewModel.swift")
        let editGoalView = try readSource(root, "ios/CryptoSavingsTracker/Views/EditGoalView.swift")

        #expect(!goalEditViewModel.contains("recalculateMonthlyPlan"))
        #expect(!goalEditViewModel.contains("makeMonthlyPlanService"))
        #expect(!goalEditViewModel.contains("planNeedsRecalculation"))
        #expect(!goalEditViewModel.contains("originalSnapshot.reminderFrequency"))
        #expect(!goalEditViewModel.contains("originalSnapshot.reminderTime"))
        #expect(!goalEditViewModel.contains("notificationUpdateFailed"))
        #expect(goalEditViewModel.contains("goal.clearRetiredReminderState()"))
        #expect(goalEditView.contains("Basic Information"))
        #expect(!editGoalView.contains("ReminderConfigurationView"))
    }

    @Test("Retained onboarding and goal detail copy exclude reminder-era messaging")
    func retainedCopyExcludesReminderEraMessaging() throws {
        let root = repositoryRoot()
        let onboardingStepViews = try readSource(root, "ios/CryptoSavingsTracker/Views/Onboarding/OnboardingStepViews.swift")
        let goalTemplate = try readSource(root, "ios/CryptoSavingsTracker/Models/GoalTemplate.swift")
        let goalDetailView = try readSource(root, "ios/CryptoSavingsTracker/Views/GoalDetailView.swift")

        #expect(!onboardingStepViews.contains("smart automation"))
        #expect(!onboardingStepViews.contains("intelligent reminders"))
        #expect(!onboardingStepViews.contains("title: \"Monthly\""))
        #expect(!onboardingStepViews.contains("estimatedMonthlyContribution"))
        #expect(onboardingStepViews.contains("title: \"Assets\""))
        #expect(onboardingStepViews.contains("Create savings goals, connect crypto or fiat assets, and track real progress"))
        #expect(onboardingStepViews.contains("Goal Tracking"))
        #expect(onboardingStepViews.contains("Manual Flexibility"))
        #expect(!goalTemplate.contains("estimatedMonthlyContribution"))
        #expect(!goalDetailView.contains("Next reminder:"))
    }

    @Test("Transaction entry flow excludes reminder scheduling hooks")
    func transactionEntryFlowExcludesReminderSchedulingHooks() throws {
        let root = repositoryRoot()
        let addTransactionView = try readSource(root, "ios/CryptoSavingsTracker/Views/AddTransactionView.swift")
        let mutationServices = try readSource(root, "ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift")

        #expect(!addTransactionView.contains("scheduleReminders"))
        #expect(!addTransactionView.contains("NotificationManager.shared"))
        #expect(!mutationServices.contains("scheduleReminders(for: goal)"))
    }

    @Test("Goal lifecycle mutation service keeps resume cleanup cancellation-only")
    func goalMutationResumePathCancelsLegacyNotifications() throws {
        let root = repositoryRoot()
        let protocols = try readSource(root, "ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift")
        let mutationServices = try readSource(root, "ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift")

        #expect(protocols.contains("func resumeGoal(_ goal: Goal) async throws"))
        #expect(mutationServices.contains("func resumeGoal(_ goal: Goal) async throws"))
        #expect(mutationServices.contains("await notificationManager.cancelNotifications(for: goal)"))
    }

    @Test("Reminder retirement uses the shared goal helper in active MVP write paths")
    func reminderRetirementUsesSharedGoalHelper() throws {
        let root = repositoryRoot()
        let goalEditing = try readSource(root, "ios/CryptoSavingsTracker/Models/Goal+Editing.swift")
        let goalModel = try readSource(root, "ios/CryptoSavingsTracker/Models/Goal.swift")
        let addGoalView = try readSource(root, "ios/CryptoSavingsTracker/Views/AddGoalView.swift")
        let goalEditViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/GoalEditViewModel.swift")
        let goalLifecycleService = try readSource(root, "ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift")
        let mutationServices = try readSource(root, "ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift")
        let goalRepository = try readSource(root, "ios/CryptoSavingsTracker/Repositories/GoalRepository.swift")

        #expect(goalEditing.contains("func clearRetiredReminderState()"))
        #expect(goalModel.contains("frequency: ReminderFrequency? = nil"))
        #expect(addGoalView.contains("newGoal.clearRetiredReminderState()"))
        #expect(goalEditViewModel.contains("goal.clearRetiredReminderState()"))
        #expect(goalLifecycleService.contains("goal.clearRetiredReminderState()"))
        #expect(mutationServices.contains("goal.clearRetiredReminderState()"))
        #expect(goalRepository.contains("goal.clearRetiredReminderState()"))
    }

    @Test("Shared SwiftData query helpers treat reminder metadata as migration-only cleanup state")
    func swiftDataQueriesTreatReminderMetadataAsCleanupOnly() throws {
        let root = repositoryRoot()
        let swiftDataQueries = try readSource(root, "ios/CryptoSavingsTracker/Utilities/SwiftDataQueries.swift")

        #expect(!swiftDataQueries.contains("static func goalsWithReminders()"))
        #expect(swiftDataQueries.contains("static func legacyReminderCleanupCandidates()"))
        #expect(swiftDataQueries.contains("goal.reminderFrequency != nil ||"))
        #expect(swiftDataQueries.contains("goal.reminderTime != nil ||"))
        #expect(swiftDataQueries.contains("goal.firstReminderDate != nil"))
        #expect(swiftDataQueries.contains("SortDescriptor(\\.lastModifiedDate, order: .reverse)"))
        #expect(!swiftDataQueries.contains("SortDescriptor(\\.reminderTime, order: .forward)"))
    }

    @Test("Goal calculation helpers exclude reminder-era dependencies in MVP flows")
    func goalCalculationHelpersExcludeReminderState() throws {
        let root = repositoryRoot()
        let protocols = try readSource(root, "ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift")
        let goalCalculationService = try readSource(root, "ios/CryptoSavingsTracker/Services/GoalCalculationService.swift")

        #expect(protocols.contains("static func getSuggestedDeposit(for goal: Goal) async -> Double"))
        #expect(!protocols.contains("static func isReminderEnabled(for goal: Goal)"))
        #expect(!protocols.contains("static func getReminderFrequency(for goal: Goal)"))
        #expect(!protocols.contains("static func getReminderDates(for goal: Goal)"))
        #expect(!protocols.contains("static func getRemainingReminderDates(for goal: Goal)"))
        #expect(!protocols.contains("static func getNextReminder(for goal: Goal)"))

        #expect(goalCalculationService.contains("let remainingDays = max(Self.getDaysRemaining(for: goal), 1)"))
        #expect(goalCalculationService.contains("let remainingDays = max(getDaysRemaining(for: goal), 1)"))
        #expect(!goalCalculationService.contains("getRemainingReminderDates"))
        #expect(!goalCalculationService.contains("ReminderFrequency"))
        #expect(!goalCalculationService.contains("reminderFrequency"))
        #expect(!goalCalculationService.contains("reminderTime"))
        #expect(!goalCalculationService.contains("firstReminderDate"))
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
