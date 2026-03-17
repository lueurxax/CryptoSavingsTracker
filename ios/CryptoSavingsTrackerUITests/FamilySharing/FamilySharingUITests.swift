//
//  FamilySharingUITests.swift
//  CryptoSavingsTrackerUITests
//

import XCTest

final class FamilySharingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func launchApp(familyShareScenario: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        if let familyShareScenario {
            app.launchEnvironment["UITEST_FAMILY_SHARE_SCENARIO"] = familyShareScenario
        }
        app.launch()
    }

    private func openSettings() {
        let settingsButton = app.buttons["openSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        let familyAccessRow = app.buttons["settings.cloudkit.familyAccess"]
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSync"]
        XCTAssertTrue(
            familyAccessRow.waitForExistence(timeout: 5) || localBridgeRow.waitForExistence(timeout: 5),
            "Settings sync rows should be visible after opening Settings"
        )
    }

    func testSettingsShowsFamilyAccessBeforeLocalBridgeSync() {
        launchApp()
        openSettings()

        let familyAccessRow = app.buttons["settings.cloudkit.familyAccess"]
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSync"]

        XCTAssertTrue(familyAccessRow.waitForExistence(timeout: 5), "Family Access row should be visible in Sync settings")
        XCTAssertTrue(localBridgeRow.waitForExistence(timeout: 5), "Local Bridge Sync row should remain visible in Sync settings")
        XCTAssertLessThan(familyAccessRow.frame.minY, localBridgeRow.frame.minY, "Family Access should appear before Local Bridge Sync")
    }

    func testInviteeScenarioShowsSharedGoalsAndReadOnlyDetail() {
        launchApp(familyShareScenario: "invitee_active")

        let sharedGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
            .firstMatch
        XCTAssertTrue(sharedGoalRow.waitForExistence(timeout: 5), "A shared goal row should be visible")
        XCTAssertTrue(
            app.staticTexts["Shared Goals"].exists || app.otherElements["sharedGoalsSection"].exists,
            "Shared Goals section should appear for invitee scenarios"
        )
        sharedGoalRow.tap()

        XCTAssertTrue(app.staticTexts["Read only"].waitForExistence(timeout: 5), "Shared goal detail should expose read-only state")
        XCTAssertFalse(app.buttons["Add Asset"].exists, "Shared goal detail must not expose owner mutation CTAs")
        XCTAssertFalse(app.buttons["Add Transaction"].exists, "Shared goal detail must not expose owner mutation CTAs")
    }
}
