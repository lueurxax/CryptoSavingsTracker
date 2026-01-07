//
//  CryptoSavingsTrackerUITests.swift
//  CryptoSavingsTrackerUITests
//
//  Created by user on 25/07/2025.
//

import XCTest

final class CryptoSavingsTrackerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        
        // Clear any existing data and enable UI test helpers
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()
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
        
        // Set deadline (assume there's a date picker)
        if app.datePickers.count > 0 {
            let datePicker = app.datePickers.firstMatch
            datePicker.tap()
            // Set a future date (basic interaction)
        }
        
        // Save the goal
        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        } else {
            // Try alternative save button text
            app.buttons["Save"].tap()
        }
        
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
                saveButton.tap()
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
    func testGoalFormValidation() throws {
        openAddGoalForm()
        
        // Try to save without filling required fields
        let saveButton = app.buttons["saveGoalButton"].exists ? app.buttons["saveGoalButton"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
            
            // Should stay on the form (validation failed)
            XCTAssertTrue(app.navigationBars["New Goal"].exists || app.navigationBars["Add Goal"].exists)
        }
        
        // Cancel and return
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        } else {
            // Try swipe down to dismiss on iOS
            app.swipeDown()
        }
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
        let targetLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Target:'")).firstMatch
        XCTAssertTrue(targetLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(targetLabel.label.contains("USD") || app.staticTexts["USD"].exists)
        
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
        let goalCell = app.cells.containing(.staticText, identifier: "Delete Me").firstMatch
        XCTAssertTrue(goalCell.waitForExistence(timeout: 5))
        
        // Swipe to delete (iOS standard pattern)
        goalCell.swipeLeft()
        
        // Tap delete button
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
            
            // Goal should be removed from list
            XCTAssertFalse(app.cells.containing(.staticText, identifier: "Delete Me").firstMatch.waitForExistence(timeout: 2))
        }
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
        
        // Check that progress is displayed
        // Look for percentage display
        let progressText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '%'")).firstMatch
        XCTAssertTrue(progressText.waitForExistence(timeout: 5))
        
        // Should show 25% or similar
        XCTAssertTrue(app.staticTexts["25%"].exists || 
                     app.staticTexts["25"].exists ||
                     progressText.label.contains("25"))
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
        if addAssetButton.waitForExistence(timeout: 3) {
            addAssetButton.tap()
            
            setAssetCurrency(currency)
            
            let saveButton = app.buttons["saveAssetButton"].exists ? app.buttons["saveAssetButton"] : app.buttons["Save"]
            if saveButton.exists {
                saveButton.tap()
            }
        }
    }
    
    private func addTestTransaction(amount: String, assetCurrency: String? = nil) {
        expandAssetRow(for: assetCurrency)

        let addTransactionButton = app.buttons["addTransactionButton"].exists ? app.buttons["addTransactionButton"] : app.buttons["Add Transaction"]
        if addTransactionButton.waitForExistence(timeout: 3) {
            addTransactionButton.tap()
            
            let amountField = app.textFields["transactionAmountField"].exists ? app.textFields["transactionAmountField"] : app.textFields["Amount"]
            if amountField.waitForExistence(timeout: 3) {
                amountField.tap()
                amountField.typeText(amount)
            }
            
            let saveButton = app.buttons["saveTransactionButton"].exists ? app.buttons["saveTransactionButton"] : app.buttons["Save"]
            if saveButton.exists {
                saveButton.tap()
            }
        }
    }

    private func expandAssetRow(for currency: String?) {
        let row: XCUIElement
        if let currency {
            let identifier = "assetRow-\(currency.uppercased())"
            row = app.buttons[identifier].exists ? app.buttons[identifier] : app.otherElements[identifier]
        } else {
            let predicate = NSPredicate(format: "identifier BEGINSWITH 'assetRow-'")
            row = app.buttons.matching(predicate).firstMatch.exists
                ? app.buttons.matching(predicate).firstMatch
                : app.otherElements.matching(predicate).firstMatch
        }

        if row.waitForExistence(timeout: 5) {
            tapForce(row)
            return
        }

        if let currency {
            let label = currency.uppercased()
            let text = app.staticTexts[label].exists ? app.staticTexts[label] : app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if text.waitForExistence(timeout: 3) {
                tapForce(text)
            }
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

    private func setGoalCurrency(_ symbol: String) {
        if setCurrency(symbol: symbol, overrideId: "goalCurrencyOverrideField", buttonId: "currencyButton") {
            return
        }
    }

    private func setAssetCurrency(_ symbol: String) {
        if setCurrency(symbol: symbol, overrideId: "assetCurrencyOverrideField", buttonId: "assetCurrencyButton") {
            return
        }
    }

    private func setCurrency(symbol: String, overrideId: String, buttonId: String) -> Bool {
        let overrideField = app.textFields[overrideId]
        if overrideField.waitForExistence(timeout: 2) {
            overrideField.tap()
            clearTextField(overrideField)
            overrideField.typeText(symbol)
            return true
        }

        let button = app.buttons[buttonId]
        guard button.waitForExistence(timeout: 2) else { return false }
        button.tap()

        let search = app.textFields["currencySearchField"]
        if search.waitForExistence(timeout: 2) {
            search.tap()
            search.typeText(symbol)
            let cell = app.buttons["currencyCell-\(symbol.uppercased())"].firstMatch
            if cell.waitForExistence(timeout: 3) {
                cell.tap()
            } else if app.buttons["currencyDoneButton"].waitForExistence(timeout: 2) {
                app.buttons["currencyDoneButton"].tap()
            }
            return true
        }

        return false
    }

    private func clearTextField(_ element: XCUIElement) {
        guard let currentValue = element.value as? String else { return }
        if currentValue.isEmpty { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        element.typeText(deleteString)
    }
}
