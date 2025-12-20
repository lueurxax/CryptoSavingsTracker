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
        
        // Clear any existing data by using launch arguments
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Tests
    
    @MainActor
    func testAppLaunch() throws {
        // Verify the main UI elements are present
        XCTAssertTrue(app.navigationBars["Crypto Goals"].exists)
        XCTAssertTrue(app.buttons["Plus"].exists || app.buttons["+"].exists)
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
        // Tap the add button
        let addButton = app.buttons["Plus"].exists ? app.buttons["Plus"] : app.buttons["+"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        
        // Should show the add goal form
        XCTAssertTrue(app.navigationBars["Add Goal"].waitForExistence(timeout: 3))
        
        // Fill in the form
        let nameField = app.textFields["Goal Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Bitcoin Savings")
        
        let amountField = app.textFields["Target Amount"]
        XCTAssertTrue(amountField.exists)
        amountField.tap()
        amountField.typeText("10000")
        
        let currencyField = app.textFields["Currency"]
        XCTAssertTrue(currencyField.exists)
        currencyField.tap()
        // Clear existing text and type new
        currencyField.doubleTap()
        currencyField.typeText("USD")
        
        // Set deadline (assume there's a date picker)
        if app.datePickers.count > 0 {
            let datePicker = app.datePickers.firstMatch
            datePicker.tap()
            // Set a future date (basic interaction)
        }
        
        // Save the goal
        let saveButton = app.buttons["Save Goal"]
        if saveButton.exists {
            saveButton.tap()
        } else {
            // Try alternative save button text
            app.buttons["Save"].tap()
        }
        
        // Should return to goals list and show the new goal
        XCTAssertTrue(app.navigationBars["Crypto Goals"].waitForExistence(timeout: 3))
        
        // Verify the goal appears in the list
        let goalCell = app.cells.containing(.staticText, identifier: "Bitcoin Savings").firstMatch
        XCTAssertTrue(goalCell.waitForExistence(timeout: 5))
    }
    
    @MainActor
    func testGoalFormValidation() throws {
        // Tap add button
        let addButton = app.buttons["Plus"].exists ? app.buttons["Plus"] : app.buttons["+"]
        addButton.tap()
        
        // Try to save without filling required fields
        let saveButton = app.buttons["Save Goal"].exists ? app.buttons["Save Goal"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
            
            // Should stay on the form (validation failed)
            XCTAssertTrue(app.navigationBars["Add Goal"].exists)
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
        XCTAssertTrue(app.staticTexts["1000"].exists || app.staticTexts["1000.00"].exists)
        XCTAssertTrue(app.staticTexts["USD"].exists)
        
        // Should have Add Asset button
        XCTAssertTrue(app.buttons["Add Asset"].waitForExistence(timeout: 3))
    }
    
    @MainActor
    func testAddAssetToGoal() throws {
        // Create a goal and navigate to detail
        createTestGoal(name: "Asset Goal", amount: "5000", currency: "USD")
        
        let goalCell = app.cells.containing(.staticText, identifier: "Asset Goal").firstMatch
        goalCell.tap()
        
        // Tap Add Asset
        let addAssetButton = app.buttons["Add Asset"]
        XCTAssertTrue(addAssetButton.waitForExistence(timeout: 5))
        addAssetButton.tap()
        
        // Should show add asset form
        XCTAssertTrue(app.navigationBars["Add Asset"].waitForExistence(timeout: 3))
        
        // Fill in asset details
        let currencyField = app.textFields.firstMatch
        XCTAssertTrue(currencyField.waitForExistence(timeout: 3))
        currencyField.tap()
        currencyField.typeText("BTC")
        
        // Save asset
        let saveButton = app.buttons["Save Asset"].exists ? app.buttons["Save Asset"] : app.buttons["Save"]
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
        
        // Tap Add Transaction button for the asset
        let addTransactionButton = app.buttons["Add Transaction"]
        XCTAssertTrue(addTransactionButton.waitForExistence(timeout: 5))
        addTransactionButton.tap()
        
        // Should show add transaction form
        XCTAssertTrue(app.navigationBars["Add Transaction"].waitForExistence(timeout: 3))
        
        // Fill in transaction amount
        let amountField = app.textFields["Amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("1.5")
        
        // Save transaction
        let saveButton = app.buttons["Save Transaction"].exists ? app.buttons["Save Transaction"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        }
        
        // Should return to goal detail and show updated asset amount
        XCTAssertTrue(app.staticTexts["1.5"].waitForExistence(timeout: 5) || 
                     app.staticTexts["1.50"].waitForExistence(timeout: 5) ||
                     app.staticTexts["1.5000"].waitForExistence(timeout: 5))
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
        addTestTransaction(amount: "250")
        
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
        let addButton = app.buttons["Plus"].exists ? app.buttons["Plus"] : app.buttons["+"]
        addButton.tap()
        
        // On macOS, should show as popover
        XCTAssertTrue(app.popovers.count > 0 || app.sheets.count > 0)
        
        #else
        // Test iOS-specific sheet behavior
        let addButton = app.buttons["Plus"].exists ? app.buttons["Plus"] : app.buttons["+"]
        addButton.tap()
        
        // On iOS, should show as sheet
        XCTAssertTrue(app.sheets.count > 0 || app.navigationBars["Add Goal"].exists)
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
        let addButton = app.buttons["Plus"].exists ? app.buttons["Plus"] : app.buttons["+"]
        addButton.tap()
        
        let nameField = app.textFields["Goal Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText(name)
        }
        
        let amountField = app.textFields["Target Amount"]
        if amountField.exists {
            amountField.tap()
            amountField.typeText(amount)
        }
        
        let currencyField = app.textFields["Currency"]
        if currencyField.exists {
            currencyField.tap()
            currencyField.doubleTap() // Select all
            currencyField.typeText(currency)
        }
        
        let saveButton = app.buttons["Save Goal"].exists ? app.buttons["Save Goal"] : app.buttons["Save"]
        if saveButton.exists {
            saveButton.tap()
        }
        
        // Wait for return to main screen
        _ = app.navigationBars["Crypto Goals"].waitForExistence(timeout: 5)
    }
    
    private func addTestAsset(currency: String) {
        let addAssetButton = app.buttons["Add Asset"]
        if addAssetButton.waitForExistence(timeout: 3) {
            addAssetButton.tap()
            
            let currencyField = app.textFields.firstMatch
            if currencyField.waitForExistence(timeout: 3) {
                currencyField.tap()
                currencyField.typeText(currency)
            }
            
            let saveButton = app.buttons["Save Asset"].exists ? app.buttons["Save Asset"] : app.buttons["Save"]
            if saveButton.exists {
                saveButton.tap()
            }
        }
    }
    
    private func addTestTransaction(amount: String) {
        let addTransactionButton = app.buttons["Add Transaction"]
        if addTransactionButton.waitForExistence(timeout: 3) {
            addTransactionButton.tap()
            
            let amountField = app.textFields["Amount"]
            if amountField.waitForExistence(timeout: 3) {
                amountField.tap()
                amountField.typeText(amount)
            }
            
            let saveButton = app.buttons["Save Transaction"].exists ? app.buttons["Save Transaction"] : app.buttons["Save"]
            if saveButton.exists {
                saveButton.tap()
            }
        }
    }
}