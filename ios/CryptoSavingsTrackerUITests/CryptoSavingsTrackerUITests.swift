//
//  CryptoSavingsTrackerUITests.swift
//  CryptoSavingsTrackerUITests
//
//  Created by user on 25/07/2025.
//

import XCTest

final class CryptoSavingsTrackerUITests: XCTestCase {

    var app: XCUIApplication!
    private let baseLaunchArguments = [
        "UITEST_RESET_DATA",
        "UITEST_UI_FLOW",
        "UITEST_START_ON_GOALS",
        "-ApplePersistenceIgnoreState",
        "YES"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
#if os(iOS)
        // UI launch configurations share simulator orientation across suites.
        XCUIDevice.shared.orientation = .portrait
#endif
        launchApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Tests
    
    @MainActor
    func testAppLaunch() throws {
        // Verify the main UI elements are present
        let goalsNavExists = app.navigationBars["Goals"].exists || app.navigationBars["Crypto Goals"].exists
        XCTAssertTrue(goalsNavExists)
        XCTAssertTrue(addGoalButton().waitForExistence(timeout: 5))
    }
    
    @MainActor
    func testEmptyStateDisplay() throws {
        // On first launch, should show empty list
        let goalsList = app.collectionViews.firstMatch
        
        // Wait for the list to appear
        XCTAssertTrue(goalsList.waitForExistence(timeout: 5))
        
        // Should have no goal cells initially
        let goalCells = app.cells.containing(.staticText, identifier: "days").count
        XCTAssertEqual(goalCells, 0)
    }
    
    // MARK: - Goal Creation Flow Tests

    @MainActor
    func testDashboardEmptyStateCanOpenGoalForm() throws {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 5))
        dashboardTab.tap()

        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))

        let createGoalButton = app.buttons["Create Goal"]
        XCTAssertTrue(createGoalButton.waitForExistence(timeout: 5))
        createGoalButton.tap()

        XCTAssertTrue(
            app.navigationBars["New Goal"].waitForExistence(timeout: 5)
                || app.navigationBars["Add Goal"].waitForExistence(timeout: 5),
            "Dashboard navigation should open the goal form"
        )
    }
    
    @MainActor
    func testCreateNewGoal() throws {
        openAddGoalForm()
        
        // Fill in the form
        let nameField = app.textFields["goalNameField"].exists ? app.textFields["goalNameField"] : app.textFields["Goal Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Bitcoin Savings")
        
        setGoalCurrency("USD")

        let amountField = app.textFields["targetAmountField"].exists ? app.textFields["targetAmountField"] : app.textFields["Target Amount"]
        XCTAssertTrue(amountField.exists)
        amountField.tap()
        amountField.typeText("10000")
        
        // The form already supplies a future default deadline. Opening the
        // compact picker without selecting a value only obscures the bottom
        // action bar and does not exercise a deadline change.
        
        // Save the goal
        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        
        // Wait for form to dismiss and navigation to complete
        sleep(2)

        // After saving, we might end up on:
        // 1. Goals list (nav title "Goals" or "Crypto Goals")
        // 2. Goal detail view (nav title is goal name "Bitcoin Savings")
        // 3. Still on the form if save failed (nav title "New Goal")

        let goalsNav = app.navigationBars["Goals"]
        let cryptoGoalsNav = app.navigationBars["Crypto Goals"]
        let goalDetailNav = app.navigationBars["Bitcoin Savings"]
        let newGoalNav = app.navigationBars["New Goal"]

        // Check for expected navigation states
        _ = goalsNav.waitForExistence(timeout: 3) ||
            cryptoGoalsNav.waitForExistence(timeout: 3) ||
            goalDetailNav.waitForExistence(timeout: 3)

        // If still on the form, the save might have failed - try again
        if newGoalNav.exists {
            let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save"]
            if saveButton.exists && saveButton.isEnabled {
                saveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(2)
            }
        }

        // Re-check navigation after potential retry
        let navExists = goalsNav.waitForExistence(timeout: 5) ||
                        cryptoGoalsNav.waitForExistence(timeout: 5) ||
                        goalDetailNav.waitForExistence(timeout: 5)
        XCTAssertTrue(navExists, "Expected to return to goals list or goal detail after saving")

        // If we're on goal detail, go back to list
        if goalDetailNav.exists {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists {
                backButton.tap()
                _ = goalsNav.waitForExistence(timeout: 3) || cryptoGoalsNav.waitForExistence(timeout: 3)
            }
        }

        // Verify the goal appears in the list
        let goalCell = app.cells.containing(.staticText, identifier: "Bitcoin Savings").firstMatch
        if !goalCell.waitForExistence(timeout: 3) {
            // Try finding by text content
            let goalText = app.staticTexts["Bitcoin Savings"]
            XCTAssertTrue(goalText.waitForExistence(timeout: 5), "Goal 'Bitcoin Savings' should appear in the list")
        }
    }

    @MainActor
    func testPublicGoalCurrencyPickerSelectsCatalogCell() throws {
        relaunch(extraArguments: ["UITEST_SEED_PUBLIC_CURRENCY_CATALOG"])
        openAddGoalForm()

        let currencyButton = app.buttons["currencyButton"]
        XCTAssertTrue(currencyButton.waitForExistence(timeout: 3))
        currencyButton.tap()

        let searchField = app.textFields["currencySearchField"]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 3),
            "The public currency picker must be presented"
        )

        let euroCell = app.buttons["currencyCell-EUR"].firstMatch
        XCTAssertTrue(
            euroCell.waitForExistence(timeout: 3),
            "The deterministic public catalog must expose a real EUR currencyCell"
        )
        XCTAssertTrue(euroCell.isHittable, "The public EUR currencyCell must be directly selectable")
        euroCell.tap()

        XCTAssertTrue(
            searchField.waitForNonExistence(timeout: 3),
            "Selecting the public EUR cell must dismiss the picker"
        )
        XCTAssertEqual(
            currencyButton.value as? String,
            "EUR",
            "The goal form must receive the value selected through the public picker"
        )
    }

    @MainActor
    func testLocalizedGoalAmountCanBeSaved() throws {
        relaunch(extraArguments: [
            "-AppleLanguages",
            "(de)",
            "-AppleLocale",
            "de_DE"
        ])
        openGoalsTab()
        openAddGoalForm()

        let nameField = app.textFields["goalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Localized Goal")
        setGoalCurrency("EUR")

        let amountField = app.textFields["targetAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("1,50")

        let saveButton = app.buttons["saveGoalButton"].exists
            ? app.buttons["saveGoalButton"]
            : app.buttons["Save Goal"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        XCTAssertTrue(
            app.buttons["goalRow-Localized Goal"].waitForExistence(timeout: 8),
            "A comma-decimal amount should save as a localized value"
        )
    }

    @MainActor
    func testArchivedGoalCanBeRestoredFromGoalsList() throws {
        relaunch(extraArguments: ["UITEST_SEED_GOALS"])
        openGoalsTab()

        let goalRow = app.buttons["goalRow-UI Goal Seed"]
        XCTAssertTrue(goalRow.waitForExistence(timeout: 8))
        goalRow.swipeLeft()

        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        editButton.tap()

        let archiveButton = app.buttons["Archive this goal"]
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 5))
        archiveButton.tap()

        let archiveConfirmation = app.buttons["Archive"]
        XCTAssertTrue(archiveConfirmation.waitForExistence(timeout: 3))
        archiveConfirmation.tap()

        let archivedRow = app.otherElements["archivedGoalRow-UI Goal Seed"]
        XCTAssertTrue(
            archivedRow.waitForExistence(timeout: 8),
            "Archived goals should remain reachable from the Goals list"
        )

        let restoreButton = app.buttons["restoreGoalButton-UI Goal Seed"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 3))
        restoreButton.tap()

        XCTAssertTrue(
            app.buttons["goalRow-UI Goal Seed"].waitForExistence(timeout: 8),
            "Restoring should return the goal to the active list"
        )
        XCTAssertFalse(archivedRow.exists)
    }

    @MainActor
    func testArchiveFailureStaysInEditorAndRetrySucceeds() throws {
        relaunch(extraArguments: [
            "UITEST_SEED_GOALS",
            "UITEST_SIMULATE_GOAL_ARCHIVE_FAILURE"
        ])
        openGoalsTab()

        let goalRow = app.buttons["goalRow-UI Goal Seed"]
        XCTAssertTrue(goalRow.waitForExistence(timeout: 8))
        goalRow.swipeLeft()

        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        editButton.tap()

        let archiveButton = app.buttons["Archive this goal"]
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 5))
        archiveButton.tap()

        let archiveConfirmation = app.buttons["Archive"]
        XCTAssertTrue(archiveConfirmation.waitForExistence(timeout: 3))
        archiveConfirmation.tap()

        let archiveError = app.alerts["Unable to Archive Goal"]
        XCTAssertTrue(archiveError.waitForExistence(timeout: 5))
        XCTAssertTrue(
            archiveError.staticTexts["Unable to archive this goal right now. Please try again."].exists
        )
        XCTAssertTrue(app.navigationBars["Edit Goal"].exists)

        let retryButton = archiveError.buttons["Retry Archive"]
        XCTAssertTrue(retryButton.exists)
        retryButton.tap()

        XCTAssertTrue(
            app.otherElements["archivedGoalRow-UI Goal Seed"].waitForExistence(timeout: 8),
            "A successful retry should dismiss the editor and expose the archived goal"
        )
        XCTAssertFalse(archiveError.exists)
    }
    
    @MainActor
    func testGoalFormValidation() throws {
        openAddGoalForm()
        
        // Try to save without filling required fields
        let primarySaveButton = app.buttons["saveGoalButton"]
        let fallbackSaveGoalButton = app.buttons["Save Goal"]
        let fallbackSaveButton = app.buttons["Save"]
        let saveButton: XCUIElement
        if primarySaveButton.waitForExistence(timeout: 3) {
            saveButton = primarySaveButton
        } else if fallbackSaveGoalButton.waitForExistence(timeout: 2) {
            saveButton = fallbackSaveGoalButton
        } else {
            XCTAssertTrue(fallbackSaveButton.waitForExistence(timeout: 2), "A save action should be visible on the goal form")
            saveButton = fallbackSaveButton
        }

        saveButton.tap()

        // Should stay on the form (validation failed)
        XCTAssertTrue(app.navigationBars["New Goal"].exists || app.navigationBars["Add Goal"].exists)
        XCTAssertTrue(
            primarySaveButton.exists || fallbackSaveGoalButton.exists || fallbackSaveButton.exists,
            "Primary save CTA should remain visible after validation failure"
        )
        XCTAssertTrue(
            app.staticTexts["Review this goal"].waitForExistence(timeout: 2) ||
            app.staticTexts["Goal name is required"].waitForExistence(timeout: 2),
            "Validation summary or first validation reason should appear after attempting to save an invalid goal"
        )
        
        // Cancel and return
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        } else {
            // Try swipe down to dismiss on iOS
            app.swipeDown()
        }
    }

    @MainActor
    func testAddGoalInvalidSaveFocusesFirstInvalidField() throws {
        openAddGoalForm()

        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save Goal"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        let focusedField = app.otherElements["goalFormFocusedField"]
        XCTAssertTrue(focusedField.waitForExistence(timeout: 2), "Focused field hook should be available after validation failure")
        XCTAssertEqual(focusedField.label, "name", "First invalid field should receive focus after invalid submit")
        XCTAssertTrue(
            app.staticTexts["Review this goal"].waitForExistence(timeout: 2) ||
            app.staticTexts["Goal name is required"].waitForExistence(timeout: 2),
            "Validation feedback should be visible after invalid submit"
        )
    }

    @MainActor
    func testGoalFormPersistenceFailureRetryFlow() throws {
        relaunch(extraArguments: ["UITEST_SIMULATE_GOAL_SAVE_FAILURE"])
        openAddGoalForm()

        let nameField = app.textFields["goalNameField"].exists ? app.textFields["goalNameField"] : app.textFields["Goal Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Retry Goal")

        setGoalCurrency("USD")

        let amountField = app.textFields["targetAmountField"].exists ? app.textFields["targetAmountField"] : app.textFields["Target Amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("2500")

        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save Goal"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        let saveErrorText = app.staticTexts["Unable to save this goal right now. Please try again."]
        XCTAssertTrue(saveErrorText.waitForExistence(timeout: 5), "Save failure should surface a blocking error")
        let retryButton = app.buttons["goalFormRetryButton"].exists ? app.buttons["goalFormRetryButton"] : app.buttons["Retry"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 3), "Retry CTA should be visible after save failure")

        retryButton.tap()

        let navExists = app.navigationBars["Goals"].waitForExistence(timeout: 5) ||
            app.navigationBars["Crypto Goals"].waitForExistence(timeout: 5) ||
            app.navigationBars["Retry Goal"].waitForExistence(timeout: 5)
        XCTAssertTrue(navExists, "Retry should eventually complete the save flow")
        XCTAssertFalse(saveErrorText.exists, "Save error should disappear after a successful retry")
    }

    @MainActor
    func testAddGoalDirtyDismissConfirmationFlow() throws {
        openAddGoalForm()

        let nameField = app.textFields["goalNameField"].exists ? app.textFields["goalNameField"] : app.textFields["Goal Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Dirty Goal")

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        let discardButton = app.buttons["Discard Changes"]
        XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
        discardButton.tap()

        XCTAssertTrue(
            app.navigationBars["Goals"].waitForExistence(timeout: 5) ||
            app.navigationBars["Crypto Goals"].waitForExistence(timeout: 5)
        )
    }
    
    // MARK: - Goal Detail Flow Tests
    
    @MainActor
    func testGoalDetailNavigation() throws {
        // First create a goal for testing
        createTestGoal(name: "Test Goal", amount: "1000", currency: "USD")
        
        // Tap on the goal to open detail view
        let goalCell = app.cells.containing(.staticText, identifier: "Test Goal").firstMatch
        XCTAssertTrue(goalCell.waitForExistence(timeout: 5))
        goalCell.tap()
        
        // Should navigate to goal detail view
        XCTAssertTrue(app.navigationBars.containing(.staticText, identifier: "Test Goal").firstMatch.waitForExistence(timeout: 3) ||
                     app.staticTexts["Test Goal"].waitForExistence(timeout: 3))
        
        // Should show goal information
        let targetLabel = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Target'")
        ).firstMatch
        XCTAssertTrue(targetLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(targetLabel.label.contains("USD"))
        
        // Should have Add Asset button
        XCTAssertTrue(app.buttons["addAssetButton"].waitForExistence(timeout: 3) || app.buttons["Add Asset"].waitForExistence(timeout: 3))
    }
    
    @MainActor
    func testAddAssetToGoal() throws {
        // Create a goal and navigate to detail
        createTestGoal(name: "Asset Goal", amount: "5000", currency: "USD")
        
        let goalCell = app.cells.containing(.staticText, identifier: "Asset Goal").firstMatch
        goalCell.tap()
        
        // Tap Add Asset
        let addAssetButton = app.buttons["addAssetButton"].exists ? app.buttons["addAssetButton"] : app.buttons["Add Asset"]
        XCTAssertTrue(addAssetButton.waitForExistence(timeout: 5))
        addAssetButton.tap()
        
        // Should show add asset form
        XCTAssertTrue(app.navigationBars["New Asset"].waitForExistence(timeout: 3) || app.navigationBars["Add Asset"].waitForExistence(timeout: 3))
        
        // Fill in asset details
        setAssetCurrency("BTC")
        
        // Save asset
        let saveButton = app.buttons["saveAssetButton"].exists ? app.buttons["saveAssetButton"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        }
        
        // Should return to goal detail and show the asset
        XCTAssertTrue(app.staticTexts["BTC"].waitForExistence(timeout: 5))
    }
    
    @MainActor
    func testAddTransactionToAsset() throws {
        // Create goal, add asset, then add transaction
        createTestGoal(name: "Transaction Goal", amount: "2000", currency: "USD")
        
        let goalCell = app.cells.containing(.staticText, identifier: "Transaction Goal").firstMatch
        goalCell.tap()
        
        // Add asset first
        addTestAsset(currency: "ETH")

        // Expand the asset row to reveal actions
        expandAssetRow(for: "ETH")
        
        // Tap Add Transaction button for the asset
        let addTransactionButton = app.buttons["addTransactionButton"].exists ? app.buttons["addTransactionButton"] : app.buttons["Add Transaction"]
        XCTAssertTrue(addTransactionButton.waitForExistence(timeout: 5))
        addTransactionButton.tap()
        
        // Should show add transaction form
        XCTAssertTrue(app.navigationBars["New Transaction"].waitForExistence(timeout: 3) || app.navigationBars["Add Transaction"].waitForExistence(timeout: 3))
        
        // Fill in transaction amount
        let amountField = app.textFields["transactionAmountField"].exists ? app.textFields["transactionAmountField"] : app.textFields["Amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("1.5")
        
        // Save transaction
        let saveButton = app.buttons["saveTransactionButton"].exists ? app.buttons["saveTransactionButton"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        }
        
        // Should return to goal detail and show updated transaction amount
        let amountText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1.5'")).firstMatch
        XCTAssertTrue(amountText.waitForExistence(timeout: 5))
    }
    
    // MARK: - Goal Management Tests
    
    @MainActor
    func testDeleteGoal() throws {
        // Create a goal to delete
        createTestGoal(name: "Delete Me", amount: "500", currency: "EUR")
        
        // Find the goal cell
        let goalRow = app.buttons["goalRow-Delete Me"]
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        
        // Swipe to delete (iOS standard pattern)
        goalRow.swipeLeft()
        
        // Tap delete button
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 3),
            "Swiping an active goal must expose the Delete action"
        )
        deleteButton.tap()

        // The active row must disappear and the goal must remain recoverable in the archive.
        XCTAssertFalse(goalRow.waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.otherElements["archivedGoalRow-Delete Me"].waitForExistence(timeout: 5),
            "Deleting from the active list should archive the goal"
        )
    }
    
    // MARK: - Progress Display Tests
    
    @MainActor
    func testProgressCalculationDisplay() throws {
        // Create goal with known values
        createTestGoal(name: "Progress Goal", amount: "1000", currency: "USD")
        
        let goalCell = app.cells.containing(.staticText, identifier: "Progress Goal").firstMatch
        goalCell.tap()
        
        // Add asset and transaction for 25% progress
        addTestAsset(currency: "USD")
        addTestTransaction(amount: "250", assetCurrency: "USD")

        let progressSummary = app.descendants(matching: .any)["goalSummaryProgress"]
        XCTAssertTrue(progressSummary.waitForExistence(timeout: 5))
        let progressUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "25%"),
            object: progressSummary
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [progressUpdated], timeout: 10),
            .completed,
            "Expected goal-specific progress to be 25%, got \(progressSummary.label)"
        )
    }
    
    // MARK: - Platform-Specific Tests
    
    @MainActor
    func testPlatformSpecificUI() throws {
        #if os(macOS)
        // Test macOS-specific popover behavior
        openAddGoalForm()
        
        // On macOS, should show as popover
        XCTAssertTrue(app.popovers.count > 0 || app.sheets.count > 0)
        
        #else
        // Test iOS-specific sheet behavior
        openAddGoalForm()
        
        // On iOS, should show as sheet
        XCTAssertTrue(app.sheets.count > 0 || app.navigationBars["New Goal"].exists || app.navigationBars["Add Goal"].exists)
        #endif
    }
    
    // MARK: - Performance Tests
    
    @MainActor
    func testLaunchPerformance() throws {
        // Measure app launch time
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    @MainActor
    func testScrollPerformance() throws {
        // Create multiple goals for scroll testing
        for i in 1...10 {
            createTestGoal(name: "Goal \(i)", amount: "\(i * 100)", currency: "USD")
        }
        
        let goalsList = app.collectionViews.firstMatch
        
        // Measure scroll performance
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            goalsList.swipeUp()
            goalsList.swipeDown()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestGoal(name: String, amount: String, currency: String) {
        openAddGoalForm()
        
        let nameField = app.textFields["goalNameField"].exists ? app.textFields["goalNameField"] : app.textFields["Goal Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText(name)
        }

        setGoalCurrency(currency)
        
        let amountField = app.textFields["targetAmountField"].exists ? app.textFields["targetAmountField"] : app.textFields["Target Amount"]
        if amountField.exists {
            amountField.tap()
            amountField.typeText(amount)
        }
        
        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        }
        
        // Wait for return to main screen
        _ = app.navigationBars["Goals"].waitForExistence(timeout: 5)
    }
    
    private func addTestAsset(currency: String) {
        let addAssetButton = app.buttons["addAssetButton"].exists ? app.buttons["addAssetButton"] : app.buttons["Add Asset"]
        XCTAssertTrue(addAssetButton.waitForExistence(timeout: 5), "Add Asset control is unavailable")
        tapForce(addAssetButton)

        setAssetCurrency(currency)

        let saveButton = app.buttons["saveAssetButton"].exists ? app.buttons["saveAssetButton"] : app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save Asset control is unavailable")
        tapForce(saveButton)
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 8), "Asset form did not dismiss after Save")
    }
    
    private func addTestTransaction(amount: String, assetCurrency: String? = nil) {
        expandAssetRow(for: assetCurrency)

        let addTransactionButton = app.buttons["addTransactionButton"].exists ? app.buttons["addTransactionButton"] : app.buttons["Add Transaction"]
        XCTAssertTrue(addTransactionButton.waitForExistence(timeout: 5), "Add Transaction control is unavailable")
        tapForce(addTransactionButton)

        let amountField = app.textFields["transactionAmountField"].exists ? app.textFields["transactionAmountField"] : app.textFields["Amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5), "Transaction amount field is unavailable")
        guard acquireKeyboardFocus(amountField) else {
            XCTFail("Transaction amount field did not acquire keyboard focus")
            return
        }
        amountField.typeText(amount)

        let saveButton = app.buttons["saveTransactionButton"].exists ? app.buttons["saveTransactionButton"] : app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save Transaction control is unavailable")
        tapForce(saveButton)
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 8), "Transaction form did not dismiss after Save")
    }

    private func expandAssetRow(for currency: String?) {
        let row: XCUIElement
        if let currency {
            row = app.buttons["assetRow-\(currency.uppercased())"]
        } else {
            row = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'assetRow-'")
            ).firstMatch
        }

        if !row.waitForExistence(timeout: 2) {
            for _ in 0..<6 where !row.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Saved asset row is unavailable")
        tapForce(row)
    }

    private func tapForce(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            let coord = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coord.tap()
        }
    }

    private func addGoalButton() -> XCUIElement {
        let candidates = [
            app.buttons["addGoalButton"],
            app.buttons["Create Your First Goal"],
            app.buttons["Plus"],
            app.buttons["+"]
        ]

        for button in candidates where button.exists || button.waitForExistence(timeout: 2) {
            return button
        }

        return app.buttons["addGoalButton"]
    }

    private func openAddGoalForm() {
        let button = addGoalButton()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let newGoalNav = app.navigationBars["New Goal"]
        let addGoalNav = app.navigationBars["Add Goal"]
        XCTAssertTrue(newGoalNav.waitForExistence(timeout: 5) || addGoalNav.waitForExistence(timeout: 5))
    }

    private func openGoalsTab() {
        let goalsTab = app.tabBars.buttons["Goals"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 5))
        goalsTab.tap()
        XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 5))
    }

    private func setGoalCurrency(_ symbol: String) {
        XCTAssertTrue(
            setCurrency(symbol: symbol, overrideId: "goalCurrencyOverrideField", buttonId: "currencyButton"),
            "Unable to choose goal currency \(symbol)"
        )
    }

    private func setAssetCurrency(_ symbol: String) {
        XCTAssertTrue(
            setCurrency(symbol: symbol, overrideId: "assetCurrencyOverrideField", buttonId: "assetCurrencyButton"),
            "Unable to choose asset currency \(symbol)"
        )
    }

    private func setCurrency(symbol: String, overrideId: String, buttonId: String) -> Bool {
        let button = app.buttons[buttonId]
        if button.waitForExistence(timeout: 2) {
            tapForce(button)

            let search = app.textFields["currencySearchField"]
            if search.waitForExistence(timeout: 2) {
                search.tap()
                search.typeText(symbol)
                let cell = app.buttons["currencyCell-\(symbol.uppercased())"].firstMatch
                if cell.waitForExistence(timeout: 3) {
                    tapForce(cell)
                    return true
                }

                // The public picker can legitimately have no rows while its
                // backing catalog is unavailable. Close it and use the
                // UI-test-only field rather than pretending a selection was
                // made.
                let doneButton = app.buttons["currencyDoneButton"]
                if doneButton.waitForExistence(timeout: 2) {
                    tapForce(doneButton)
                } else {
                    let cancelButton = app.buttons["currencyCancelButton"]
                    if cancelButton.waitForExistence(timeout: 2) {
                        tapForce(cancelButton)
                    }
                }
            }
        }

        let overrideField = app.textFields[overrideId]
        guard overrideField.waitForExistence(timeout: 2) else { return false }
        tapForce(overrideField)
        clearTextField(overrideField)
        overrideField.typeText(symbol)
        return true
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

    private func clearTextField(_ element: XCUIElement) {
        guard let currentValue = element.value as? String else { return }
        if currentValue.isEmpty { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        element.typeText(deleteString)
    }

    private func acquireKeyboardFocus(_ element: XCUIElement) -> Bool {
        let hasFocus = NSPredicate(format: "hasKeyboardFocus == true")
        if hasFocus.evaluate(with: element) {
            return true
        }

        for attempt in 0..<3 {
            switch attempt {
            case 0:
                element.tap()
            case 1:
                element.doubleTap()
            default:
                element.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
                ).tap()
            }

            let focused = XCTNSPredicateExpectation(predicate: hasFocus, object: element)
            if XCTWaiter.wait(for: [focused], timeout: 1) == .completed {
                return true
            }
        }
        return false
    }
}
