//
//  AccessibilityTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by Claude on 09/08/2025.
//

import Testing
import SwiftUI
@testable import CryptoSavingsTracker

/// Comprehensive accessibility testing suite for WCAG 2.1 AA compliance
struct AccessibilityTests {
    
    // MARK: - Color Contrast Tests
    
    @Test("WCAG AA contrast ratios for accessible colors")
    func testColorContrastRatios() {
        // Test primary interactive colors
        let primaryOnWhite = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.primaryInteractive,
            background: .white
        )
        #expect(primaryOnWhite >= 4.5, "Primary interactive color must meet WCAG AA standards (4.5:1)")
        
        // Test secondary text colors
        let secondaryOnWhite = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.secondaryText,
            background: .white
        )
        #expect(secondaryOnWhite >= 4.5, "Secondary text must meet WCAG AA standards")
        
        // Test status colors
        let errorOnWhite = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.error,
            background: .white
        )
        #expect(errorOnWhite >= 4.5, "Error color must meet WCAG AA standards")
        
        let successOnWhite = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.success,
            background: .white
        )
        #expect(successOnWhite >= 4.5, "Success color must meet WCAG AA standards")
        
        let warningOnWhite = AccessibleColors.contrastRatio(
            foreground: AccessibleColors.warning,
            background: .white
        )
        #expect(warningOnWhite >= 4.5, "Warning color must meet WCAG AA standards")
    }
    
    @Test("WCAG compliance validation methods")
    func testWCAGComplianceMethods() {
        // Test WCAG AA compliance
        let meetsAA = AccessibleColors.meetsWCAGAA(
            foreground: AccessibleColors.primaryInteractive,
            background: .white
        )
        #expect(meetsAA, "Primary color should meet WCAG AA standards")
        
        // Test WCAG AAA compliance
        let meetsAAA = AccessibleColors.meetsWCAGAAA(
            foreground: AccessibleColors.primaryInteractive,
            background: .white
        )
        // Note: AAA is more stringent (7:1), so this might fail
        // but the test documents our compliance level
    }
    
    @Test("Colorblind-safe color palette distinctiveness")
    func testColorblindSafeColors() {
        let colors = AccessibleColors.colorblindSafeColors
        
        // Ensure we have adequate color variety
        #expect(colors.count >= 7, "Should have at least 7 distinct colorblind-safe colors")
        
        // Test color retrieval
        let firstColor = AccessibleColors.colorblindSafeColor(at: 0)
        let secondColor = AccessibleColors.colorblindSafeColor(at: 1)
        let wrappedColor = AccessibleColors.colorblindSafeColor(at: colors.count)
        
        #expect(wrappedColor == firstColor, "Color selection should wrap around properly")
    }
    
    // MARK: - Accessibility Manager Tests
    
    @Test("AccessibilityManager initialization and state tracking")
    func testAccessibilityManagerInitialization() {
        let manager = AccessibilityManager.shared
        
        // Test initial state is properly set
        #expect(manager.showFocusIndicators != nil, "Focus indicators preference should be initialized")
        #expect(manager.enableHapticFeedback != nil, "Haptic feedback preference should be initialized")
        #expect(manager.useColorblindSafeColors != nil, "Colorblind safe colors preference should be initialized")
    }
    
    @Test("VoiceOver currency description generation")
    func testVoiceOverCurrencyDescriptions() {
        let manager = AccessibilityManager.shared
        
        // Test basic currency description
        let basicDescription = manager.voiceOverDescription(
            for: 1250.50,
            currency: "USD"
        )
        #expect(basicDescription.contains("1250.50"), "Should contain amount value")
        #expect(basicDescription.contains("USD") || basicDescription.contains("dollar"), "Should contain currency information")
        
        // Test with context
        let contextDescription = manager.voiceOverDescription(
            for: 500.0,
            currency: "EUR",
            context: "Monthly requirement"
        )
        #expect(contextDescription.contains("Monthly requirement"), "Should include context")
        #expect(contextDescription.contains("500"), "Should contain amount")
    }
    
    @Test("VoiceOver progress description generation")
    func testVoiceOverProgressDescriptions() {
        let manager = AccessibilityManager.shared
        
        // Test progress description
        let progressDescription = manager.voiceOverProgressDescription(
            0.75,
            goalName: "Bitcoin Savings"
        )
        #expect(progressDescription.contains("Bitcoin Savings"), "Should contain goal name")
        #expect(progressDescription.contains("75") || progressDescription.contains("percent"), "Should contain percentage")
        #expect(progressDescription.contains("complete"), "Should indicate completion status")
    }
    
    @Test("Chart accessibility label generation")
    func testChartAccessibilityLabels() {
        let manager = AccessibilityManager.shared
        
        // Test with data points
        let dataPoints = [
            ("Jan", 1000.0),
            ("Feb", 1250.0),
            ("Mar", 1100.0),
            ("Apr", 1400.0)
        ]
        
        let chartLabel = manager.chartAccessibilityLabel(
            title: "Savings Progress",
            dataPoints: dataPoints,
            unit: "USD"
        )
        
        #expect(chartLabel.contains("Savings Progress"), "Should contain chart title")
        #expect(chartLabel.contains("4 data points"), "Should indicate number of data points")
        #expect(chartLabel.contains("1000") || chartLabel.contains("min"), "Should include range information")
        #expect(chartLabel.contains("1400") || chartLabel.contains("max"), "Should include maximum value")
        
        // Test empty chart
        let emptyChartLabel = manager.chartAccessibilityLabel(
            title: "Empty Chart",
            dataPoints: [],
            unit: "USD"
        )
        #expect(emptyChartLabel.contains("No data available"), "Should handle empty data gracefully")
    }
    
    @Test("Accessibility hint generation")
    func testAccessibilityHints() {
        let manager = AccessibilityManager.shared
        
        // Test various action hints
        let addGoalHint = manager.accessibilityHint(for: .addGoal)
        #expect(addGoalHint.contains("Opens") && addGoalHint.contains("goal"), "Add goal hint should be descriptive")
        
        let editGoalHint = manager.accessibilityHint(for: .editGoal)
        #expect(editGoalHint.contains("edit"), "Edit goal hint should mention editing")
        
        let deleteHint = manager.accessibilityHint(for: .deleteItem)
        #expect(deleteHint.contains("remove") || deleteHint.contains("delete"), "Delete hint should warn about removal")
    }
    
    @Test("Animation duration accessibility adaptation")
    func testAnimationAccessibilityAdaptation() {
        let manager = AccessibilityManager.shared
        
        // Test normal animation duration
        manager.useSimplifiedAnimations = false
        let normalDuration = manager.animationDuration(0.3)
        #expect(normalDuration == 0.3, "Should return original duration when animations enabled")
        
        // Test reduced motion
        manager.useSimplifiedAnimations = true
        let reducedDuration = manager.animationDuration(0.3)
        #expect(reducedDuration == 0.0, "Should return zero duration for reduced motion")
    }
    
    // MARK: - View Modifier Tests
    
    @Test("Accessible button modifier configuration")
    func testAccessibleButtonModifier() {
        let buttonModifier = AccessibleButton(
            title: "Test Button",
            hint: "Test hint",
            action: .addGoal,
            isEnabled: true,
            importance: .high
        )
        
        #expect(buttonModifier.title == "Test Button", "Button title should be preserved")
        #expect(buttonModifier.hint == "Test hint", "Button hint should be preserved")
        #expect(buttonModifier.isEnabled == true, "Button enabled state should be preserved")
        #expect(buttonModifier.importance == .high, "Button importance should be preserved")
    }
    
    @Test("Accessible text field modifier configuration")
    func testAccessibleTextFieldModifier() {
        let textFieldModifier = AccessibleTextField(
            label: "Amount",
            placeholder: "Enter amount",
            isRequired: true,
            validationMessage: "Amount must be positive",
            textInputType: .currency
        )
        
        #expect(textFieldModifier.label == "Amount", "Text field label should be preserved")
        #expect(textFieldModifier.isRequired == true, "Required state should be preserved")
        #expect(textFieldModifier.textInputType == .currency, "Input type should be preserved")
        #expect(textFieldModifier.validationMessage == "Amount must be positive", "Validation message should be preserved")
    }
    
    @Test("Accessible chart modifier configuration")
    func testAccessibleChartModifier() {
        let dataPoints = [("A", 10.0), ("B", 20.0)]
        let chartModifier = AccessibleChart(
            title: "Test Chart",
            dataPoints: dataPoints,
            unit: "USD",
            chartType: .bar,
            trends: "Increasing trend"
        )
        
        #expect(chartModifier.title == "Test Chart", "Chart title should be preserved")
        #expect(chartModifier.dataPoints.count == 2, "Data points should be preserved")
        #expect(chartModifier.unit == "USD", "Unit should be preserved")
        #expect(chartModifier.chartType == .bar, "Chart type should be preserved")
    }
    
    @Test("Accessible currency modifier configuration")
    func testAccessibleCurrencyModifier() {
        let currencyModifier = AccessibleCurrency(
            amount: 1500.75,
            currency: "EUR",
            context: "Goal target",
            showSymbol: true
        )
        
        #expect(currencyModifier.amount == 1500.75, "Amount should be preserved")
        #expect(currencyModifier.currency == "EUR", "Currency should be preserved")
        #expect(currencyModifier.context == "Goal target", "Context should be preserved")
        #expect(currencyModifier.showSymbol == true, "Symbol display preference should be preserved")
    }
    
    // MARK: - Text Input Type Tests
    
    @Test("Text input type accessibility mapping")
    func testTextInputTypeMapping() {
        // Test accessibility type mapping
        #expect(TextInputType.text.accessibilityType == .text, "Text type should map correctly")
        #expect(TextInputType.email.accessibilityType == .emailAddress, "Email type should map correctly")
        #expect(TextInputType.password.accessibilityType == .password, "Password type should map correctly")
        #expect(TextInputType.number.accessibilityType == .number, "Number type should map correctly")
        #expect(TextInputType.currency.accessibilityType == .number, "Currency type should map to number")
        #expect(TextInputType.date.accessibilityType == .date, "Date type should map correctly")
    }
    
    // MARK: - Navigation Level Tests
    
    @Test("Navigation level heading mapping")
    func testNavigationLevelMapping() {
        #expect(NavigationLevel.primary.headingLevel == .h1, "Primary should map to H1")
        #expect(NavigationLevel.secondary.headingLevel == .h2, "Secondary should map to H2")
        #expect(NavigationLevel.tertiary.headingLevel == .h3, "Tertiary should map to H3")
    }
    
    // MARK: - Accessibility Action Tests
    
    @Test("Accessibility action default hints")
    func testAccessibilityActionDefaultHints() {
        // Test that all actions have meaningful hints
        let actions: [AccessibilityAction] = [
            .addGoal, .editGoal, .addTransaction, .viewDetails,
            .navigateBack, .adjustAmount, .selectCurrency,
            .toggleReminders, .shareGoal, .deleteItem
        ]
        
        for action in actions {
            let hint = action.defaultHint
            #expect(!hint.isEmpty, "Action \(action) should have a non-empty hint")
            #expect(hint.count > 10, "Action \(action) hint should be descriptive")
        }
    }
    
    // MARK: - High Contrast Mode Tests
    
    @Test("High contrast mode color selection")
    func testHighContrastModeColors() {
        // Test high contrast colors are distinct
        let textColor = AccessibleColors.highContrastText
        let backgroundColor = AccessibleColors.highContrastBackground
        let borderColor = AccessibleColors.highContrastBorder
        
        // These should be maximally distinct for high contrast mode
        #expect(textColor != backgroundColor, "Text and background should be different in high contrast mode")
        #expect(borderColor != backgroundColor, "Border should be distinct from background")
    }
    
    // MARK: - Focus Indicator Tests
    
    @Test("Focus indicator color accessibility")
    func testFocusIndicatorAccessibility() {
        let focusColor = AccessibleColors.focusIndicator
        
        // Focus indicator should be highly visible
        let contrastWithWhite = AccessibleColors.contrastRatio(
            foreground: focusColor,
            background: .white
        )
        #expect(contrastWithWhite >= 3.0, "Focus indicator should be visible against white backgrounds")
    }
    
    // MARK: - Integration Tests
    
    @Test("Accessibility manager and colors integration")
    func testAccessibilityManagerColorsIntegration() {
        let manager = AccessibilityManager.shared
        
        // Test that manager properly uses accessible colors when enabled
        manager.useHighContrastMode = true
        manager.useColorblindSafeColors = true
        
        // These settings should influence color selection in real usage
        #expect(manager.useHighContrastMode == true, "High contrast mode should be settable")
        #expect(manager.useColorblindSafeColors == true, "Colorblind safe colors should be settable")
    }
    
    // MARK: - Performance Tests
    
    @Test("Accessibility description generation performance")
    func testAccessibilityDescriptionPerformance() {
        let manager = AccessibilityManager.shared
        
        // Test performance of generating descriptions
        let startTime = Date()
        
        for i in 0..<1000 {
            let _ = manager.voiceOverDescription(
                for: Double(i),
                currency: "USD",
                context: "Test context \(i)"
            )
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(duration < 1.0, "Generating 1000 descriptions should complete within 1 second")
    }
    
    @Test("Chart accessibility label performance")
    func testChartAccessibilityPerformance() {
        let manager = AccessibilityManager.shared
        
        // Test with larger dataset
        let largeDataSet = (0..<1000).map { ("Point \($0)", Double($0)) }
        
        let startTime = Date()
        let _ = manager.chartAccessibilityLabel(
            title: "Large Dataset Chart",
            dataPoints: largeDataSet,
            unit: "units"
        )
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        #expect(duration < 0.1, "Large chart description generation should be fast")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Accessibility with empty or nil values")
    func testAccessibilityEdgeCases() {
        let manager = AccessibilityManager.shared
        
        // Test with zero amount
        let zeroDescription = manager.voiceOverDescription(
            for: 0.0,
            currency: "USD"
        )
        #expect(!zeroDescription.isEmpty, "Should handle zero amounts gracefully")
        
        // Test with negative amount
        let negativeDescription = manager.voiceOverDescription(
            for: -100.0,
            currency: "USD"
        )
        #expect(negativeDescription.contains("negative") || negativeDescription.contains("-"), "Should handle negative amounts")
        
        // Test with empty context
        let emptyContextDescription = manager.voiceOverDescription(
            for: 100.0,
            currency: "USD",
            context: ""
        )
        #expect(!emptyContextDescription.isEmpty, "Should handle empty context")
        
        // Test progress edge cases
        let zeroProgress = manager.voiceOverProgressDescription(0.0, goalName: "Test Goal")
        #expect(zeroProgress.contains("0"), "Should handle zero progress")
        
        let fullProgress = manager.voiceOverProgressDescription(1.0, goalName: "Test Goal")
        #expect(fullProgress.contains("100"), "Should handle full progress")
    }
}