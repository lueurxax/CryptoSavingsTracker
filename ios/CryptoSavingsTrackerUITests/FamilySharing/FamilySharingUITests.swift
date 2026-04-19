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
        if let app, app.state != .notRunning {
            app.terminate()
        }
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
        app.launchEnvironment["CST_RUNTIME_MODE"] = "debug_internal"
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
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        } else {
            let settingsTab = app.tabBars.buttons["Settings"]
            XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should be visible")
            settingsTab.tap()
        }
        let familyAccessRow = app.buttons["settings.cloudkit.familyAccessRow"]
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSyncRow"]
        XCTAssertTrue(
            familyAccessRow.waitForExistence(timeout: 5) || localBridgeRow.waitForExistence(timeout: 5),
            "Settings sync rows should be visible after opening Settings"
        )
    }

    private func anyElement(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func isVisibleOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.isEmpty == false else { return false }
        let window = app.windows.firstMatch
        guard window.exists else { return element.isHittable }
        return frame.intersects(window.frame)
    }

    @discardableResult
    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 4) -> Bool {
        if isVisibleOnScreen(element) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), isVisibleOnScreen(element) {
                return true
            }
        }

        return isVisibleOnScreen(element)
    }

    @discardableResult
    private func waitForSharedGoalsHydration(timeout: TimeInterval = 20) -> Bool {
        let sharedWithYou = app.staticTexts["Shared with You"]
        let sharedSection = anyElement(withIdentifier: "sharedGoalsSection")
        let sharedGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
            .firstMatch
        let freshnessHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalsFreshnessHeader-"))
            .firstMatch
        let emptyState = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalsEmptyState-"))
            .firstMatch
        if sharedWithYou.waitForExistence(timeout: timeout) {
            return true
        }
        if sharedSection.waitForExistence(timeout: 1) {
            return true
        }
        if freshnessHeader.waitForExistence(timeout: 1) {
            return true
        }
        if emptyState.waitForExistence(timeout: 1) {
            return true
        }
        return sharedGoalRow.waitForExistence(timeout: 1)
    }

    func testSettingsShowsFamilyAccessBeforeLocalBridgeSync() {
        launchApp()
        openSettings()

        let familyAccessRow = app.buttons["settings.cloudkit.familyAccessRow"]
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSyncRow"]

        XCTAssertTrue(familyAccessRow.waitForExistence(timeout: 5), "Family Access row should be visible in Sync settings")
        XCTAssertTrue(localBridgeRow.waitForExistence(timeout: 5), "Local Bridge Sync row should remain visible in Sync settings")
        XCTAssertLessThan(familyAccessRow.frame.minY, localBridgeRow.frame.minY, "Family Access should appear before Local Bridge Sync")
    }

    func testInviteeScenarioShowsSharedWithYouAndReadOnlyDetail() {
        launchApp(familyShareScenario: "invitee_active")

        XCTAssertTrue(waitForSharedGoalsHydration(), "Shared with You section should hydrate before assertions")
        let sharedGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
            .firstMatch
        XCTAssertTrue(sharedGoalRow.waitForExistence(timeout: 5), "A shared goal row should be visible")
        XCTAssertTrue(app.staticTexts["Shared with You"].waitForExistence(timeout: 5), "Shared with You should be the invitee entry cue")
        XCTAssertFalse(app.staticTexts["Shared Goals"].exists, "Legacy Shared Goals explainer copy must not appear")
        XCTAssertFalse(app.staticTexts["Shared by family"].exists, "Legacy shared-by-family badge must not appear")
        sharedGoalRow.tap()

        XCTAssertTrue(app.staticTexts["Read-only"].waitForExistence(timeout: 5), "Shared goal detail should expose read-only state")
        let freshnessCard = anyElement(withIdentifier: "sharedGoalDetailFreshnessCard")
        XCTAssertTrue(freshnessCard.waitForExistence(timeout: 5), "Shared goal detail should expose freshness card")
        XCTAssertTrue(scrollUntilVisible(freshnessCard, maxSwipes: 6), "Freshness card should be reachable in shared goal detail")
        XCTAssertFalse(app.buttons["Add Asset"].exists, "Shared goal detail must not expose owner mutation CTAs")
        XCTAssertFalse(app.buttons["Add Transaction"].exists, "Shared goal detail must not expose owner mutation CTAs")
    }

    func testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders() {
        launchApp(familyShareScenario: "invitee_multi_owner")

        XCTAssertTrue(waitForSharedGoalsHydration(), "Shared with You section should hydrate before group assertions")
        let alexSection = anyElement(withIdentifier: "sharedGoalsOwnerSection-shared-owner-shared-household")
        let jordanSection = anyElement(withIdentifier: "sharedGoalsOwnerSection-shared-owner-coowner-shared-household-secondary")

        XCTAssertTrue(alexSection.waitForExistence(timeout: 5), "Primary owner section should be visible")
        XCTAssertTrue(app.staticTexts["Alex"].waitForExistence(timeout: 5), "Primary owner label should be visible")
        XCTAssertTrue(scrollUntilVisible(jordanSection, maxSwipes: 3), "Secondary owner section should be visible")
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Jordan"], maxSwipes: 1), "Secondary owner label should be visible")

        let alexGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-shared-owner-shared-household"))
            .firstMatch
        let jordanGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-shared-owner-coowner-shared-household-secondary"))
            .firstMatch

        XCTAssertTrue(alexGoalRow.waitForExistence(timeout: 5), "Primary owner shared goal row should be visible")
        XCTAssertTrue(jordanGoalRow.waitForExistence(timeout: 5), "Secondary owner shared goal row should be visible")
        XCTAssertFalse(app.staticTexts["Shared Goals"].exists, "Legacy Shared Goals explainer copy must not appear")
        XCTAssertFalse(app.staticTexts["Shared by family"].exists, "Legacy shared-by-family badge must not appear")
        XCTAssertFalse(app.staticTexts["Current"].exists, "Healthy rows must not show a default lifecycle chip")
        XCTAssertFalse(app.staticTexts["On track"].exists, "Healthy rows must not show a default lifecycle chip")
        XCTAssertFalse(app.staticTexts["Just started"].exists, "Healthy rows must not show a default lifecycle chip")
    }

    func testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction() {
        launchApp(familyShareScenario: "invitee_stale")

        XCTAssertTrue(waitForSharedGoalsHydration(), "Shared with You section should hydrate before stale-state assertions")
        XCTAssertTrue(
            scrollUntilVisible(app.buttons["Retry Refresh"], maxSwipes: 2),
            "Non-active shared state should expose a primary action"
        )
        let lastSharedMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Last shared")).firstMatch
        let ratesOldMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Rates are")).firstMatch
        XCTAssertTrue(
            lastSharedMessage.exists || ratesOldMessage.exists,
            "Stale section should expose freshness copy"
        )
        XCTAssertTrue(app.staticTexts["Achieved"].exists || app.staticTexts["Expired"].exists, "Row lifecycle states should remain visible when the section is unhealthy")
        let legacyBanner = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalsStateBanner-"))
            .firstMatch
        XCTAssertFalse(legacyBanner.exists, "Stale namespaces should use freshness header semantics instead of an escalated banner")
        XCTAssertFalse(app.staticTexts["Shared Goals"].exists, "Legacy Shared Goals explainer copy must not appear")
    }

    func testInviteeScenarioSuppressesBlockedDeviceOwnerLabels() {
        launchApp(familyShareScenario: "invitee_blocked_owner")

        XCTAssertTrue(waitForSharedGoalsHydration())
        XCTAssertFalse(app.staticTexts["iPhone"].exists, "Blocked device labels must not be shown as owner identity")
        XCTAssertTrue(app.staticTexts["Family member"].exists || app.staticTexts["Shared by Family member"].exists)
    }

    func testInviteeScenarioUsesLockedOwnershipLineAndSuppressesHealthyLifecycleChip() {
        launchApp(familyShareScenario: "invitee_active")

        XCTAssertTrue(waitForSharedGoalsHydration())
        XCTAssertTrue(
            app.staticTexts["Shared by Alex · Read-only"].waitForExistence(timeout: 5),
            "Healthy rows must use the locked ownership line contract"
        )
        XCTAssertFalse(app.staticTexts["Current"].exists, "Healthy rows must not show a Current chip")
        XCTAssertFalse(app.staticTexts["On track"].exists, "Healthy rows must not show an On track chip")
        XCTAssertFalse(app.staticTexts["Just started"].exists, "Healthy rows must not show a Just started chip")
    }

    func testInviteeScenarioDisambiguatesMultipleFallbackOwners() {
        launchApp(familyShareScenario: "invitee_multi_owner_unresolved")

        XCTAssertTrue(waitForSharedGoalsHydration(), "Shared with You section should hydrate before fallback-owner assertions")
        XCTAssertTrue(app.staticTexts["Family member 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Family member 2"], maxSwipes: 3))
        XCTAssertFalse(app.staticTexts["iPhone"].exists, "Blocked device labels must not leak into unresolved multi-owner grouping")
        XCTAssertFalse(app.staticTexts["iPad"].exists, "Blocked device labels must not leak into unresolved multi-owner grouping")
    }

    func testScopePreviewKeepsPersistentCTAVisibleAtAccessibilitySize() {
        launchApp(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        openSettings()

        let familyAccessRow = app.buttons["settings.cloudkit.familyAccessRow"]
        XCTAssertTrue(familyAccessRow.waitForExistence(timeout: 5))
        familyAccessRow.tap()

        let shareButton = app.buttons["Share with Family"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5), "Scope preview trigger should be visible")
        shareButton.tap()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5), "Scope preview must keep Continue discoverable")
        XCTAssertTrue(app.buttons["Cancel"].exists, "Scope preview must keep Cancel discoverable")
    }

    func testNoSharedNamespacesSuppressesFreshnessChrome() {
        launchApp()

        XCTAssertFalse(app.staticTexts["Shared with You"].waitForExistence(timeout: 3), "No shared section should render without invitee namespaces")
        let freshnessHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalsFreshnessHeader-"))
            .firstMatch
        XCTAssertFalse(freshnessHeader.exists, "Freshness chrome must be suppressed when no shared namespaces exist")
    }

    func testInviteeEmptyNamespaceShowsFreshnessHeaderButNoRows() {
        launchApp(familyShareScenario: "invitee_empty")

        XCTAssertTrue(waitForSharedGoalsHydration())
        XCTAssertTrue(
            app.staticTexts["No shared goals in this group."].waitForExistence(timeout: 5),
            "Empty namespace should expose the empty shared-goals copy"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
                .firstMatch
                .exists
        )
    }

    func testInviteeUnavailableNamespaceShowsRetryWithoutRows() {
        launchApp(familyShareScenario: "invitee_unavailable")

        XCTAssertTrue(waitForSharedGoalsHydration())
        XCTAssertTrue(scrollUntilVisible(app.buttons["Retry"], maxSwipes: 2))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "temporarily unavailable")).firstMatch.waitForExistence(timeout: 5),
            "Unavailable namespace should expose recovery copy"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
                .firstMatch
                .exists
        )
    }

    func testInviteeDetailFreshnessCardCollapsesExactTimestampAtAccessibilitySize() {
        launchApp(familyShareScenario: "invitee_active", contentSizeCategory: "UICTContentSizeCategoryAccessibilityXL")

        XCTAssertTrue(waitForSharedGoalsHydration())
        let sharedGoalRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sharedGoalRow-"))
            .firstMatch
        XCTAssertTrue(sharedGoalRow.waitForExistence(timeout: 5))
        sharedGoalRow.tap()

        let freshnessCard = anyElement(withIdentifier: "sharedGoalDetailFreshnessCard")
        XCTAssertTrue(
            freshnessCard.waitForExistence(timeout: 5),
            "Detail should finish navigation before freshness assertions"
        )
        XCTAssertTrue(
            scrollUntilVisible(freshnessCard, maxSwipes: 8),
            "Freshness card should be reachable at accessibility sizes"
        )
        XCTAssertEqual(freshnessCard.value as? String, "Collapsed")
        freshnessCard.tap()
        XCTAssertEqual(freshnessCard.value as? String, "Expanded")
    }
}
