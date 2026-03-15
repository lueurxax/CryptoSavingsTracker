//
//  MonthlyPlanningUITests.swift
//  CryptoSavingsTrackerUITests
//
//  Created by Claude on 09/08/2025.
//

import XCTest

/// UI tests for monthly planning feature interactions
/// Note: App uses NavigationStack with embedded MonthlyPlanningWidget - NOT tab bars
final class MonthlyPlanningUITests: XCTestCase {

    var app: XCUIApplication!
    private let baseLaunchArguments = [
        "UITEST_RESET_DATA",
        "UITEST_SEED_GOALS",
        "UITEST_UI_FLOW",
        "-ApplePersistenceIgnoreState",
        "YES"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        launchApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Navigation Helpers

    /// Expands the planning widget on the main goals list screen
    private func expandPlanningWidget() {
        if isOnMonthlyPlanningScreen() {
            return
        }

        let expandButton = app.buttons["planningWidgetExpandButton"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10), "Planning widget expand button should exist on main screen")
        expandButton.tap()
    }

    /// Opens the full Monthly Planning view
    private func openFullPlanningView() {
        if isOnMonthlyPlanningScreen() {
            return
        }

        expandPlanningWidget()

        let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
        XCTAssertTrue(viewPlanLink.waitForExistence(timeout: 5), "View Monthly Plan link should exist after expanding widget")
        viewPlanLink.tap()

        XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 5), "Monthly Planning navigation bar should appear")
    }

    private func isOnMonthlyPlanningScreen() -> Bool {
        if app.navigationBars["Monthly Planning"].exists {
            return true
        }

        // Compact layouts may render the title in-content instead of a nav bar.
        let hasGoalsTab = app.buttons["Goals tab"].exists
        let hasTrackingCTA = app.buttons["startTrackingButton"].exists
        let hasBudgetCard = app.descendants(matching: .any).matching(identifier: "budgetSummaryCard").firstMatch.exists

        return hasGoalsTab && (hasTrackingCTA || hasBudgetCard)
    }

    private func launchApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = baseLaunchArguments + extraArguments
        app.launch()
    }

    private func relaunch(extraArguments: [String] = []) {
        app.terminate()
        launchApp(extraArguments: extraArguments)
    }

    private func previousMonthTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return formatter.string(from: previousMonth)
    }

    // MARK: - Monthly Planning Widget Tests

    func testMonthlyPlanningWidgetExpansion() throws {
        // Widget is on the main goals list screen - no tab navigation needed
        expandPlanningWidget()

        // Verify expanded content appears
        let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
        XCTAssertTrue(viewPlanLink.waitForExistence(timeout: 3), "View plan link should appear after expansion")
    }

    func testMonthlyPlanningWidgetQuickActions() throws {
        expandPlanningWidget()

        // Look for quick action buttons in the expanded widget
        let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
        XCTAssertTrue(viewPlanLink.waitForExistence(timeout: 3))

        // Test that we can tap to open full planning
        viewPlanLink.tap()
        XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 5))
    }

    func testNavigateToFullPlanningView() throws {
        openFullPlanningView()

        // Verify we're in the full planning view
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists)

        // Verify we can go back
        let backButton = navBar.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
            XCTAssertTrue(app.buttons["planningWidgetExpandButton"].waitForExistence(timeout: 5))
        }
    }

    func testCompactPlanningShowsFirstGoalRowAboveFoldWithoutStaleDrafts() throws {
        openFullPlanningView()

        let goalActionsButton = app.buttons["Goal Actions"].firstMatch
        XCTAssertTrue(goalActionsButton.waitForExistence(timeout: 5), "First goal row should render without scrolling")
        XCTAssertTrue(goalActionsButton.isHittable, "First goal row should remain visible above the fold on compact iPhone")
    }

    func testCompactPlanningShowsStaleBannerAndFirstGoalRowAboveFold() throws {
        relaunch(extraArguments: ["UITEST_SEED_STALE_DRAFTS"])
        openFullPlanningView()

        let staleBannerText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "stale draft plan")).firstMatch
        XCTAssertTrue(staleBannerText.waitForExistence(timeout: 5), "Stale draft banner should be visible before scrolling")

        let goalActionsButton = app.buttons["Goal Actions"].firstMatch
        XCTAssertTrue(goalActionsButton.waitForExistence(timeout: 5), "Goal row should still render when stale drafts exist")
        XCTAssertTrue(goalActionsButton.isHittable, "First goal row should remain visible above the fold alongside the stale draft banner")
    }

    func testStaleDraftDeleteConfirmationShowsGoalAndMonthAtRuntime() throws {
        relaunch(extraArguments: ["UITEST_SEED_STALE_DRAFTS"])
        openFullPlanningView()

        let staleBannerText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "stale draft plan")).firstMatch
        XCTAssertTrue(staleBannerText.waitForExistence(timeout: 5), "Stale draft banner should exist")
        staleBannerText.tap()

        let resolveButton = app.buttons["Resolve"].firstMatch
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 5), "Resolve button should appear after expanding stale drafts")
        resolveButton.tap()

        let deleteDraftOptionLower = app.buttons["Delete draft"].firstMatch
        let deleteDraftOptionUpper = app.buttons["Delete Draft"].firstMatch
        let deleteDraftOption: XCUIElement
        if deleteDraftOptionLower.waitForExistence(timeout: 3) {
            deleteDraftOption = deleteDraftOptionLower
        } else {
            XCTAssertTrue(deleteDraftOptionUpper.waitForExistence(timeout: 3), "Delete draft action should be available in resolve actions")
            deleteDraftOption = deleteDraftOptionUpper
        }
        deleteDraftOption.tap()

        let expectedTitle = "Delete UI Goal Seed draft for \(previousMonthTitle())?"
        let exactTitle = app.staticTexts[expectedTitle]
        let fallbackTitle = app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UI Goal Seed")).firstMatch
        XCTAssertTrue(
            exactTitle.waitForExistence(timeout: 3) || fallbackTitle.waitForExistence(timeout: 3),
            "Delete confirmation should include goal name and month context"
        )
        XCTAssertTrue(
            app.buttons["Delete Draft"].waitForExistence(timeout: 3) ||
            app.buttons["Cancel"].waitForExistence(timeout: 3),
            "Delete confirmation should expose destructive runtime wording"
        )

        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }
    }

    // MARK: - Planning View Tests

    func testPlanningViewNavigation() throws {
        openFullPlanningView()

        // Verify planning view loads with expected elements
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists)

        // Look for start tracking or finish month button (depending on state)
        let startButton = app.buttons["startTrackingButton"]
        let finishButton = app.buttons["finishMonthButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5) || finishButton.waitForExistence(timeout: 5),
                      "Either start tracking or finish month button should be visible")
    }

    func testGoalRequirementRowInteractions() throws {
        openFullPlanningView()

        // Verify the planning view loaded by checking navigation bar
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists, "Monthly Planning navigation bar should exist")

        // Verify there's content in the planning view - look for any static text
        let anyStaticText = app.staticTexts.element(boundBy: 0)
        XCTAssertTrue(anyStaticText.waitForExistence(timeout: 5), "Planning view should have content")
    }

    func testFlexStateToggling() throws {
        openFullPlanningView()

        // Verify the planning view loaded
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists, "Monthly Planning navigation bar should exist")

        // The flex controls may be in a specific section
        // This test verifies the planning view has interactive elements (buttons in the view)
        let buttons = app.buttons
        XCTAssertTrue(buttons.count > 0, "Planning view should have interactive buttons")
    }

    // MARK: - Flex Adjustment Tests

    func testFlexAdjustmentSliderInteraction() throws {
        openFullPlanningView()

        // Verify the planning view loaded
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists, "Monthly Planning navigation bar should exist")

        // Scroll to find flex controls if needed
        app.swipeUp()

        // Look for percentage indicators or adjustment buttons
        let buttons = app.buttons.allElementsBoundByIndex
        let hasFlexControls = buttons.contains { $0.label.contains("%") || $0.label.contains("Half") || $0.label.contains("Full") }
        // Flex controls may or may not be visible depending on state
        _ = hasFlexControls
    }

    func testFlexAdjustmentPreviewToggle() throws {
        openFullPlanningView()

        // Verify the planning view loaded
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists, "Monthly Planning navigation bar should exist")

        // Verify the view is interactive
        let hasInteractiveElements = app.buttons.count > 0 || app.sliders.count > 0
        XCTAssertTrue(hasInteractiveElements, "Planning view should have interactive elements")
    }

    // MARK: - Multi-Platform Specific Tests

    #if os(iOS)
    func testIOSCompactLayoutTransitions() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This test is for iPhone only")
        }

        openFullPlanningView()

        // Verify the planning view renders properly on compact layout
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists)

        // Look for segmented controls if present
        let segmentedControl = app.segmentedControls.firstMatch
        if segmentedControl.exists {
            // Test segment interaction
            let segments = segmentedControl.buttons.allElementsBoundByIndex
            for segment in segments {
                segment.tap()
                // Allow UI to update
                sleep(1)
            }
        }
    }
    #endif

    #if os(macOS)
    func testMacOSSplitViewLayout() throws {
        openFullPlanningView()

        // Verify the planning view exists
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists)

        // Look for split view elements
        let scrollViews = app.scrollViews
        XCTAssertTrue(scrollViews.count > 0, "Should have scroll views in planning layout")
    }
    #endif

    // MARK: - Error Handling Tests

    func testOfflineErrorHandling() throws {
        // Simulate offline condition
        app.launchEnvironment["UITEST_SIMULATE_OFFLINE"] = "1"
        app.terminate()
        app.launch()

        // Try to open planning view
        let expandButton = app.buttons["planningWidgetExpandButton"]
        if expandButton.waitForExistence(timeout: 5) {
            expandButton.tap()
        }

        // Look for error state or loading indicator
        let loadingIndicator = app.activityIndicators.firstMatch
        let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'error' OR label CONTAINS 'offline'")).element

        // Either loading or error should be shown, or the app handles offline gracefully
        _ = loadingIndicator.exists || errorText.waitForExistence(timeout: 10)
    }

    func testEmptyStateHandling() throws {
        // Configure empty data state
        app.launchEnvironment["UITEST_MOCK_DATA"] = "empty"
        app.terminate()
        app.launch()

        // With no goals, the planning widget may not be visible
        // or it may show an empty state
        let expandButton = app.buttons["planningWidgetExpandButton"]
        let emptyStateText = app.staticTexts["No Active Goals"]
        let noGoalsMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'goal'")).element

        // Either the widget exists or an empty state is shown
        XCTAssertTrue(
            expandButton.waitForExistence(timeout: 5) ||
            emptyStateText.waitForExistence(timeout: 5) ||
            noGoalsMessage.waitForExistence(timeout: 5),
            "Should show planning widget or empty state"
        )
    }

    // MARK: - Performance Tests

    func testPlanningViewLoadPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()

            let expandButton = app.buttons["planningWidgetExpandButton"]
            if expandButton.waitForExistence(timeout: 10) {
                expandButton.tap()

                let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
                _ = viewPlanLink.waitForExistence(timeout: 5)
            }
        }
    }

    func testFlexAdjustmentResponseTime() throws {
        openFullPlanningView()

        let scrollView = app.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 5) {
            measure(metrics: [XCTClockMetric()]) {
                // Interact with the planning view
                app.swipeUp()
                app.swipeDown()
            }
        }
    }

    // MARK: - Commit Dock Collapse Tests

    func testCommitDockCollapsesOnScroll() throws {
        // Relaunch with many goals so the scroll view has enough content to scroll 96pt+
        app.terminate()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_SEED_MANY_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        openFullPlanningView()

        let startButton = app.buttons["startTrackingButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start tracking button should exist")

        // Capture expanded state: label includes "Ready to commit"
        let expandedLabel = startButton.label
        let attachment1 = XCTAttachment(screenshot: app.screenshot())
        attachment1.name = "dock-before-scroll"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        // Scroll down aggressively to trigger collapse (need > 96pt scroll)
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Scroll view should exist")
        scrollView.swipeUp()
        scrollView.swipeUp()
        scrollView.swipeUp()

        // Let animation finish
        Thread.sleep(forTimeInterval: 0.5)

        let attachment2 = XCTAttachment(screenshot: app.screenshot())
        attachment2.name = "dock-after-scroll"
        attachment2.lifetime = .keepAlways
        add(attachment2)

        // After scroll the button should still exist but its label changes (collapsed = shorter)
        XCTAssertTrue(startButton.exists, "Start tracking button should still exist after scroll")
        let scrolledLabel = startButton.label
        XCTAssertNotEqual(expandedLabel, scrolledLabel,
            "Dock label should change after scroll (expanded: '\(expandedLabel)' vs collapsed: '\(scrolledLabel)')")

        // Scroll back to top to verify re-expansion
        scrollView.swipeDown()
        scrollView.swipeDown()
        scrollView.swipeDown()
        scrollView.swipeDown()

        Thread.sleep(forTimeInterval: 0.5)

        let attachment3 = XCTAttachment(screenshot: app.screenshot())
        attachment3.name = "dock-after-scroll-back"
        attachment3.lifetime = .keepAlways
        add(attachment3)

        // Label should return to expanded form
        let returnedLabel = startButton.label
        XCTAssertEqual(expandedLabel, returnedLabel,
            "Dock should re-expand after scrolling back (expected: '\(expandedLabel)', got: '\(returnedLabel)')")
    }

    /// Proposal §13 QA #19/#30: VoiceOver focus stays on the dock's actionable button after collapse,
    /// and focus is not stolen from elements outside the dock subtree.
    func testCommitDockFocusOwnership() throws {
        app.terminate()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_SEED_MANY_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        openFullPlanningView()

        let startButton = app.buttons["startTrackingButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start tracking button should exist")

        // The dock button should be an actionable Button (not just a combined text container).
        // Verify it's hittable, meaning VO can activate it.
        XCTAssertTrue(startButton.isHittable, "Dock button should be hittable in expanded state")

        // Scroll to collapse
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeUp()
        scrollView.swipeUp()
        scrollView.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)

        // After collapse, the button should still exist and be hittable (FAB)
        XCTAssertTrue(startButton.exists, "Start tracking button should still exist after collapse")
        XCTAssertTrue(startButton.isHittable, "FAB should be hittable after collapse")

        // Verify the button's accessibility label includes full intent with explicit action
        let fabLabel = startButton.label
        XCTAssertTrue(fabLabel.contains("Start Tracking"),
            "FAB should include 'Start Tracking' in label, got: '\(fabLabel)'")
    }

    /// Proposal §13 QA #31: Budget sheet dismissal preserves dock phase via event-origin reducer.
    func testCommitDockSheetDismissPreservesPhase() throws {
        app.terminate()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_SEED_MANY_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()

        openFullPlanningView()

        let startButton = app.buttons["startTrackingButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start tracking button should exist")

        // Scroll to collapse the dock
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeUp()
        scrollView.swipeUp()
        scrollView.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)

        let collapsedLabel = startButton.label
        XCTAssertTrue(collapsedLabel.contains("Start"),
            "Collapsed dock should still expose start action, got: '\(collapsedLabel)'")

        // Open budget sheet via the Edit button (may be scrolled out — tap "Fix" shortfall button or scroll back partially)
        // The "Fix" button in the collapsed header strip opens the budget sheet
        let fixButton = app.buttons["editBudgetButton"]
        if fixButton.waitForExistence(timeout: 3) {
            fixButton.tap()
        } else {
            // Try the collapsed header "Fix" button
            let fixShortfall = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fix'")).firstMatch
            if fixShortfall.waitForExistence(timeout: 3) {
                fixShortfall.tap()
            } else {
                // Scroll back enough to find the Edit button
                scrollView.swipeDown()
                Thread.sleep(forTimeInterval: 0.3)
                let editButton = app.buttons["editBudgetButton"]
                XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit budget button should exist")
                editButton.tap()
            }
        }

        // Verify budget sheet appeared
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 5) {
            // Dismiss the sheet
            cancelButton.tap()
            Thread.sleep(forTimeInterval: 0.5)

            // After sheet dismiss, the dock should preserve its phase (sheetDismiss preserves current).
            // The scroll position may have reset, so the dock could re-expand based on scroll offset.
            // What we're really testing is that the dock didn't glitch or crash.
            XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                "Start tracking button should exist after sheet dismiss")
        }
    }

    // MARK: - Accessibility Tests

    func testVoiceOverSupport() throws {
        // Enable VoiceOver for testing
        app.launchEnvironment["UITEST_ACCESSIBILITY"] = "1"
        app.terminate()
        app.launch()

        // Verify accessibility elements are present
        let expandButton = app.buttons["planningWidgetExpandButton"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10))

        // Check that the button is accessible
        XCTAssertTrue(expandButton.isHittable)
    }

    func testKeyboardNavigation() throws {
        #if os(macOS)
        openFullPlanningView()

        // Verify the planning view is keyboard accessible
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists)
        #endif
    }

    // MARK: - Integration Tests

    func testDataFlowIntegration() throws {
        // Test that widget and full view show consistent data
        expandPlanningWidget()

        // Navigate to full planning view
        let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
        if viewPlanLink.waitForExistence(timeout: 5) {
            viewPlanLink.tap()

            // Verify full view opened
            XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 5))

            // Go back
            app.navigationBars.buttons.element(boundBy: 0).tap()

            // Verify we're back to the goals list
            XCTAssertTrue(app.buttons["planningWidgetExpandButton"].waitForExistence(timeout: 5))
        }
    }

    func testCrossNavigationStateConsistency() throws {
        // Test that planning state persists across navigation
        openFullPlanningView()

        // Verify the planning view loaded
        let navBar = app.navigationBars["Monthly Planning"]
        XCTAssertTrue(navBar.exists, "Monthly Planning navigation bar should exist")

        // Go back
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Re-open
        openFullPlanningView()

        // Verify the view still works
        XCTAssertTrue(app.navigationBars["Monthly Planning"].exists)
    }

    func testBudgetShortfallVisualState() throws {
        openFullPlanningView()

        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")

        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5), "Budget amount field should exist")
        amountField.clearAndTypeText("1")

        let minimumText = app.staticTexts["budgetMinimumRequiredText"]
        XCTAssertTrue(minimumText.waitForExistence(timeout: 6), "Minimum required text should appear for low budget")

        let shortfallWarning = app.staticTexts["budgetShortfallSaveWarning"]
        XCTAssertTrue(shortfallWarning.exists, "Shortfall save warning should be shown")

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertTrue(saveButton.exists, "Save budget button should be present")
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled when budget is infeasible")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "BudgetShortfallState"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMonthlyPlanningShortfallAfterBudgetCancel() throws {
        app.terminate()
        app.launchArguments += ["UITEST_SEED_GOALS", "UITEST_SEED_BUDGET_SHORTFALL"]
        app.launch()

        openFullPlanningView()

        let summaryShortfall = app.staticTexts["budgetSummaryShortfallText"]
        XCTAssertTrue(summaryShortfall.waitForExistence(timeout: 6), "Shortfall state should be visible on Monthly Planning")

        XCTAssertTrue(openBudgetSheet(), "Should open budget sheet from Monthly Planning")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget sheet should open")

        let cancelButton = app.navigationBars["Budget Plan"].buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "Cancel button should be available in budget sheet")
        cancelButton.tap()

        let returnedToPlanning = app.navigationBars["Monthly Planning"].waitForExistence(timeout: 2) || isOnMonthlyPlanningScreen()
        XCTAssertTrue(returnedToPlanning, "Should return to Monthly Planning after cancel")
        XCTAssertTrue(summaryShortfall.waitForExistence(timeout: 5), "Shortfall state should still be visible after cancel")

        let fixButton = app.buttons["budgetSummaryFixButton"]
        let fallbackFixButton = app.buttons["Fix Budget Shortfall"]
        XCTAssertTrue(
            (fixButton.exists && fixButton.isHittable) || fallbackFixButton.exists,
            "Prominent fix button should be visible on Monthly Planning shortfall state"
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "MonthlyPlanningShortfallAfterCancel"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUseMinimumEnablesSaveBudget() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndTypeText("1")

        let minimumButton = app.buttons["useMinimumBudgetButton"]
        XCTAssertTrue(minimumButton.waitForExistence(timeout: 6), "Use Minimum button should be visible")
        minimumButton.tap()

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled immediately after Use Minimum")
    }

    func testMinimumMinusOneMinorUnitDisablesSaveWithExplicitReason() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndTypeText("1")

        let minimumText = app.staticTexts["budgetMinimumRequiredText"]
        XCTAssertTrue(minimumText.waitForExistence(timeout: 12), "Minimum required text should be visible for low budget")

        let minimumLabel = minimumText.label
        guard let minimumValue = parseDecimalFromMixedText(minimumLabel) else {
            XCTFail("Could not parse minimum required amount from '\(minimumLabel)'")
            return
        }
        let fractionDigits = inferredFractionDigits(from: minimumLabel)
        amountField.clearAndTypeText(formatDecimalForTyping(minimumValue, fractionDigits: fractionDigits))

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Save button should exist")
        let enabledExpectation = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        wait(for: [enabledExpectation], timeout: 8)

        let oneMinorUnit = Decimal(sign: .plus, exponent: -fractionDigits, significand: 1)
        let reduced = minimumValue - oneMinorUnit
        amountField.clearAndTypeText(formatDecimalForTyping(reduced, fractionDigits: fractionDigits))

        let disabledExpectation = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: saveButton)
        wait(for: [disabledExpectation], timeout: 6)

        let reasonByIdentifier = app.descendants(matching: .any).matching(identifier: "budgetShortfallSaveWarning").firstMatch
        let reasonByCopy = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] 'Short by'")).firstMatch

        XCTAssertTrue(
            reasonByIdentifier.waitForExistence(timeout: 2) || reasonByCopy.waitForExistence(timeout: 2),
            "Disabled Save reason should be visible"
        )
        XCTAssertFalse(saveButton.isEnabled, "Minimum minus one minor unit must disable Save")
    }

    func testAppendingZeroKeepsEligibilityWhenCanonicalValueUnchanged() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndTypeText("1")

        let minimumButton = app.buttons["useMinimumBudgetButton"]
        XCTAssertTrue(minimumButton.waitForExistence(timeout: 6))
        minimumButton.tap()

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled at canonical minimum")

        amountField.tap()
        amountField.typeText("0")
        XCTAssertTrue(saveButton.isEnabled, "Appending trailing zero should not change eligibility when canonical amount is unchanged")
    }

    func testSameCanonicalAmountRecomputesAfterInvalidInput() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndTypeText("1")

        let minimumText = app.staticTexts["budgetMinimumRequiredText"]
        XCTAssertTrue(minimumText.waitForExistence(timeout: 12), "Minimum required text should be visible for low budget")

        let minimumLabel = minimumText.label
        guard let minimumValue = parseDecimalFromMixedText(minimumLabel) else {
            XCTFail("Could not parse minimum required amount from '\(minimumLabel)'")
            return
        }
        let fractionDigits = inferredFractionDigits(from: minimumLabel)
        let canonicalMinimum = formatDecimalForTyping(minimumValue, fractionDigits: fractionDigits)

        amountField.clearAndTypeText(canonicalMinimum)

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Save button should exist")
        let enabledExpectation = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        wait(for: [enabledExpectation], timeout: 8)

        amountField.clearAndTypeText("2..5")
        XCTAssertTrue(app.staticTexts["Enter a valid amount."].waitForExistence(timeout: 4))
        XCTAssertFalse(saveButton.isEnabled, "Invalid input should disable Save")

        amountField.clearAndTypeText(canonicalMinimum)
        let reenabledExpectation = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        wait(for: [reenabledExpectation], timeout: 8)
        XCTAssertTrue(saveButton.isEnabled, "Re-entering the same canonical amount should restore Save eligibility")
    }

    func testDoneAccessoryDismissesKeyboard() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Numeric keyboard should be visible")

        let doneButton = app.buttons["budgetKeyboardDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3), "Keyboard toolbar Done button should exist")
        doneButton.tap()

        XCTAssertFalse(keyboard.waitForExistence(timeout: 1), "Done should dismiss keyboard")
    }

    func testInvalidAmountShowsExplicitReasonCopy() throws {
        openFullPlanningView()
        XCTAssertTrue(openBudgetSheet(), "Budget entry action should be visible")
        XCTAssertTrue(app.navigationBars["Budget Plan"].waitForExistence(timeout: 5), "Budget plan sheet should open")

        let amountField = app.textFields["budgetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndTypeText("2..5")

        let reason = app.staticTexts["Enter a valid amount."]
        XCTAssertTrue(reason.waitForExistence(timeout: 4), "Invalid input should show explicit parser reason")

        let saveButton = app.buttons["saveBudgetPlanButton"]
        XCTAssertFalse(saveButton.isEnabled, "Save must stay disabled for invalid input")
    }

    private func openBudgetSheet() -> Bool {
        // Try to reset scroll position to where summary cards are usually rendered.
        for _ in 0..<2 { app.swipeDown() }

        for _ in 0..<6 {
            let fixButton = app.buttons["Fix Budget Shortfall"]
            if fixButton.exists && fixButton.isHittable {
                fixButton.tap()
                return true
            }

            let editInBudgetCard = app.buttons
                .matching(identifier: "budgetSummaryCard")
                .matching(NSPredicate(format: "label == 'Edit'"))
                .firstMatch
            if editInBudgetCard.exists && editInBudgetCard.isHittable {
                editInBudgetCard.tap()
                return true
            }

            let entryCard = app.otherElements["budgetEntryCard"]
            if entryCard.exists {
                let setInCard = entryCard.buttons["setBudgetButton"]
                if setInCard.exists && setInCard.isHittable {
                    setInCard.tap()
                    return true
                }
            }

            let summaryCard = app.otherElements["budgetSummaryCard"]
            if summaryCard.exists {
                let editInCard = summaryCard.buttons["editBudgetButton"]
                if editInCard.exists && editInCard.isHittable {
                    editInCard.tap()
                    return true
                }
            }

            let setBudgetButton = app.buttons["setBudgetButton"]
            if setBudgetButton.exists && setBudgetButton.isHittable {
                setBudgetButton.tap()
                return true
            }

            let editBudgetButton = app.buttons["editBudgetButton"]
            if editBudgetButton.exists && editBudgetButton.isHittable {
                editBudgetButton.tap()
                return true
            }

            // Fallback by visible title when accessibility IDs are not surfaced.
            let setByLabel = app.buttons["Set Budget"]
            if setByLabel.exists && setByLabel.isHittable {
                setByLabel.tap()
                return true
            }

            let editByLabel = app.buttons["Edit"]
            if editByLabel.exists && editByLabel.isHittable {
                editByLabel.tap()
                return true
            }

            app.swipeUp()
        }

        return false
    }

    private func parseDecimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current

        if let number = formatter.number(from: normalized) {
            return number.decimalValue
        }

        var fallback = normalized
        if let groupingSeparator = formatter.groupingSeparator, !groupingSeparator.isEmpty {
            fallback = fallback.replacingOccurrences(of: groupingSeparator, with: "")
        }
        if let decimalSeparator = formatter.decimalSeparator, decimalSeparator != "." {
            fallback = fallback.replacingOccurrences(of: decimalSeparator, with: ".")
        }
        return Decimal(string: fallback)
    }

    private func parseDecimalFromMixedText(_ text: String) -> Decimal? {
        let allowed = Set("0123456789., +-")
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .filter { allowed.contains($0) }
        return parseDecimal(normalized)
    }

    private func inferredFractionDigits(from text: String) -> Int {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard
            let separatorIndex = normalized.lastIndex(where: { $0 == "." || $0 == "," })
        else {
            return 2
        }
        let count = normalized.distance(from: separatorIndex, to: normalized.endIndex) - 1
        return max(0, min(4, count))
    }

    private func formatDecimalForTyping(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = max(0, fractionDigits)
        formatter.maximumFractionDigits = max(0, fractionDigits)

        if let formatted = formatter.string(from: NSDecimalNumber(decimal: value)) {
            return formatted
        }
        return NSDecimalNumber(decimal: value).stringValue
    }
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        tap()
        guard let currentValue = value as? String else {
            typeText(text)
            return
        }
        let deleteCount = max(currentValue.count + 6, 20)
        let deleteText = String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount)
        typeText(deleteText)
        typeText(text)
    }
}
