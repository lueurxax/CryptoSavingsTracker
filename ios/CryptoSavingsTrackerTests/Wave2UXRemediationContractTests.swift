import Foundation
import Testing

struct Wave2UXRemediationContractTests {
    @Test("adaptive summary row encodes compact spacing and token contract")
    func adaptiveSummaryRowContract() throws {
        let root = repositoryRoot()
        let component = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/AdaptiveSummaryRow.swift")
        let preview = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/AdaptiveSummaryRowPreview.swift")

        #expect(component.contains("static let minimumHorizontalSpacing: CGFloat = 12"))
        #expect(component.contains("static let compactWidth: CGFloat = 320"))
        #expect(component.contains("static let compactLabelFraction: CGFloat = 0.5"))
        #expect(component.contains("ViewThatFits(in: .horizontal)"))
        #expect(component.contains("Spacer(minLength: Self.minimumHorizontalSpacing)"))
        #expect(component.contains("AccessibleColors.primaryText"))
        #expect(component.contains("AccessibleColors.secondaryText"))
        #expect(preview.contains("#Preview"))
    }

    @Test("goal and asset detail use adaptive rows and goal refresh error banner")
    func detailViewsUseAdaptiveRowsAndRecoverableRefreshError() throws {
        let root = repositoryRoot()
        let goalDetail = try readSource(root, "ios/CryptoSavingsTracker/Views/GoalDetailView.swift")
        let assetDetail = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetDetailView.swift")
        let goalViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift")

        #expect(goalDetail.contains("AdaptiveSummaryRow(label: label, value: value)"))
        #expect(goalDetail.contains("ErrorBannerView("))
        #expect(goalDetail.contains("onRetry: { await refreshBalances() }"))
        #expect(goalDetail.contains("onDismiss: { goalViewModel.balanceRefreshError = nil }"))
        #expect(assetDetail.contains("AdaptiveSummaryRow(label: \"Manual Balance\""))
        #expect(assetDetail.contains("valueTruncationMode: .middle"))
        #expect(!assetDetail.contains("struct InfoRow"))
        #expect(goalViewModel.contains("@Published var balanceRefreshError: UserFacingError?"))
        #expect(goalViewModel.contains("isRetryable: true"))
    }

    @Test("goal detail exposes zero transaction state and add transaction recovery")
    func goalDetailExposesZeroTransactionStateAndTransactionRows() throws {
        let root = repositoryRoot()
        let goalDetail = try readSource(root, "ios/CryptoSavingsTracker/Views/GoalDetailView.swift")

        #expect(goalDetail.contains("Section(\"Transactions\")"))
        #expect(goalDetail.contains("No transactions yet"))
        #expect(goalDetail.contains("goalDetailZeroTransactions"))
        #expect(goalDetail.contains("goalDetailAddTransactionButton"))
        #expect(goalDetail.contains("private var goalTransactions: [Transaction]"))
        #expect(goalDetail.contains("selectedAssetForAddTransaction"))
        #expect(goalDetail.contains("showingTransactionAssetPicker"))
        #expect(goalDetail.contains("AddTransactionView(asset: asset)"))
        #expect(goalDetail.contains("presentAddTransaction()"))
    }

    @Test("goals list context actions open real flows")
    func goalsListContextActionsOpenRealFlows() throws {
        let root = repositoryRoot()
        let goalsList = try readSource(root, "ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift")

        #expect(goalsList.contains("selectedGoalForAddAsset"))
        #expect(goalsList.contains("selectedAssetForAddTransaction"))
        #expect(goalsList.contains("selectedGoalForTransactionAssetPicker"))
        #expect(goalsList.contains("onAddAsset:"))
        #expect(goalsList.contains("onAddTransaction:"))
        #expect(goalsList.contains("AddAssetView(goal: goal)"))
        #expect(goalsList.contains("AddTransactionView(asset: asset)"))
        #expect(goalsList.contains("private func presentAddTransaction(for goal: Goal)"))
        #expect(!goalsList.contains("// Add asset action"))
        #expect(!goalsList.contains("// Add transaction action"))
    }

    @Test("remediated views use accessible color tokens")
    func remediatedViewsUseAccessibleColorTokens() throws {
        let root = repositoryRoot()
        let auditedPaths = [
            "ios/CryptoSavingsTracker/Views/AddTransactionView.swift",
            "ios/CryptoSavingsTracker/Views/AssetDetailView.swift",
            "ios/CryptoSavingsTracker/Views/GoalDetailView.swift",
            "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift",
            "ios/CryptoSavingsTracker/Views/Components/AdaptiveSummaryRow.swift",
            "ios/CryptoSavingsTracker/Views/Components/EmptyGoalsView.swift",
            "ios/CryptoSavingsTracker/Views/Components/ErrorBannerView.swift"
        ]
        let forbiddenPatterns = [
            ".foregroundColor(.secondary)",
            ".foregroundColor(.red)",
            ".foregroundColor(.green)",
            ".foregroundStyle(.secondary)",
            ".foregroundStyle(.tertiary)",
            ".foregroundStyle(.primary)",
            "Color(UIColor.systemGray6)",
            "Color(UIColor.systemBackground)",
            "Color(NSColor.windowBackgroundColor)",
            "Color.gray.opacity(0.1)",
            ".tint(.purple)"
        ]

        for path in auditedPaths {
            let source = try readSource(root, path)
            for pattern in forbiddenPatterns {
                #expect(!source.contains(pattern), "\(path) still contains \(pattern)")
            }
        }
    }

    @Test("transaction save failure has app level UI evidence hook")
    func transactionSaveFailureHasAppLevelUIEvidenceHook() throws {
        let root = repositoryRoot()
        let flags = try readSource(root, "ios/CryptoSavingsTracker/Utilities/UITestFlags.swift")
        let addTransaction = try readSource(root, "ios/CryptoSavingsTracker/Views/AddTransactionView.swift")
        let uiTest = try readSource(root, "ios/CryptoSavingsTrackerUITests/ExecutionUserFlowUITests.swift")

        #expect(flags.contains("UITEST_SIMULATE_TRANSACTION_SAVE_FAILURE"))
        #expect(flags.contains("consumeSimulatedTransactionSaveFailureIfNeeded"))
        #expect(flags.contains("#if DEBUG"))
        #expect(addTransaction.contains("UITestFlags.consumeSimulatedTransactionSaveFailureIfNeeded()"))
        #expect(addTransaction.contains("transactionAssetCurrencyLabel"))
        #expect(uiTest.contains("testTransactionSaveFailureKeepsSheetDraftAndRetryVisible"))
        #expect(uiTest.contains("125.50"))
        #expect(uiTest.contains("April deposit"))
        #expect(uiTest.contains("transactionAssetCurrencyLabel"))
        #expect(uiTest.contains("transactionDatePicker"))
        #expect(uiTest.contains("Transaction Not Saved"))
        #expect(uiTest.contains("Retry"))
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
