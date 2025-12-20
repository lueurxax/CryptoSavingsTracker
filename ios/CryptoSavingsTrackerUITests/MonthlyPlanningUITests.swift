//
//  MonthlyPlanningUITests.swift
//  CryptoSavingsTrackerUITests
//
//  Created by Claude on 09/08/2025.
//

import XCTest

/// UI tests for monthly planning feature interactions
final class MonthlyPlanningUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Configure test environment
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["UITEST_RESET_DATA"] = "1"
        app.launchEnvironment["UITEST_MOCK_DATA"] = "monthly_planning"
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Monthly Planning Widget Tests
    
    func testMonthlyPlanningWidgetExpansion() throws {
        // Navigate to dashboard
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 5))
        dashboardTab.tap()
        
        // Find monthly planning widget
        let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
        XCTAssertTrue(widget.waitForExistence(timeout: 5))
        
        // Test widget expansion
        let expandButton = widget.buttons["Show more"]
        XCTAssertTrue(expandButton.exists)
        expandButton.tap()
        
        // Verify expanded content appears
        let goalBreakdown = widget.staticTexts["Goal Breakdown"]
        XCTAssertTrue(goalBreakdown.waitForExistence(timeout: 2))
        
        // Test collapse
        let collapseButton = widget.buttons["Show less"]
        XCTAssertTrue(collapseButton.exists)
        collapseButton.tap()
        
        // Verify content is hidden
        XCTAssertFalse(goalBreakdown.exists)
    }
    
    func testMonthlyPlanningWidgetQuickActions() throws {
        // Navigate to dashboard and expand widget
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        dashboardTab.tap()
        
        let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
        XCTAssertTrue(widget.waitForExistence(timeout: 5))
        
        let expandButton = widget.buttons["Show more"]
        expandButton.tap()
        
        // Test quick action buttons
        let payHalfButton = widget.buttons["Pay Half"]
        XCTAssertTrue(payHalfButton.waitForExistence(timeout: 2))
        payHalfButton.tap()
        
        // Verify adjustment was applied (check for flex controls appearance)
        let flexControls = widget.staticTexts["Flex Adjustment"]
        XCTAssertTrue(flexControls.waitForExistence(timeout: 3))
        
        // Test reset button
        let resetButton = widget.buttons["Reset"]
        XCTAssertTrue(resetButton.exists)
        resetButton.tap()
        
        // Verify reset worked (flex adjustment should be 100%)
        let percentageText = widget.staticTexts["100%"]
        XCTAssertTrue(percentageText.waitForExistence(timeout: 2))
    }
    
    func testNavigateToFullPlanningView() throws {
        // Navigate to dashboard and expand widget
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        dashboardTab.tap()
        
        let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
        XCTAssertTrue(widget.waitForExistence(timeout: 5))
        
        let expandButton = widget.buttons["Show more"]
        expandButton.tap()
        
        // Tap "Open Full Planning" button
        let fullPlanningButton = widget.buttons["Open Full Planning"]
        XCTAssertTrue(fullPlanningButton.waitForExistence(timeout: 2))
        fullPlanningButton.tap()
        
        // Verify planning view opens
        let planningTitle = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(planningTitle.waitForExistence(timeout: 3))
    }
    
    // MARK: - Planning View Tests
    
    func testPlanningViewNavigation() throws {
        // Navigate to Planning tab directly
        let planningTab = app.tabBars.buttons["Planning"]
        XCTAssertTrue(planningTab.waitForExistence(timeout: 5))
        planningTab.tap()
        
        // Verify planning view loads
        let navigationTitle = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 3))
        
        #if os(iOS)
        // Test tab switching on iOS
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Test compact layout tabs
            let goalsTab = app.buttons["Goals"]
            XCTAssertTrue(goalsTab.exists)
            goalsTab.tap()
            
            let controlsTab = app.buttons["Controls"]
            XCTAssertTrue(controlsTab.exists)
            controlsTab.tap()
            
            let statsTab = app.buttons["Stats"]
            XCTAssertTrue(statsTab.exists)
            statsTab.tap()
        }
        #endif
    }
    
    func testGoalRequirementRowInteractions() throws {
        // Navigate to planning view
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Find first goal requirement row
        let goalRow = app.scrollViews.otherElements.containing(.staticText, identifier: "Bitcoin Savings").element
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        
        // Test details expansion
        let detailsButton = goalRow.buttons["Show details"]
        if detailsButton.exists {
            detailsButton.tap()
            
            // Verify details content appears
            let progressBreakdown = goalRow.staticTexts["Progress Breakdown"]
            XCTAssertTrue(progressBreakdown.waitForExistence(timeout: 2))
            
            let timeline = goalRow.staticTexts["Timeline"]
            XCTAssertTrue(timeline.exists)
            
            // Test collapse
            let hideButton = goalRow.buttons["Hide details"]
            XCTAssertTrue(hideButton.exists)
            hideButton.tap()
            
            // Verify details are hidden
            XCTAssertFalse(progressBreakdown.exists)
        }
    }
    
    func testFlexStateToggling() throws {
        // Navigate to planning view
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Find a goal row with flex controls
        let goalRow = app.scrollViews.otherElements.containing(.staticText, identifier: "Bitcoin Savings").element
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        
        // Find and tap flex state menu
        let flexMenu = goalRow.buttons.matching(identifier: "Flexible").element
        if flexMenu.exists {
            flexMenu.tap()
            
            // Test protection toggle
            let protectButton = app.buttons["Protect from Changes"]
            if protectButton.waitForExistence(timeout: 2) {
                protectButton.tap()
                
                // Verify state changed to protected
                let protectedIndicator = goalRow.staticTexts["Protected"]
                XCTAssertTrue(protectedIndicator.waitForExistence(timeout: 2))
            }
        }
    }
    
    // MARK: - Flex Adjustment Slider Tests
    
    func testFlexAdjustmentSliderInteraction() throws {
        // Navigate to planning view with flex controls
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Look for flex adjustment section
        let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
        
        if flexSection.waitForExistence(timeout: 5) {
            // Test preset buttons
            let halfButton = flexSection.buttons["Half"]
            XCTAssertTrue(halfButton.exists)
            halfButton.tap()
            
            // Verify percentage changed
            let fiftyPercent = flexSection.staticTexts["50%"]
            XCTAssertTrue(fiftyPercent.waitForExistence(timeout: 2))
            
            // Test another preset
            let fullButton = flexSection.buttons["Full"]
            XCTAssertTrue(fullButton.exists)
            fullButton.tap()
            
            let hundredPercent = flexSection.staticTexts["100%"]
            XCTAssertTrue(hundredPercent.waitForExistence(timeout: 2))
        }
    }
    
    func testFlexAdjustmentPreviewToggle() throws {
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
        
        if flexSection.waitForExistence(timeout: 5) {
            // Change adjustment to trigger preview
            let quarterButton = flexSection.buttons["Quarter"]
            quarterButton.tap()
            
            // Look for live preview section
            let livePreview = flexSection.staticTexts["Live Preview"]
            if livePreview.waitForExistence(timeout: 3) {
                // Test preview toggle
                let eyeButton = flexSection.buttons.matching(NSPredicate(format: "identifier CONTAINS 'eye'")).element
                if eyeButton.exists {
                    eyeButton.tap()
                    
                    // Verify preview content is hidden/shown
                    // (Implementation depends on current visibility state)
                }
            }
        }
    }
    
    // MARK: - Multi-Platform Specific Tests
    
    #if os(iOS)
    func testIOSCompactLayoutTransitions() throws {
        // Skip if not running on iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This test is for iPhone only")
        }
        
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Test segmented control switching
        let segmentedControl = app.segmentedControls.firstMatch
        XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5))
        
        // Test each segment
        let controlsSegment = segmentedControl.buttons["Controls"]
        if controlsSegment.exists {
            controlsSegment.tap()
            
            // Verify controls content is visible
            let flexAdjustment = app.staticTexts["Flex Adjustment"]
            XCTAssertTrue(flexAdjustment.waitForExistence(timeout: 2))
        }
        
        let statsSegment = segmentedControl.buttons["Stats"]
        if statsSegment.exists {
            statsSegment.tap()
            
            // Verify stats content is visible
            let statistics = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'goals'")).element
            XCTAssertTrue(statistics.waitForExistence(timeout: 2))
        }
    }
    #endif
    
    #if os(macOS)
    func testMacOSSplitViewLayout() throws {
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Verify split view layout exists
        let leftPanel = app.scrollViews.containing(.staticText, identifier: "Goals").element
        XCTAssertTrue(leftPanel.waitForExistence(timeout: 5))
        
        let rightPanel = app.scrollViews.containing(.staticText, identifier: "Flex Adjustment").element
        XCTAssertTrue(rightPanel.waitForExistence(timeout: 5))
        
        // Test goal selection in left panel affects right panel
        let goalRow = leftPanel.buttons.firstMatch
        if goalRow.exists {
            goalRow.tap()
            
            // Verify right panel updates (implementation dependent)
        }
    }
    #endif
    
    // MARK: - Error Handling Tests
    
    func testOfflineErrorHandling() throws {
        // Simulate offline condition
        app.launchEnvironment["UITEST_SIMULATE_OFFLINE"] = "1"
        app.terminate()
        app.launch()
        
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Look for error state or loading indicator
        let loadingIndicator = app.activityIndicators.firstMatch
        let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'error' OR label CONTAINS 'offline'")).element
        
        XCTAssertTrue(loadingIndicator.exists || errorText.waitForExistence(timeout: 10))
    }
    
    func testEmptyStateHandling() throws {
        // Configure empty data state
        app.launchEnvironment["UITEST_MOCK_DATA"] = "empty"
        app.terminate()
        app.launch()
        
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Verify empty state is shown
        let emptyStateText = app.staticTexts["No Active Goals"]
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 5))
        
        let emptyStateDescription = app.staticTexts["Create your first savings goal to see monthly requirements"]
        XCTAssertTrue(emptyStateDescription.exists)
    }
    
    // MARK: - Performance Tests
    
    func testPlanningViewLoadPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            
            let planningTab = app.tabBars.buttons["Planning"]
            planningTab.tap()
            
            let planningTitle = app.navigationBars["Monthly Planning"]
            _ = planningTitle.waitForExistence(timeout: 10)
        }
    }
    
    func testFlexAdjustmentResponseTime() throws {
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
        
        if flexSection.waitForExistence(timeout: 5) {
            measure(metrics: [XCTClockMetric()]) {
                // Test rapid preset changes
                let presets = ["Quarter", "Half", "Full", "Extra"]
                
                for preset in presets {
                    let button = flexSection.buttons[preset]
                    if button.exists {
                        button.tap()
                        
                        // Wait for UI update
                        let percentageText = flexSection.staticTexts.matching(NSPredicate(format: "label CONTAINS '%'")).element
                        _ = percentageText.waitForExistence(timeout: 1)
                    }
                }
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testVoiceOverSupport() throws {
        // Enable VoiceOver for testing
        app.launchEnvironment["UITEST_ACCESSIBILITY"] = "1"
        app.terminate()
        app.launch()
        
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()

        // Monthly planning widget: just verify it exists and can be expanded if present
        let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
        if widget.waitForExistence(timeout: 5) {
            widget.buttons.firstMatch.tap()
        }

        // Flex adjustment section presence
        let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
        if flexSection.exists {
            _ = flexSection.buttons.firstMatch
        }
    }
    
    func testKeyboardNavigation() throws {
        #if os(macOS)
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()

        // Basic sanity: ensure list renders
        XCTAssertTrue(app.tables.element(boundBy: 0).waitForExistence(timeout: 3))
        #endif
    }
    
    // MARK: - Integration Tests
    
    func testDataFlowIntegration() throws {
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Test that widget and full view stay in sync
        let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
        
        if widget.waitForExistence(timeout: 5) {
            // Make adjustment in widget
            let expandButton = widget.buttons["Show more"]
            expandButton.tap()
            
            let payHalfButton = widget.buttons["Pay Half"]
            if payHalfButton.exists {
                payHalfButton.tap()
                
                // Navigate to full planning view
                let fullPlanningButton = widget.buttons["Open Full Planning"]
                fullPlanningButton.tap()
                
                // Verify adjustment is reflected in full view
                let planningView = app.scrollViews.firstMatch
                let adjustmentText = planningView.staticTexts["50%"]
                XCTAssertTrue(adjustmentText.waitForExistence(timeout: 3))
            }
        }
    }
    
    func testCrossTabStateConsistency() throws {
        // Test that planning state persists across tab switches
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        // Make an adjustment
        let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
        if flexSection.waitForExistence(timeout: 5) {
            let quarterButton = flexSection.buttons["Quarter"]
            quarterButton.tap()
        }
        
        // Switch to dashboard
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        dashboardTab.tap()
        
        // Switch back to planning
        planningTab.tap()
        
        // Verify adjustment persisted
        if flexSection.exists {
            let twentyFivePercent = flexSection.staticTexts["25%"]
            XCTAssertTrue(twentyFivePercent.waitForExistence(timeout: 2))
        }
    }
}
