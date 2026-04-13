//
//  AccessibilityTests.swift
//  CryptoSavingsTrackerTests
//
//  Simplified smoke tests for accessibility utilities, marked @MainActor to
//  avoid isolation errors with shared singletons.
//

import Testing
import SwiftUI
@testable import CryptoSavingsTracker

@MainActor
struct AccessibilityTests {
    @Test("Contrast ratio sanity")
    func testContrastRatio() {
        let ratio = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.primaryInteractive,
            background: .white
        )
        #expect(ratio > 1.0)
    }

    @Test("AccessibilityManager voiceOver description basic")
    func testVoiceOverDescription() {
        let desc = AccessibilityManager.shared.voiceOverDescription(for: 100, currency: "USD")
        // May contain "USD" or full currency name "US Dollar"
        #expect(desc.contains("100") && (desc.contains("USD") || desc.contains("Dollar")))
    }

    @Test("AccessibleButton stores values")
    func testAccessibleButton() {
        let modifier = AccessibleButton(
            title: "Test",
            hint: "Do something",
            action: .addGoal,
            isEnabled: true,
            importance: .normal
        )
        #expect(modifier.title == "Test")
        #expect(modifier.hint == "Do something")
    }

    @Test("Accessibility audit flags missing label, identifier, and hit target")
    func testAuditFlagsInteractiveIssues() {
        let report = AccessibilityManager.shared.audit(elements: [
            AccessibilityAuditElement(
                kind: .button,
                label: nil,
                identifier: nil,
                isAccessibilityElement: true,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 32, height: 30),
                debugName: "Primary budget action"
            )
        ])

        #expect(report.hasIssues)
        #expect(report.criticalIssues.count == 1)
        #expect(report.warningIssues.count == 2)
        #expect(report.overallScore == 60)
    }

    @Test("Accessibility audit ignores hidden or decorative elements")
    func testAuditIgnoresHiddenAndDecorativeElements() {
        let report = AccessibilityManager.shared.audit(elements: [
            AccessibilityAuditElement(
                kind: .button,
                label: nil,
                identifier: nil,
                isAccessibilityElement: true,
                isHidden: true,
                frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                debugName: "Hidden CTA"
            ),
            AccessibilityAuditElement(
                kind: .decorative,
                label: nil,
                identifier: nil,
                isAccessibilityElement: false,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 12, height: 12),
                debugName: "Background flourish"
            )
        ])

        #expect(!report.hasIssues)
        #expect(report.overallScore == 100)
    }

    @Test("Accessibility audit reports non-accessible interactive controls")
    func testAuditFlagsInteractiveElementsExcludedFromAccessibility() {
        let report = AccessibilityManager.shared.audit(elements: [
            AccessibilityAuditElement(
                kind: .toggle,
                label: "Enable sync",
                identifier: "settings.sync.toggle",
                isAccessibilityElement: false,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 52, height: 52),
                debugName: "Sync toggle"
            )
        ])

        #expect(report.hasIssues)
        #expect(report.warningIssues.count == 1)
        #expect(report.criticalIssues.isEmpty)
    }

    @Test("Accessibility audit reports duplicate identifiers across interactive controls")
    func testAuditFlagsDuplicateAccessibilityIdentifiers() {
        let report = AccessibilityManager.shared.audit(elements: [
            AccessibilityAuditElement(
                kind: .button,
                label: "Export CSV",
                identifier: "exportCSVButton",
                isAccessibilityElement: true,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 52, height: 52),
                debugName: "Export action"
            ),
            AccessibilityAuditElement(
                kind: .button,
                label: "Retry Export",
                identifier: "exportCSVButton",
                isAccessibilityElement: true,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 52, height: 52),
                debugName: "Retry export action"
            )
        ])

        #expect(report.hasIssues)
        #expect(report.warningIssues.count == 1)
        #expect(
            report.warningIssues.first?.title
                == "Interactive elements share a duplicate accessibility identifier"
        )
    }

    @Test("Accessibility audit flags current budget sheet done button identifiers as unique")
    func testBudgetSheetDoneButtonIdentifiersAreDistinct() throws {
        let source = try String(
            contentsOfFile: "/Users/user/Library/Application Support/Chainworks Forge/worktrees/cw-улучшения-пользовательского-оп-ea93e8/ios/CryptoSavingsTracker/Views/Planning/BudgetCalculatorSheet.swift",
            encoding: .utf8
        )

        #expect(source.components(separatedBy: ".accessibilityIdentifier(\"budgetKeyboardDoneButton\")").count - 1 == 1)
        #expect(source.components(separatedBy: ".accessibilityIdentifier(\"budgetInlineDoneButton\")").count - 1 == 1)
    }

    @Test("Accessibility audit ignores duplicate identifiers on hidden interactive controls")
    func testAuditIgnoresHiddenDuplicateIdentifiers() {
        let report = AccessibilityManager.shared.audit(elements: [
            AccessibilityAuditElement(
                kind: .button,
                label: "Visible export",
                identifier: "exportCSVButton",
                isAccessibilityElement: true,
                isHidden: false,
                frame: CGRect(x: 0, y: 0, width: 52, height: 52),
                debugName: "Visible export action"
            ),
            AccessibilityAuditElement(
                kind: .button,
                label: "Hidden export",
                identifier: "exportCSVButton",
                isAccessibilityElement: true,
                isHidden: true,
                frame: CGRect(x: 0, y: 0, width: 52, height: 52),
                debugName: "Hidden export action"
            )
        ])

        #expect(!report.hasIssues)
        #expect(report.warningIssues.isEmpty)
        #expect(report.criticalIssues.isEmpty)
    }

    @Test("Settings import guidance points users to Local Bridge Sync")
    func testSettingsImportGuidance() {
        #expect(SettingsUXCopy.importDataTitle == "Import Data")
        #expect(
            SettingsUXCopy.importDataHint
                == "Double tap to open Local Bridge Sync and review import packages before applying them."
        )
        #expect(
            SettingsUXCopy.dataSectionFooter
                == "Exports create CSV snapshots. Imports are reviewed through Local Bridge Sync before changes are applied."
        )
    }

    @Test("Settings navigation hint reuses the destination name")
    func testSettingsNavigationHint() {
        #expect(
            SettingsUXCopy.navigationHint(destination: "Family Access")
                == "Double tap to open Family Access."
        )
    }
}
