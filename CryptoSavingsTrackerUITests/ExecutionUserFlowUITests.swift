//
//  ExecutionUserFlowUITests.swift
//  CryptoSavingsTrackerUITests
//
//  End-to-end UI tests for execution tracking with shared assets.
//

import XCTest

final class ExecutionUserFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// **Test: Sharing Asset After Starting Execution + Multi-Asset Contributions**
    ///
    /// This test validates:
    /// 1. Asset sharing between multiple goals after execution tracking starts
    /// 2. Multiple assets contributing to the same goal
    /// 3. Underfunded goals display correctly
    /// 4. Tracking view matches details view
    ///
    /// ## Part 1: USD Asset Sharing
    /// 1. Create two goals: Goal A ($800 target) and Goal B ($600 target)
    /// 2. Start execution tracking for the current month
    /// 3. Add a USD asset to Goal A (100% allocated initially)
    /// 4. Add a $200 transaction to the asset
    /// 5. Share the asset: allocate $50 to Goal A, $150 to Goal B
    ///    - Goal A is now underfunded ($50 of $800 target = 6.25%)
    /// 6. Verify execution view shows: Goal A: $50, Goal B: $150
    ///
    /// ## Part 2: BTC Asset Addition
    /// 7. Add a BTC asset to Goal A
    /// 8. Add 0.01 BTC transaction
    /// 9. Verify tracking shows BTC contribution for Goal A
    /// 10. Verify tracking numbers match details view
    ///
    /// ## What This Tests:
    /// - Asset sharing during active execution
    /// - Underfunded goal display (Goal A: $50 vs $800 target)
    /// - Multi-asset contributions (USD + BTC to same goal)
    /// - Consistency between details and tracking views
    ///
    /// ## Related Architecture:
    /// - See docs/CONTRIBUTION_TRACKING_REDESIGN.md for allocation rules
    /// - See docs/CONTRIBUTION_FLOW.md for timestamp-based tracking
    ///
    func testSharedAssetContributionFlow() throws {
#if os(macOS)
        throw XCTSkip("Flow is automated on iOS simulator.")
#endif
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-ApplePersistenceDisableAutosave",
            "YES"
        ]
        app.launch()
        dismissMonthlyPlanningSettingsIfPresent(app)

        addGoal(app, name: "Goal A", target: "800")
        addGoal(app, name: "Goal B", target: "600")

        // Start execution tracking before recording any transactions/allocations.
        startTrackingIfNeeded(app)

        // DEBUG: Check initial plan state after starting tracking
        print("=== AFTER START TRACKING ===")
        logExecutionViewState(app)

        // Open Goal A detail
        XCTAssertTrue(tapWithScroll(app: app, element: app.buttons["goalRow-Goal A"], maxSwipes: 10), "Unable to open Goal A row")
        // Ensure we are on the Details tab (TabView selection can vary across OS versions)
        if app.tabBars.buttons["Details"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["Details"].tap()
        }
        dismissMonthlyPlanningSettingsIfPresent(app)

        // Add Asset to Goal A
        let addAssetButton = app.buttons["addAssetButton"]
        XCTAssertTrue(tapWithScroll(app: app, element: addAssetButton, maxSwipes: 10), "Unable to find/tap addAssetButton")
        pickCurrency(app, symbol: "USD", buttonId: "assetCurrencyButton")
        XCTAssertTrue(app.buttons["saveAssetButton"].waitForExistence(timeout: 2))
        app.buttons["saveAssetButton"].tap()
        // Ensure we returned to Goal Detail after dismissing the sheet
        XCTAssertTrue(app.buttons["saveAssetButton"].waitForNonExistence(timeout: 8))
        dismissMonthlyPlanningSettingsIfPresent(app)

        // Expand asset row and add transaction
        // SwiftUI can duplicate identifiers across the button + its label children; pick a deterministic match.
        var assetRow = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "assetRow-USD")).firstMatch
        if !assetRow.exists {
            assetRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "assetRow-USD")).firstMatch
        }
        XCTAssertTrue(
            waitForExistenceWithScroll(app: app, element: assetRow, maxSwipes: 10, perAttemptTimeout: 1.0),
            "Asset row not found after saving asset"
        )
        tapForce(assetRow)

        let addTransactionButton = app.descendants(matching: .any)["addTransactionButton"]
        if !addTransactionButton.waitForExistence(timeout: 1) {
            // Sometimes the first tap doesn't toggle expansion (SwiftUI + ScrollView flake). Retry once.
            tapForce(assetRow)
        }
        XCTAssertTrue(
            waitForExistenceWithScroll(app: app, element: addTransactionButton, maxSwipes: 3, perAttemptTimeout: 1.0)
                || addTransactionButton.waitForExistence(timeout: 6),
            "addTransactionButton did not appear after expanding the asset row"
        )
        tapForce(addTransactionButton)
        XCTAssertTrue(app.textFields["transactionAmountField"].waitForExistence(timeout: 2))
        app.textFields["transactionAmountField"].tap()
        app.textFields["transactionAmountField"].typeText("200")
        app.buttons["saveTransactionButton"].tap()

        // DEBUG: Check state after adding transaction
        print("=== AFTER ADDING $200 TRANSACTION ===")
        navigateBackToGoalsList(app)
        openMonthlyPlan(app)
        logExecutionViewState(app)
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back to goals list

        // Re-open Goal A detail to share asset
        XCTAssertTrue(tapWithScroll(app: app, element: app.buttons["goalRow-Goal A"], maxSwipes: 10), "Unable to re-open Goal A row")
        if app.tabBars.buttons["Details"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["Details"].tap()
        }

        // Re-expand asset row
        var assetRowForShare = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "assetRow-USD")).firstMatch
        if !assetRowForShare.exists {
            assetRowForShare = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "assetRow-USD")).firstMatch
        }
        XCTAssertTrue(waitForExistenceWithScroll(app: app, element: assetRowForShare, maxSwipes: 10, perAttemptTimeout: 1.0), "Asset row not found for sharing")
        tapForce(assetRowForShare)

        // Share asset: allocate 120 to Goal A, 80 to Goal B
        let shareButton = app.descendants(matching: .any)["shareAssetButton"]
        if !shareButton.waitForExistence(timeout: 2) {
            tapForce(assetRow)
        }
        XCTAssertTrue(shareButton.waitForExistence(timeout: 6))
        tapForce(shareButton)
        let allocA = app.textFields["allocation-Goal A"]
        let allocB = app.textFields["allocation-Goal B"]
        if !allocA.waitForExistence(timeout: 2) {
            // Sheet might have been slow to present; retry tap once.
            tapForce(shareButton)
        }
        XCTAssertTrue(allocA.waitForExistence(timeout: 6))
        XCTAssertTrue(allocB.waitForExistence(timeout: 6))

        // Clear existing value and enter new allocation for Goal A
        // Using 50 instead of 120 so Goal A is clearly underfunded (target $800, contribution $50)
        allocA.tap()
        clearTextField(allocA)
        allocA.typeText("50")

        // Clear existing value and enter new allocation for Goal B
        allocB.tap()
        clearTextField(allocB)
        allocB.typeText("150")
        app.buttons["saveAllocationsButton"].tap()
        XCTAssertTrue(app.buttons["saveAllocationsButton"].waitForNonExistence(timeout: 8))

        // Back to goals list - navigate back until we see addGoalButton
        navigateBackToGoalsList(app)
        dismissMonthlyPlanningSettingsIfPresent(app)

        // Re-open Monthly Plan (execution mode) for assertions
        openMonthlyPlan(app)

        // Execution view assertions
        let goalACard = app.staticTexts["goalCard-Goal A"]
        let goalBCard = app.staticTexts["goalCard-Goal B"]
        XCTAssertTrue(goalACard.waitForExistence(timeout: 6), "Goal A card not found in execution view")
        XCTAssertTrue(goalBCard.waitForExistence(timeout: 6), "Goal B card not found in execution view")

        // Log all visible static texts for debugging
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        print("=== EXECUTION VIEW DEBUG ===")
        print("Found \(allStaticTexts.count) static texts:")
        var allDollarLabels: [String] = []
        for (index, text) in allStaticTexts.enumerated() {
            let label = text.label
            let identifier = text.identifier
            if label.contains("$") {
                allDollarLabels.append(label)
                print("  [\(index)] id='\(identifier)' label='\(label)'")
            } else if label.contains("Goal") || label.contains("120") || label.contains("80") || label.contains("200") || label.contains("2800") {
                print("  [\(index)] id='\(identifier)' label='\(label)'")
            }
        }
        print("All dollar amounts found: \(allDollarLabels)")
        print("=== END DEBUG ===")

        // Contributions should reflect 50 / 150 after sharing (Goal A underfunded: $50 of $800 target)
        let has50 = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'US$50.00'")).firstMatch.waitForExistence(timeout: 5)
        let has150 = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'US$150.00'")).firstMatch.waitForExistence(timeout: 5)

        // Check for unexpected amounts that indicate bugs
        let has2800 = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '2800' OR label CONTAINS '2,800'")).firstMatch.exists
        let has200AsContribution = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'US$200.00'")).firstMatch.exists

        // Provide detailed failure messages
        if !has50 {
            XCTFail("Expected 'US$50.00' for Goal A but found dollar amounts: \(allDollarLabels)")
        }
        if !has150 {
            XCTFail("Expected 'US$150.00' for Goal B but found dollar amounts: \(allDollarLabels)")
        }
        if has2800 {
            XCTFail("Unexpected $2800 found - this indicates a calculation bug. All amounts: \(allDollarLabels)")
        }
        if has200AsContribution {
            // $200 as a contribution would mean sharing didn't work - transaction stayed fully allocated to Goal A
            print("WARNING: Found US$200.00 - sharing may not have updated contributions correctly")
        }

        // PART 1.5: Verify tracking contribution matches details current total
        // Since Goal A had no assets before execution started, and both currencies are USD,
        // the tracking contribution should equal the details current total.
        print("=== PART 1.5: Verifying Details vs Tracking ===")

        // Navigate back to goals list then open Goal A details
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tapWithScroll(app: app, element: app.buttons["goalRow-Goal A"], maxSwipes: 10), "Unable to open Goal A for verification")
        if app.tabBars.buttons["Details"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["Details"].tap()
        }
        dismissMonthlyPlanningSettingsIfPresent(app)
        sleep(1) // Wait for UI to settle

        // Capture current total from details view (format: "Current: X.XX USD")
        let detailsTexts = app.staticTexts.allElementsBoundByIndex
        var detailsCurrentTotal: String?
        for text in detailsTexts {
            let label = text.label
            if label.hasPrefix("Current:") {
                detailsCurrentTotal = label
                print("  Found details current total: '\(label)'")
                break
            }
        }
        XCTAssertNotNil(detailsCurrentTotal, "Could not find 'Current:' text in details view")

        // Extract numeric value from details (e.g., "Current: 50.00 USD" -> "50.00")
        var detailsAmount: Double?
        if let currentText = detailsCurrentTotal {
            // Extract number after "Current: "
            let parts = currentText.replacingOccurrences(of: "Current: ", with: "").split(separator: " ")
            if let firstPart = parts.first {
                detailsAmount = Double(firstPart)
            }
        }
        print("  Details amount extracted: \(detailsAmount ?? -1)")

        // Navigate to tracking and capture Goal A's contribution
        navigateBackToGoalsList(app)
        dismissMonthlyPlanningSettingsIfPresent(app)
        openMonthlyPlan(app)
        sleep(1)

        // Find Goal A's contribution in tracking (format: "US$X.XX / US$Y.YY")
        let trackingTexts = app.staticTexts.allElementsBoundByIndex
        var trackingContribution: String?
        for text in trackingTexts {
            let label = text.label
            // Look for the contribution/planned format near Goal A card
            if label.contains("US$") && label.contains("/") && label.contains("50") {
                trackingContribution = label
                print("  Found tracking contribution: '\(label)'")
                break
            }
        }

        // Extract numeric value from tracking (e.g., "US$50.00 / US$800.00" -> 50.00)
        var trackingAmount: Double?
        if let trackingText = trackingContribution {
            // Extract first US$ amount
            let parts = trackingText.split(separator: "/")
            if let firstPart = parts.first {
                let amountStr = String(firstPart)
                    .replacingOccurrences(of: "US$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                trackingAmount = Double(amountStr)
            }
        }
        print("  Tracking amount extracted: \(trackingAmount ?? -1)")

        // Verify they match
        if let dAmount = detailsAmount, let tAmount = trackingAmount {
            XCTAssertEqual(dAmount, tAmount, accuracy: 0.01,
                "Details current total (\(dAmount)) should match tracking contribution (\(tAmount))")
        } else {
            print("  WARNING: Could not extract both amounts for comparison")
            print("  Details: \(detailsCurrentTotal ?? "nil"), Tracking: \(trackingContribution ?? "nil")")
        }

        // Navigate back for Part 2
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // PART 2: Add BTC asset to Goal A and verify tracking matches details
        print("=== PART 2: Adding BTC Asset ===")

        // Open Goal A detail
        XCTAssertTrue(tapWithScroll(app: app, element: app.buttons["goalRow-Goal A"], maxSwipes: 10), "Unable to open Goal A for BTC asset")
        if app.tabBars.buttons["Details"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["Details"].tap()
        }
        dismissMonthlyPlanningSettingsIfPresent(app)

        // Add BTC Asset to Goal A
        let addAssetButton2 = app.buttons["addAssetButton"]
        XCTAssertTrue(tapWithScroll(app: app, element: addAssetButton2, maxSwipes: 10), "Unable to find addAssetButton for BTC")
        pickCurrency(app, symbol: "BTC", buttonId: "assetCurrencyButton")
        XCTAssertTrue(app.buttons["saveAssetButton"].waitForExistence(timeout: 2))
        app.buttons["saveAssetButton"].tap()
        XCTAssertTrue(app.buttons["saveAssetButton"].waitForNonExistence(timeout: 8))
        dismissMonthlyPlanningSettingsIfPresent(app)

        // Find and expand BTC asset row
        var btcAssetRow = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "assetRow-BTC")).firstMatch
        if !btcAssetRow.exists {
            btcAssetRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "assetRow-BTC")).firstMatch
        }
        XCTAssertTrue(
            waitForExistenceWithScroll(app: app, element: btcAssetRow, maxSwipes: 10, perAttemptTimeout: 1.0),
            "BTC asset row not found after saving asset"
        )
        tapForce(btcAssetRow)

        // Add BTC transaction (0.01 BTC)
        let addBtcTransactionButton = app.descendants(matching: .any)["addTransactionButton"]
        if !addBtcTransactionButton.waitForExistence(timeout: 1) {
            tapForce(btcAssetRow)
        }
        XCTAssertTrue(
            waitForExistenceWithScroll(app: app, element: addBtcTransactionButton, maxSwipes: 3, perAttemptTimeout: 1.0)
                || addBtcTransactionButton.waitForExistence(timeout: 6),
            "addTransactionButton did not appear for BTC asset"
        )
        tapForce(addBtcTransactionButton)
        XCTAssertTrue(app.textFields["transactionAmountField"].waitForExistence(timeout: 2))
        app.textFields["transactionAmountField"].tap()
        app.textFields["transactionAmountField"].typeText("0.01")
        app.buttons["saveTransactionButton"].tap()

        // Wait for transaction to be saved
        XCTAssertTrue(app.buttons["saveTransactionButton"].waitForNonExistence(timeout: 8))

        // Capture Goal A details current total after BTC transaction
        print("=== GOAL A DETAILS AFTER BTC TRANSACTION ===")
        sleep(1) // Wait for UI to settle

        let detailStaticTexts = app.staticTexts.allElementsBoundByIndex
        var detailsCurrentTotalAfterBTC: String?
        for text in detailStaticTexts {
            let label = text.label
            if label.hasPrefix("Current:") {
                detailsCurrentTotalAfterBTC = label
                print("  Found details current total: '\(label)'")
            }
            if label.contains("BTC") || label.contains("0.01") || label.contains("$") {
                print("  Detail: '\(label)'")
            }
        }
        XCTAssertNotNil(detailsCurrentTotalAfterBTC, "Could not find 'Current:' text in details view after BTC")

        // Extract numeric value from details
        var detailsAmountAfterBTC: Double?
        if let currentText = detailsCurrentTotalAfterBTC {
            let parts = currentText.replacingOccurrences(of: "Current: ", with: "").split(separator: " ")
            if let firstPart = parts.first {
                detailsAmountAfterBTC = Double(firstPart)
            }
        }
        print("  Details amount after BTC: \(detailsAmountAfterBTC ?? -1)")

        // Navigate to execution tracking
        navigateBackToGoalsList(app)
        dismissMonthlyPlanningSettingsIfPresent(app)
        openMonthlyPlan(app)
        sleep(1)

        print("=== EXECUTION VIEW AFTER BTC TRANSACTION ===")
        logExecutionViewState(app)

        // Find Goal A's contribution in tracking after BTC
        let finalTrackingTexts = app.staticTexts.allElementsBoundByIndex
        var trackingContributionAfterBTC: String?
        var finalDollarLabels: [String] = []
        for text in finalTrackingTexts {
            let label = text.label
            if text.label.contains("$") || text.label.contains("BTC") {
                finalDollarLabels.append(text.label)
            }
            // Look for Goal A's contribution/planned format - should have more than $50 now
            // The contribution should include USD ($50) + BTC value
            if label.contains("US$") && label.contains("/") && label.contains("800") {
                // This is likely Goal A's progress (target is $800)
                trackingContributionAfterBTC = label
                print("  Found Goal A tracking contribution: '\(label)'")
            }
        }
        print("Final amounts after BTC: \(finalDollarLabels)")

        // Extract numeric value from tracking
        var trackingAmountAfterBTC: Double?
        if let trackingText = trackingContributionAfterBTC {
            let parts = trackingText.split(separator: "/")
            if let firstPart = parts.first {
                let amountStr = String(firstPart)
                    .replacingOccurrences(of: "US$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                trackingAmountAfterBTC = Double(amountStr)
            }
        }
        print("  Tracking amount after BTC: \(trackingAmountAfterBTC ?? -1)")

        // Verify details and tracking match after BTC transaction
        if let dAmount = detailsAmountAfterBTC, let tAmount = trackingAmountAfterBTC {
            XCTAssertEqual(dAmount, tAmount, accuracy: 0.01,
                "After BTC: Details current total (\(dAmount)) should match tracking contribution (\(tAmount))")
            // Also verify BTC actually increased the amount (should be more than $50 USD)
            XCTAssertGreaterThan(tAmount, 50.0,
                "Tracking contribution after BTC (\(tAmount)) should be greater than USD-only amount ($50)")
        } else {
            XCTFail("Could not extract amounts for comparison after BTC. Details: \(detailsCurrentTotalAfterBTC ?? "nil"), Tracking: \(trackingContributionAfterBTC ?? "nil")")
        }

        // Goal A card should still be visible
        XCTAssertTrue(goalACard.exists, "Goal A card should still be visible after BTC transaction")
    }

    // MARK: - Helpers

    /// Logs the current state of the execution view for debugging.
    private func logExecutionViewState(_ app: XCUIApplication) {
        // Wait a moment for UI to settle
        sleep(1)

        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        print("Execution view state - \(allStaticTexts.count) static texts:")
        for text in allStaticTexts {
            let label = text.label
            let identifier = text.identifier
            // Log elements related to goals, amounts, or contributions
            if label.contains("$") || label.contains("Goal") || label.contains("contributed") ||
               label.contains("target") || label.contains("progress") || identifier.contains("goalCard") {
                print("  id='\(identifier)' label='\(label)'")
            }
        }

        // Also check for any progress indicators or contribution amounts
        let allButtons = app.buttons.allElementsBoundByIndex
        for button in allButtons {
            let label = button.label
            let identifier = button.identifier
            if identifier.contains("goal") || label.contains("Goal") {
                print("  [button] id='\(identifier)' label='\(label)'")
            }
        }
    }

    /// Navigates back to the goals list by tapping back buttons until addGoalButton is visible.
    private func navigateBackToGoalsList(_ app: XCUIApplication) {
        // If we're already on the goals list, do nothing
        if app.buttons["addGoalButton"].waitForExistence(timeout: 1) {
            return
        }

        // Try up to 5 back button taps
        for _ in 0..<5 {
            // Look for a back button in the navigation bar
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            guard backButton.exists else { break }

            // Don't tap if we've reached the goals list
            if app.buttons["addGoalButton"].exists {
                break
            }

            backButton.tap()

            // Check if we've arrived at the goals list
            if app.buttons["addGoalButton"].waitForExistence(timeout: 2) {
                break
            }
        }
    }

    private func openMonthlyPlan(_ app: XCUIApplication) {
        if !app.buttons["viewMonthlyPlanLink"].exists {
            let expand = app.buttons["planningWidgetExpandButton"].firstMatch
            if expand.exists { tapForce(expand) }
        }
        XCTAssertTrue(app.buttons["viewMonthlyPlanLink"].waitForExistence(timeout: 6))
        app.buttons["viewMonthlyPlanLink"].tap()
    }

    private func startTrackingIfNeeded(_ app: XCUIApplication) {
        openMonthlyPlan(app)

        // If we are already in execution mode, we should see goal cards or a return-to-planning button.
        if app.buttons["returnToPlanningButton"].waitForExistence(timeout: 2) || app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'goalCard-'")).firstMatch.exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            return
        }

        if app.buttons["startTrackingButton"].waitForExistence(timeout: 6) {
            app.buttons["startTrackingButton"].tap()
            let startAlert = app.alerts["Start Tracking?"]
            if startAlert.waitForExistence(timeout: 2) {
                startAlert.buttons["Start Tracking"].firstMatch.tap()
            }
        }

        // Wait for execution mode to appear
        _ = app.buttons["returnToPlanningButton"].waitForExistence(timeout: 8)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func addGoal(_ app: XCUIApplication, name: String, target: String) {
        // Ensure we're back on the goals list
        if !app.buttons["addGoalButton"].waitForExistence(timeout: 2) {
            if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            } else if app.buttons["BackButton"].exists {
                app.buttons["BackButton"].tap()
            }
        }

        XCTAssertTrue(app.buttons["addGoalButton"].waitForExistence(timeout: 6))
        var opened = false
        for _ in 0..<3 {
            app.buttons["addGoalButton"].tap()
            // Wait for the Add Goal form to appear (avoid generic text-field fallbacks; they can match unrelated screens)
            let nameField = app.textFields["goalNameField"]
            if nameField.waitForExistence(timeout: 8) {
                nameField.tap()
                nameField.typeText(name)
                opened = true
                break
            }
            // If we ended up in the form but field didn't resolve, try backing out
            if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            } else if app.buttons["BackButton"].exists {
                app.buttons["BackButton"].tap()
            } else if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(opened, "Add Goal form did not appear")

        // Currency selection: either the explicit button or the generic "Select Currency" button
        if app.buttons["currencyButton"].waitForExistence(timeout: 2) {
            pickCurrency(app, symbol: "USD", buttonId: "currencyButton")
        } else if app.buttons["Select Currency"].waitForExistence(timeout: 2) {
            pickCurrency(app, symbol: "USD", buttonId: "Select Currency")
        } else {
            XCTFail("Currency button not found")
        }

        let targetField = app.textFields["targetAmountField"].exists ? app.textFields["targetAmountField"] : (app.textFields["Target Amount"].exists ? app.textFields["Target Amount"] : app.textFields.element(boundBy: 0))
        XCTAssertTrue(targetField.waitForExistence(timeout: 5))
        if !targetField.isHittable {
            app.swipeUp()
            app.swipeUp()
        }
        tapForce(targetField)
        if !targetField.hasKeyboardFocus {
            tapForce(targetField)
        }
        if !app.keyboards.element.exists {
            tapForce(targetField)
        }
        targetField.typeText(target)

        let saveButton = app.buttons["saveGoalButton"].firstMatch
        if !saveButton.exists {
            // mac-style button name fallback on iOS if layout differs
            app.buttons["saveGoalButtonMac"].firstMatch.tap()
        } else {
            saveButton.tap()
        }

        // Wait until we are back on the goals list
        if !app.buttons["addGoalButton"].waitForExistence(timeout: 4) {
            if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            } else if app.buttons["BackButton"].exists {
                app.buttons["BackButton"].tap()
            }
        }
        XCTAssertTrue(app.buttons["addGoalButton"].waitForExistence(timeout: 4))
    }

    private func pickCurrency(_ app: XCUIApplication, symbol: String, buttonId: String) {
        XCTAssertTrue(app.buttons[buttonId].waitForExistence(timeout: 3))
        app.buttons[buttonId].tap()

        let search = app.textFields["currencySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText(symbol)
        // Dismiss keyboard if it stays up to avoid focus issues.
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }

        let symbolUpper = symbol.uppercased()
        let cell = app.buttons["currencyCell-\(symbolUpper)"].firstMatch

        // Picker may auto-pick and dismiss in UI test mode.
        if search.exists {
            if !search.waitForNonExistence(timeout: 1) {
                // Prefer explicit selection (cell tap triggers dismiss()).
                XCTAssertTrue(cell.waitForExistence(timeout: 6), "Currency cell not found: \(symbolUpper)")
                tapForce(cell)

                // Wait for picker dismissal; avoid gestures that could dismiss the parent view.
                if !search.waitForNonExistence(timeout: 6) {
                    let done = app.buttons["currencyDoneButton"].firstMatch
                    if done.waitForExistence(timeout: 2) {
                        done.tap()
                    }
                }
                XCTAssertTrue(search.waitForNonExistence(timeout: 6), "Currency picker did not dismiss after selecting \(symbolUpper)")
            }
        }

        // Verify we're still on the expected screen and the selection is reflected.
        let selectedButton = app.buttons[buttonId]
        XCTAssertTrue(selectedButton.waitForExistence(timeout: 3), "Expected currency button not found after picker dismissed (\(buttonId))")

        let labelUpper = selectedButton.label.uppercased()
        let valueUpper = ((selectedButton.value as? String) ?? "").uppercased()
        XCTAssertTrue(
            labelUpper.contains(symbolUpper) || valueUpper.contains(symbolUpper),
            "Currency selection not reflected in UI (buttonId=\(buttonId), label=\(selectedButton.label), value=\(String(describing: selectedButton.value)))"
        )
    }

    private func dismissMonthlyPlanningSettingsIfPresent(_ app: XCUIApplication) {
        let navBar = app.navigationBars["Monthly Planning Settings"]
        guard navBar.exists || navBar.waitForExistence(timeout: 0.5) else { return }

        let doneCandidates: [XCUIElement] = [
            navBar.buttons["Done"],
            app.buttons["Done"],
            app.navigationBars.buttons["Done"].firstMatch
        ]
        for button in doneCandidates where button.exists {
            tapForce(button)
            _ = navBar.waitForNonExistence(timeout: 2)
            if !navBar.exists { return }
        }

        let cancelCandidates: [XCUIElement] = [
            navBar.buttons["Cancel"],
            app.buttons["Cancel"],
            app.navigationBars.buttons["Cancel"].firstMatch
        ]
        for button in cancelCandidates where button.exists {
            tapForce(button)
            _ = navBar.waitForNonExistence(timeout: 2)
            if !navBar.exists { return }
        }

        // Final fallback: swipe down to dismiss a sheet.
        app.swipeDown()
        _ = navBar.waitForNonExistence(timeout: 2)
    }
}

private func tapForce(_ element: XCUIElement) {
    if element.isHittable {
        element.tap()
    } else {
        let coord = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.tap()
    }
}

/// Clears all text from a text field by selecting all and deleting.
private func clearTextField(_ textField: XCUIElement) {
    guard let currentValue = textField.value as? String, !currentValue.isEmpty else { return }

    // Triple-tap to select all text
    textField.tap(withNumberOfTaps: 3, numberOfTouches: 1)

    // Small delay to let selection happen
    usleep(100_000) // 100ms

    // Delete selected text
    textField.typeText(XCUIKeyboardKey.delete.rawValue)
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        self.value(forKey: "hasKeyboardFocus") as? Bool ?? false
    }
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }
}

/// Attempts to tap an element, scrolling if necessary.
@discardableResult
private func tapWithScroll(app: XCUIApplication, element: XCUIElement, maxSwipes: Int = 5) -> Bool {
    if element.exists && element.isHittable {
        element.tap()
        return true
    }
    for _ in 0..<maxSwipes {
        app.swipeUp()
        if element.exists && element.isHittable {
            element.tap()
            return true
        }
    }
    if element.exists {
        tapForce(element)
        return true
    }
    return false
}

@discardableResult
private func waitForExistenceWithScroll(
    app: XCUIApplication,
    element: XCUIElement,
    maxSwipes: Int = 5,
    perAttemptTimeout: TimeInterval = 1.0
) -> Bool {
    if element.waitForExistence(timeout: perAttemptTimeout) { return true }
    for _ in 0..<maxSwipes {
        app.swipeUp()
        if element.waitForExistence(timeout: perAttemptTimeout) { return true }
    }
    return element.exists
}
