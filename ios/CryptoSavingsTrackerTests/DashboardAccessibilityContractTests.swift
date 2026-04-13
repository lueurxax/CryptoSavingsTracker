//
//  DashboardAccessibilityContractTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

struct DashboardAccessibilityContractTests {
    @Test("Dashboard accessibility copy explains what-if status and quick action prerequisites")
    func dashboardAccessibilityCopy() {
        #expect(
            DashboardAccessibilityCopy.whatIfStatusValue(onTrack: true)
                == "On track. Projected contributions reach the goal by the deadline."
        )
        #expect(
            DashboardAccessibilityCopy.whatIfStatusValue(onTrack: false)
                == "Behind. Projected contributions still fall short of the goal by the deadline."
        )
        #expect(
            DashboardAccessibilityCopy.overlayToggleHint(isEnabled: false)
                == "Double tap to show the what-if projection on the forecast chart."
        )
        #expect(
            DashboardAccessibilityCopy.overlayToggleHint(isEnabled: true)
                == "Double tap to hide the what-if projection on the forecast chart."
        )
        #expect(
            DashboardAccessibilityCopy.contributionValue(amount: 250, currency: "USD", kind: "Monthly contribution")
                == "Monthly contribution 250 US dollars"
        )
        #expect(
            DashboardAccessibilityCopy.remainingDaysValue(1)
                == "1 day remaining"
        )
        #expect(
            DashboardAccessibilityCopy.remainingDaysValue(42)
                == "42 days remaining"
        )
        #expect(
            DashboardAccessibilityCopy.quickActionHint(action: .addTransaction, hasAssets: false)
                == "Add an asset to this goal before logging a transaction."
        )
        #expect(
            DashboardAccessibilityCopy.quickActionHint(action: .addTransaction, hasAssets: true)
                == "Double tap to choose an asset and log a transaction for this goal."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryPrimaryActionHint(hasAssets: false)
                == "Double tap to add an asset for this goal before recording a transaction."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryPrimaryActionHint(hasAssets: true)
                == "Double tap to choose the asset you want to use before recording this transaction."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryDismissHint(hasAssets: false)
                == "Double tap to close this message and continue reviewing the dashboard until you are ready to add an asset."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryDismissHint(hasAssets: true)
                == "Double tap to close this message and continue reviewing the dashboard until you are ready to choose an asset."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryFooter(hasAssets: false)
                == "You can come back after linking an asset to this goal."
        )
        #expect(
            DashboardAccessibilityCopy.transactionRecoveryFooter(hasAssets: true)
                == "You can come back after linking the right asset."
        )
        #expect(
            DashboardAccessibilityCopy.assetPickerDismissHint
                == "Double tap to close asset selection and return to the dashboard."
        )
    }

    @Test("Legacy dashboard views remove single-line truncation and use accessibility helpers")
    func dashboardViewContracts() throws {
        let root = repositoryRoot()
        let metricsGrid = try readSource(root, "ios/CryptoSavingsTracker/Views/Components/DashboardMetricsGrid.swift")
        let enhancedComponents = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/EnhancedDashboardComponents.swift")
        let dashboardComponents = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift")
        let whatIfView = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/WhatIfView.swift")
        let goalDashboardScreen = try readSource(root, "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift")

        #expect(!metricsGrid.contains(".lineLimit(1)"))
        #expect(!enhancedComponents.contains(".lineLimit(1)"))
        #expect(!goalDashboardScreen.contains(".lineLimit(1)"))

        #expect(metricsGrid.contains("DashboardAccessibilityCopy.metricSummary"))
        #expect(enhancedComponents.contains("DashboardAccessibilityCopy.metricSummary"))
        #expect(dashboardComponents.contains("DashboardAccessibilityCopy.quickActionHint"))
        #expect(whatIfView.contains("DashboardAccessibilityCopy.whatIfStatusValue"))
        #expect(whatIfView.contains("DashboardAccessibilityCopy.overlayToggleHint"))
        #expect(whatIfView.contains("DashboardAccessibilityCopy.contributionValue"))
        #expect(whatIfView.contains("DashboardAccessibilityCopy.remainingDaysValue"))
        #expect(whatIfView.contains(".accessibilityLabel(\"Monthly contribution amount\")"))
        #expect(whatIfView.contains(".accessibilityLabel(\"One-time investment amount\")"))
        #expect(whatIfView.contains(".accessibilityLabel(\"Days remaining\")"))
        #expect(goalDashboardScreen.contains("DashboardAccessibilityCopy.assetSelectionLabel"))
        #expect(goalDashboardScreen.contains("DashboardAccessibilityCopy.assetPickerDismissHint"))
        #expect(goalDashboardScreen.contains("dashboard.asset_picker.dismiss"))
        #expect(dashboardComponents.contains("DashboardAccessibilityCopy.assetPickerDismissHint"))
        #expect(dashboardComponents.contains("dashboard.asset_picker.dismiss"))
        #expect(dashboardComponents.contains("goalAssets.isEmpty ? AccessibleColors.primaryInteractive : AccessibleColors.success"))
        #expect(!dashboardComponents.contains("AccessibleColors.disabled"))
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
