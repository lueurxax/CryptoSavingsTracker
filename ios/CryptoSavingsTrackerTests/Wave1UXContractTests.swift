//
//  Wave1UXContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct Wave1UXContractTests {
    @Test("Dashboard transaction flows avoid EmptyView placeholders")
    func dashboardTransactionFlowsAvoidEmptyPlaceholders() throws {
        let root = repositoryRoot()
        let goalDashboardScreen = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift"
        )
        let dashboardComponents = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift"
        )
        let recoverySheet = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/DashboardTransactionRecoverySheet.swift"
        )

        #expect(!goalDashboardScreen.contains("EmptyView()"))
        #expect(!dashboardComponents.contains("EmptyView()"))
        #expect(goalDashboardScreen.contains("DashboardTransactionRecoverySheet"))
        #expect(dashboardComponents.contains("DashboardTransactionRecoverySheet"))
        #expect(dashboardComponents.contains("if goalAssets.isEmpty"))
        #expect(!dashboardComponents.contains(".disabled(goalAssets.isEmpty)"))
        #expect(recoverySheet.contains("DashboardAccessibilityCopy.transactionRecoveryFooter"))
        #expect(recoverySheet.contains("DashboardAccessibilityCopy.transactionRecoveryDismissHint"))
        #expect(recoverySheet.contains("dashboard.transaction_recovery.dismiss"))
        #expect(goalDashboardScreen.contains("dashboard.asset_picker.dismiss"))
        #expect(goalDashboardScreen.contains("DashboardAccessibilityCopy.assetPickerDismissHint"))
        #expect(dashboardComponents.contains("dashboard.asset_picker.dismiss"))
        #expect(dashboardComponents.contains("DashboardAccessibilityCopy.assetPickerDismissHint"))
    }

    @Test("Planning compact surfaces avoid forced single-line truncation")
    func planningCompactSurfacesAvoidForcedSingleLineTruncation() throws {
        let root = repositoryRoot()
        let budgetSummaryCard = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift"
        )
        let planningView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift"
        )

        #expect(!budgetSummaryCard.contains(".lineLimit(1)"))
        #expect(!planningView.contains(".lineLimit(1)"))
    }

    @Test("Planning commit dock headline avoids forced single-line truncation")
    func planningCommitDockAvoidsForcedSingleLineTruncation() throws {
        let root = repositoryRoot()
        let commitDock = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/CommitDock.swift"
        )

        #expect(!commitDock.contains(".lineLimit(1)"))
        #expect(commitDock.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    @Test("Settings excludes monthly planning preview in public MVP containment")
    func settingsExcludesMonthlyPlanningPreviewInPublicMvp() throws {
        let root = repositoryRoot()
        let settingsView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift"
        )

        #expect(!settingsView.contains("MonthlyPlanningSettingsView(goals: [])"))
        #expect(!settingsView.contains("MonthlyPlanningSettingsView(goals: activeGoals)"))
    }

    @Test("Settings excludes CSV export action in public MVP containment")
    func settingsExcludesCsvExportActionInPublicMvp() throws {
        let root = repositoryRoot()
        let settingsView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift"
        )

        #expect(settingsView.components(separatedBy: ".accessibilityIdentifier(\"exportCSVButton\")").count - 1 == 0)
        #expect(!settingsView.contains("CSVExport"))
    }

    @Test("Settings import review uses accessible semantic status colors")
    func settingsImportReviewUsesAccessibleSemanticStatusColors() throws {
        let root = repositoryRoot()
        let importReviewView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift"
        )

        #expect(!importReviewView.contains("return .orange"))
        #expect(!importReviewView.contains("return .green"))
        #expect(!importReviewView.contains("return .red"))
        #expect(!importReviewView.contains("return .secondary"))
        #expect(!importReviewView.contains(".foregroundStyle(.orange)"))
        #expect(!importReviewView.contains(".foregroundStyle(.red)"))

        #expect(importReviewView.contains("AccessibleColors.warning"))
        #expect(importReviewView.contains("AccessibleColors.success"))
        #expect(importReviewView.contains("AccessibleColors.error"))
        #expect(importReviewView.contains("AccessibleColors.secondaryText"))
    }

    @Test("Local Bridge Sync uses accessible semantic status colors")
    func localBridgeSyncUsesAccessibleSemanticStatusColors() throws {
        let root = repositoryRoot()
        let localBridgeSyncView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift"
        )

        #expect(!localBridgeSyncView.contains("? .green : .orange"))
        #expect(!localBridgeSyncView.contains("? .red : .green"))
        #expect(!localBridgeSyncView.contains("return .green"))
        #expect(!localBridgeSyncView.contains("return .orange"))
        #expect(!localBridgeSyncView.contains("return .red"))
        #expect(!localBridgeSyncView.contains("return .secondary"))
        #expect(!localBridgeSyncView.contains(".foregroundStyle(.orange)"))

        #expect(localBridgeSyncView.contains("AccessibleColors.success"))
        #expect(localBridgeSyncView.contains("AccessibleColors.warning"))
        #expect(localBridgeSyncView.contains("AccessibleColors.error"))
        #expect(localBridgeSyncView.contains("AccessibleColors.secondaryText"))
    }

    @Test("Planning empty state uses the shared recovery component and opens Add Goal")
    func planningEmptyStateUsesSharedRecovery() throws {
        let root = repositoryRoot()
        let planningView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift"
        )
        let planningContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift"
        )

        #expect(!planningView.contains("EmptyView()"))
        #expect(planningView.contains("EmptyStateView("))
        #expect(planningView.contains("title: \"No Active Goals\""))
        #expect(planningView.contains("title: \"Add Goal\""))
        #expect(planningView.contains("onAddGoal?()"))
        #expect(planningContainer.contains("PlanningView(viewModel: planningViewModel, onAddGoal:"))
        #expect(planningContainer.contains("showingAddGoal = true"))
    }

    @Test("Planning history and monthly settings use semantic interactive accents")
    func planningHistoryAndMonthlySettingsUseSemanticInteractiveAccents() throws {
        let root = repositoryRoot()
        let historyDetail = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryDetailView.swift"
        )
        let monthlySettings = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/MonthlyPlanningSettingsView.swift"
        )

        #expect(!historyDetail.contains("return .blue"))
        #expect(historyDetail.contains("return AccessibleColors.primaryInteractive"))

        #expect(!monthlySettings.contains(".tint(.blue)"))
        #expect(!monthlySettings.contains(".foregroundColor(.blue)"))
        #expect(monthlySettings.contains(".tint(AccessibleColors.primaryInteractive)"))
        #expect(monthlySettings.contains(".foregroundColor(AccessibleColors.primaryInteractive)"))
    }

    @Test("Monthly planning settings budget row exposes explicit accessibility guidance")
    func monthlyPlanningSettingsBudgetRowExposesAccessibilityGuidance() throws {
        let root = repositoryRoot()
        let monthlySettings = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/MonthlyPlanningSettingsView.swift"
        )

        #expect(monthlySettings.contains(".accessibilityIdentifier(\"settings.monthlyPlanning.budget\")"))
        #expect(monthlySettings.contains(".accessibilityLabel(\"Monthly budget\")"))
        #expect(
            monthlySettings.contains(
                ".accessibilityHint(\"Double tap to review or change the monthly budget used for planning.\")"
            )
        )
        #expect(monthlySettings.contains(".accessibilityValue(monthlyBudgetAccessibilityValue)"))
        #expect(monthlySettings.contains("return \"Not set\""))
        #expect(monthlySettings.contains("CurrencyFormatter.accessibilityFormat("))
        #expect(monthlySettings.contains("currency: settings.budgetCurrency"))
    }

    @Test("Planning history surfaces respect the snapshot currency")
    func planningHistorySurfacesRespectSnapshotCurrency() throws {
        let root = repositoryRoot()
        let historyList = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryListView.swift"
        )
        let historyDetail = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryDetailView.swift"
        )

        #expect(historyList.contains("currency: group.currency"))
        #expect(historyDetail.contains("currency: historyCurrency"))
        #expect(!historyDetail.contains("number.currencyCode = \"USD\""))
    }

    @Test("Planning cycle summary and execution surfaces use semantic interactive accents")
    func planningCycleSummaryAndExecutionUseSemanticInteractiveAccents() throws {
        let root = repositoryRoot()
        let planningContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift"
        )
        let executionView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyExecutionView.swift"
        )
        let staleDraftBanner = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift"
        )

        #expect(!planningContainer.contains("return .blue"))
        #expect(!planningContainer.contains("return Color.blue.opacity(0.1)"))
        #expect(planningContainer.contains("return AccessibleColors.primaryInteractive"))
        #expect(planningContainer.contains("return AccessibleColors.primaryInteractiveBackground"))

        #expect(!executionView.contains(".background(Color.blue.opacity(0.1))"))
        #expect(!executionView.contains(".foregroundStyle(.blue)"))
        #expect(!executionView.contains(".fill(Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.10))"))
        #expect(executionView.contains(".background(AccessibleColors.primaryInteractiveBackground)"))
        #expect(executionView.contains(".foregroundStyle(AccessibleColors.primaryInteractive)"))
        #expect(executionView.contains(".fill(AccessibleColors.primaryInteractive.opacity(colorScheme == .dark ? 0.18 : 0.10))"))

        #expect(!staleDraftBanner.contains("Color.accentColor"))
        #expect(staleDraftBanner.contains("AccessibleColors.primaryInteractive"))
        #expect(staleDraftBanner.contains("AccessibleColors.secondaryText.opacity(0.3)"))
    }

    @Test("Budget calculator input controls expose explicit accessibility guidance")
    func budgetCalculatorInputControlsExposeExplicitAccessibilityGuidance() throws {
        let root = repositoryRoot()
        let budgetCalculatorSheet = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/BudgetCalculatorSheet.swift"
        )

        #expect(budgetCalculatorSheet.contains(".accessibilityLabel(\"Budget currency\")"))
        #expect(
            budgetCalculatorSheet.contains(
                ".accessibilityHint(\"Double tap to choose the currency used for this monthly budget plan.\")"
            )
        )
        #expect(budgetCalculatorSheet.contains(".accessibilityValue(currency.uppercased())"))

        #expect(budgetCalculatorSheet.contains(".accessibilityLabel(\"Monthly budget amount\")"))
        #expect(
            budgetCalculatorSheet.contains(
                ".accessibilityHint(\"Enter the amount you can save each month for active goals.\")"
            )
        )
        #expect(budgetCalculatorSheet.contains(".accessibilityValue(budgetAmountAccessibilityValue)"))
        #expect(
            budgetCalculatorSheet.components(separatedBy: ".accessibilityIdentifier(\"budgetAmountField\")").count - 1 == 1
        )

        #expect(
            budgetCalculatorSheet.components(separatedBy: ".accessibilityIdentifier(\"budgetKeyboardDoneButton\")").count - 1 == 1
        )
        #expect(
            budgetCalculatorSheet.components(separatedBy: ".accessibilityIdentifier(\"budgetInlineDoneButton\")").count - 1 == 1
        )
    }

    @Test("Planning presentation helpers use autoupdating locale for display copy")
    func planningPresentationHelpersUseAutoupdatingLocaleForDisplayCopy() throws {
        let root = repositoryRoot()
        let historyPresentation = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryPresentation.swift"
        )
        let staleDraftPresentation = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/StaleDraftPresentation.swift"
        )

        #expect(historyPresentation.contains("formatter.locale = .autoupdatingCurrent"))
        #expect(staleDraftPresentation.contains("formatter.locale = .autoupdatingCurrent"))
        #expect(historyPresentation.contains("private static let monthParser"))
        #expect(staleDraftPresentation.contains("private static let monthParser"))
        #expect(historyPresentation.contains("formatter.locale = Locale(identifier: \"en_US_POSIX\")"))
        #expect(staleDraftPresentation.contains("formatter.locale = Locale(identifier: \"en_US_POSIX\")"))
        #expect(historyPresentation.contains("private static let monthTitleFormatter"))
        #expect(staleDraftPresentation.contains("private static let monthFormatter"))
    }

    @Test("Secondary Wave 1 surfaces avoid debug prints and use semantic styling")
    func secondaryWave1SurfacesAvoidDebugPrintsAndUseSemanticStyling() throws {
        let root = repositoryRoot()
        let goalsSidebar = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Components/GoalsSidebarView.swift"
        )
        let chartErrorView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Components/ChartErrorView.swift"
        )
        let staleDraftPreview = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/StaleDraftBannerPreview.swift"
        )

        #expect(!goalsSidebar.contains("print("))
        #expect(!goalsSidebar.contains("Color.blue.opacity(0.1)"))
        #expect(!goalsSidebar.contains(".foregroundColor(.blue)"))
        #expect(goalsSidebar.contains("AccessibleColors.primaryInteractive"))
        #expect(goalsSidebar.contains("AccessibleColors.primaryInteractiveBackground"))
        #expect(goalsSidebar.contains("goals.sidebar.portfolio_overview"))

        #expect(!chartErrorView.contains("print("))
        #expect(chartErrorView.contains("AppLog.info("))
        #expect(chartErrorView.contains("category: .ui"))
        #expect(chartErrorView.contains("Logs the related help topic until in-app help navigation is available."))

        #expect(!staleDraftPreview.contains("print("))
        #expect(staleDraftPreview.contains("AppLog.debug("))
        #expect(staleDraftPreview.contains("category: .monthlyPlanning"))
    }

    @Test("What-if sliders expose explicit accessibility guidance")
    func whatIfSlidersExposeExplicitAccessibilityGuidance() throws {
        let root = repositoryRoot()
        let whatIfView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/WhatIfView.swift"
        )

        #expect(whatIfView.contains(".accessibilityLabel(\"Monthly contribution adjustment\")"))
        #expect(whatIfView.contains(".accessibilityHint(\"Adjusts the recurring monthly contribution used in the projection.\")"))
        #expect(whatIfView.contains(".accessibilityIdentifier(\"dashboard.what_if.monthly_slider\")"))
        #expect(whatIfView.contains(".accessibilityValue(CurrencyFormatter.accessibilityFormat(amount: settings.monthly, currency: goal.currency))"))

        #expect(whatIfView.contains(".accessibilityLabel(\"One-time investment adjustment\")"))
        #expect(whatIfView.contains(".accessibilityHint(\"Adjusts the one-time contribution used in the projection.\")"))
        #expect(whatIfView.contains(".accessibilityIdentifier(\"dashboard.what_if.one_time_slider\")"))
        #expect(whatIfView.contains(".accessibilityValue(CurrencyFormatter.accessibilityFormat(amount: settings.oneTime, currency: goal.currency))"))
    }

    @Test("Wave 1 planning logs avoid raw error interpolation")
    func wave1PlanningLogsAvoidRawErrorInterpolation() throws {
        let root = repositoryRoot()
        let historyList = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryListView.swift"
        )
        let historyDetail = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/PlanHistoryDetailView.swift"
        )
        let planningContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift"
        )
        let planningViewModel = try readSource(
            root,
            "ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift"
        )

        #expect(!historyList.contains(": \\(error)"))
        #expect(historyList.contains(": \\(error.localizedDescription)"))

        #expect(!historyDetail.contains(": \\(error)"))
        #expect(historyDetail.contains(": \\(error.localizedDescription)"))

        #expect(!planningContainer.contains(": \\(error)"))
        #expect(planningContainer.contains(": \\(error.localizedDescription)"))

        #expect(!planningViewModel.contains(": \\(error)"))
        #expect(planningViewModel.contains(": \\(error.localizedDescription)"))
    }

    @Test("Wave 1 surfaces use semantic neutral color tokens")
    func wave1SurfacesUseSemanticNeutralColorTokens() throws {
        let root = repositoryRoot()
        let dashboardComponents = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift"
        )
        let enhancedComponents = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/EnhancedDashboardComponents.swift"
        )
        let whatIfView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Dashboard/WhatIfView.swift"
        )
        let monthlySettings = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Settings/MonthlyPlanningSettingsView.swift"
        )
        let planningContainer = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift"
        )
        let goalRequirementRow = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/GoalRequirementRow.swift"
        )

        #expect(!dashboardComponents.contains("Color.gray.opacity(0.1)"))
        #expect(!dashboardComponents.contains("Color.gray.opacity(0.4)"))
        #expect(dashboardComponents.contains("VisualComponentTokens.dashboardCardStroke"))
        #expect(dashboardComponents.contains("AccessibleColors.primaryInteractive"))
        #expect(!dashboardComponents.contains(".background(goalAssets.isEmpty ? AccessibleColors.disabled : AccessibleColors.success)"))

        #expect(!enhancedComponents.contains("Color.gray.opacity(0.04)"))
        #expect(!enhancedComponents.contains("Color.gray.opacity(0.06)"))
        #expect(enhancedComponents.contains("AccessibleColors.surfaceSubtle"))
        #expect(enhancedComponents.contains("AccessibleColors.surfaceBase"))

        #expect(!whatIfView.contains("Color.gray.opacity(0.1)"))
        #expect(whatIfView.contains("VisualComponentTokens.dashboardCardStroke"))

        #expect(!monthlySettings.contains("Color.gray.opacity(0.1)"))
        #expect(monthlySettings.contains("Color.accessibleSurfaceSubtle"))

        #expect(!planningContainer.contains("Color.gray.opacity(0.05)"))
        #expect(planningContainer.contains("AccessibleColors.surfaceSubtle"))

        #expect(!goalRequirementRow.contains("Color.gray"))
        #expect(goalRequirementRow.contains("AccessibleColors.disabled"))

        let budgetSummaryCard = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift"
        )
        let planningContainerSecondary = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift"
        )

        #expect(!budgetSummaryCard.contains("return .secondary"))
        #expect(budgetSummaryCard.contains("return AccessibleColors.secondaryText"))
        #expect(!planningContainerSecondary.contains("return .secondary"))
        #expect(planningContainerSecondary.contains("return AccessibleColors.secondaryText"))
    }

    @Test("Stale draft pagination exposes accessible pager metadata")
    func staleDraftPaginationExposesAccessiblePagerMetadata() throws {
        let root = repositoryRoot()
        let staleDraftBanner = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift"
        )

        #expect(staleDraftBanner.contains(".accessibilityLabel(StaleDraftPresentation.paginationAccessibilityLabel)"))
        #expect(staleDraftBanner.contains(".accessibilityValue("))
        #expect(staleDraftBanner.contains("StaleDraftPresentation.paginationStatus("))
        #expect(staleDraftBanner.contains(".accessibilityHint(StaleDraftPresentation.paginationAccessibilityHint)"))
        #expect(staleDraftBanner.contains(".accessibilityIdentifier(\"staleDraftPagination\")"))
        #expect(staleDraftBanner.contains(".accessibilityIdentifier(\"staleDraftPaginationPrevious\")"))
        #expect(staleDraftBanner.contains(".accessibilityIdentifier(\"staleDraftPaginationNext\")"))
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
