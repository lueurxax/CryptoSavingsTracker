//
//  MVPContainmentContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct MVPContainmentContractTests {
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

    @Test("Retained MVP routes exclude migration chrome and hidden settings destinations")
    func retainedRoutesExcludeMigrationChromeAndHiddenDestinations() throws {
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
        #expect(!dashboardView.contains("RetiredFeatureTransitionCoordinator"))
        #expect(!dashboardView.contains("mvpMigrationBanner"))
        #expect(!settingsView.contains("What changed in this update"))
    }

    @Test("Public surfaces never disclose containment or removed-feature language")
    func publicSurfacesExcludeContainmentDisclosureLanguage() throws {
        let root = repositoryRoot()
        let publicSurfaces = [
            try readSource(root, "ios/CryptoSavingsTracker/Views/ContentView.swift"),
            try readSource(root, "ios/CryptoSavingsTracker/Views/GoalsListView.swift"),
            try readSource(root, "ios/CryptoSavingsTracker/Views/DashboardView.swift"),
            try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift"),
            try readSource(root, "docs/support/index.html")
        ].joined(separator: "\n")

        let forbiddenCopy = [
            "Focused MVP",
            "Public MVP",
            "narrower runtime",
            "advanced features",
            "internal development builds",
            "What changed in this update",
            "removed features",
            "features were removed",
            "hidden features",
            "support.cryptosavingstracker.app/mvp"
        ]

        for copy in forbiddenCopy {
            #expect(!publicSurfaces.localizedCaseInsensitiveContains(copy))
        }
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

    @Test("Retained asset detail and transaction history use local navigation seams")
    func retainedAssetDetailAndHistoryDropAppCoordinatorDependency() throws {
        let root = repositoryRoot()
        let assetDetail = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetDetailView.swift")
        let transactionHistory = try readSource(root, "ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift")

        #expect(!assetDetail.contains("@EnvironmentObject private var coordinator: AppCoordinator"))
        #expect(!assetDetail.contains("coordinator.showTransactionHistory"))
        #expect(!assetDetail.contains("coordinator.goalCoordinator.showAddTransaction"))
        #expect(!assetDetail.contains("coordinator.goalCoordinator.showEditAsset"))
        #expect(assetDetail.contains("showingTransactionHistory"))
        #expect(assetDetail.contains("showingAddTransaction"))

        #expect(!transactionHistory.contains("@EnvironmentObject private var coordinator: AppCoordinator"))
        #expect(!transactionHistory.contains("coordinator.goalCoordinator.showAddTransaction"))
        #expect(transactionHistory.contains("showingAddTransaction"))
    }

    @Test("Public asset allocation copy avoids sharing language and planner shortcuts")
    func publicAssetAllocationCopyAndBehaviorStayMvpScoped() throws {
        let root = repositoryRoot()
        let assetAllocation = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetSharingView.swift")
        let assetDetail = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetDetailView.swift")
        let banner = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/AllocationPromptBanner.swift")
        let assetRow = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetRowView.swift")
        let unallocatedSection = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/UnallocatedAssetsSection.swift")

        #expect(!assetAllocation.contains(".monthlyPlanningAssetUpdated"))
        #expect(!assetAllocation.contains("executionTrackingService"))
        #expect(!assetAllocation.contains("makeMonthlyPlanService"))
        #expect(!assetAllocation.contains("Share Asset"))
        #expect(!assetAllocation.contains("How to share this asset"))
        #expect(assetAllocation.contains("Manage Allocations"))
        #expect(assetAllocation.contains("Allocate to Goals"))

        #expect(assetDetail.contains("Manage Allocations"))
        #expect(!banner.contains("share \\(asset.currency) with other goals"))
        #expect(banner.contains("assign \\(asset.currency)"))
        #expect(!assetRow.contains("Text(\"Share\")"))
        #expect(assetRow.contains("Text(\"Allocate\")"))
        #expect(!assetRow.contains("shareAssetButton"))
        #expect(assetRow.contains("manageAllocationButton"))
        #expect(!unallocatedSection.contains("share this asset"))
        #expect(unallocatedSection.contains("allocate this asset"))
    }

    @Test("Retained crypto tracking uses explicit public state vocabulary")
    func retainedCryptoTrackingUsesExplicitPublicStateVocabulary() throws {
        let root = repositoryRoot()
        let balanceState = try readSource(root, "ios/CryptoSavingsTracker/Models/BalanceState.swift")
        let assetViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift")
        let addAssetView = try readSource(root, "ios/CryptoSavingsTracker/Views/AddAssetView.swift")
        let assetRowView = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetRowView.swift")
        let assetDetailView = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetDetailView.swift")

        for state in ["Connecting", "Syncing", "Connected", "Stale", "Needs Attention"] {
            #expect(balanceState.contains(state))
        }
        #expect(assetViewModel.contains("publicCryptoTrackingStatus"))
        #expect(addAssetView.contains("Tracking states: Connecting, Syncing, Connected, Stale, Needs Attention."))
        #expect(assetRowView.contains("publicCryptoTrackingStatus"))
        #expect(assetDetailView.contains("publicCryptoTrackingStatus"))
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
        #expect(editGoalView.contains("Basic Information"))
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

    @Test("Goal detail is native detail-only and does not embed dashboard visuals")
    func goalDetailExcludesDashboardVisuals() throws {
        let root = repositoryRoot()
        let goalDetailView = try readSource(root, "ios/CryptoSavingsTracker/Views/GoalDetailView.swift")
        let detailContainer = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift")
        let goalDashboard = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift")

        #expect(!goalDetailView.contains("ProgressRingView("))
        #expect(!goalDetailView.contains("CompactAssetCompositionView("))
        #expect(!goalDetailView.contains("Show Details"))
        #expect(!goalDetailView.contains("Hide Details"))
        #expect(goalDetailView.contains("Section(\"Assets\")") || goalDetailView.contains("Text(\"Assets\")"))
        #expect(detailContainer.contains("GoalDashboardScreen(goal: goal)"))
        #expect(goalDashboard.contains("Goal Snapshot"))
    }

    @Test("Retained goal dashboard excludes planning and forecast CTAs")
    func retainedGoalDashboardExcludesPlannerEraCtas() throws {
        let root = repositoryRoot()
        let contract = try readSource(root, "ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift")
        let sceneAssembler = try readSource(root, "ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift")
        let migration = try readSource(root, "ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift")
        let copyCatalog = try readSource(root, "ios/CryptoSavingsTracker/Utilities/GoalDashboardCopyCatalog.swift")
        let screen = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift")
        #expect(!contract.contains("\"view_history\""))
        #expect(!sceneAssembler.contains("plan_this_month"))
        #expect(!sceneAssembler.contains("open_forecast"))
        #expect(!sceneAssembler.contains("view_goal_history"))
        #expect(!sceneAssembler.contains("\"view_history\""))
        #expect(!migration.contains("\"view_history\""))
        #expect(contract.contains("\"review_activity\""))
        #expect(sceneAssembler.contains("\"review_activity\""))
        #expect(migration.contains("\"review_activity\""))
        #expect(!copyCatalog.contains("Plan this month now."))
        #expect(!screen.contains("Monthly Planning"))
    }

    @Test("Public diagnostics remains dashboard-local and not a Settings row")
    func publicDiagnosticsSurfaceIsDashboardLocalOnly() throws {
        let root = repositoryRoot()
        let proposal = try readSource(root, "docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md")
        let settingsView = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift")
        let sceneAssembler = try readSource(root, "ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift")
        let screen = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift")

        #expect(proposal.contains("Public diagnostics remains goal-dashboard-local"))
        #expect(proposal.contains("Settings/About does not expose a separate diagnostics status row"))
        #expect(!settingsView.contains("Diagnostics"))
        #expect(sceneAssembler.contains("id: \"view_diagnostics\""))
        #expect(screen.contains("case \"view_diagnostics\":"))
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
