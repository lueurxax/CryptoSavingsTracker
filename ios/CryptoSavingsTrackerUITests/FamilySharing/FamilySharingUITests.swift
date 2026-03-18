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

    private func launchApp(familyShareScenario: String? = nil, contentSizeCategory: String? = nil) {
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
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
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

    func testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders() {
        launchApp(familyShareScenario: "invitee_multi_owner")

        let alexHeader = app.otherElements["sharedGoalsOwnerHeader-shared-owner-shared-household"]
        let jordanHeader = app.otherElements["sharedGoalsOwnerHeader-shared-owner-coowner-shared-household-secondary"]

        XCTAssertTrue(alexHeader.waitForExistence(timeout: 5), "Primary owner header should be visible")
        XCTAssertTrue(jordanHeader.waitForExistence(timeout: 5), "Secondary owner header should be visible")
        XCTAssertLessThan(alexHeader.frame.minY, jordanHeader.frame.minY, "Owner headers should preserve grouping order")

        let alexGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-shared-owner-shared-household"))
            .firstMatch
        let jordanGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-shared-owner-coowner-shared-household-secondary"))
            .firstMatch

        XCTAssertTrue(alexGoalRow.waitForExistence(timeout: 5), "Primary owner shared goal row should be visible")
        XCTAssertTrue(jordanGoalRow.waitForExistence(timeout: 5), "Secondary owner shared goal row should be visible")
    }

    func testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction() {
        launchApp(familyShareScenario: "invitee_stale")

        let stateBanner = app.otherElements["sharedGoalsStateBanner-shared-owner-shared-household"]
        XCTAssertTrue(stateBanner.waitForExistence(timeout: 5), "Stale state banner should be visible")
        XCTAssertTrue(
            app.buttons["sharedGoalsPrimaryAction-shared-owner-shared-household"].waitForExistence(timeout: 5),
            "Non-active shared state should expose a primary action"
        )
        XCTAssertTrue(app.staticTexts["Retry Refresh"].exists || app.buttons["Retry Refresh"].exists)
    }

    func testScopePreviewKeepsPersistentCTAVisibleAtAccessibilitySize() {
        launchApp(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        openSettings()

        let familyAccessRow = app.buttons["settings.cloudkit.familyAccess"]
        XCTAssertTrue(familyAccessRow.waitForExistence(timeout: 5))
        familyAccessRow.tap()

        let shareButton = app.buttons["Share with Family"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5), "Scope preview trigger should be visible")
        shareButton.tap()

        XCTAssertTrue(app.otherElements["familyShareScopePreviewActionBar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5), "Scope preview must keep Continue discoverable")
        XCTAssertTrue(app.buttons["Cancel"].exists, "Scope preview must keep Cancel discoverable")
    }
}
