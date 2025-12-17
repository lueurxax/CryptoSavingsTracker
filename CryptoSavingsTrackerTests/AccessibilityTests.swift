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
}
