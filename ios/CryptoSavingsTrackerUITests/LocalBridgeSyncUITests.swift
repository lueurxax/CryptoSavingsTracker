import XCTest

final class LocalBridgeSyncUITests: XCTestCase {
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

    private func launchApp(localBridgeScenario: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launchEnvironment["CST_RUNTIME_MODE"] = "debug_internal"
        app.launchEnvironment["UITEST_LOCAL_BRIDGE_SCENARIO"] = localBridgeScenario
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
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSyncRow"]
        XCTAssertTrue(localBridgeRow.waitForExistence(timeout: 5), "Local Bridge Sync row should be visible in Settings")
    }

    private func openLocalBridge() {
        openSettings()
        let localBridgeRow = app.buttons["settings.cloudkit.localBridgeSyncRow"]
        localBridgeRow.tap()
        XCTAssertTrue(app.navigationBars["Local Bridge Sync"].waitForExistence(timeout: 5))
    }

    private func anyElement(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func accessibilityValue(for identifier: String, timeout: TimeInterval = 5) -> String? {
        let element = anyElement(withIdentifier: identifier)
        guard element.waitForExistence(timeout: timeout) else {
            return nil
        }
        return element.value as? String
    }

    private func waitForStaticText(_ text: String, timeout: TimeInterval = 5, maxScrolls: Int = 3) -> Bool {
        let element = app.staticTexts[text]
        if element.waitForExistence(timeout: timeout) {
            return true
        }

        for _ in 0..<maxScrolls {
            app.swipeUp()
            if element.waitForExistence(timeout: 1.5) {
                return true
            }
        }

        return false
    }

    private func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        maxScrolls: Int = 3
    ) -> Bool {
        if element.waitForExistence(timeout: timeout) {
            return true
        }

        for _ in 0..<maxScrolls {
            app.swipeUp()
            if element.waitForExistence(timeout: 1.5) {
                return true
            }
        }

        return false
    }

    private func scrollToTop(maxSwipes: Int = 4) {
        for _ in 0..<maxSwipes {
            app.swipeDown()
        }
    }

    func testPairingRequiredScenarioShowsPairMacAndEmptyTrustedDevices() {
        launchApp(localBridgeScenario: "pairing_required")
        openLocalBridge()

        let availability = anyElement(withIdentifier: "localBridge.availability")
        XCTAssertTrue(availability.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStaticText("Pairing Required"))
        XCTAssertTrue(app.buttons["localBridge.pairMac"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["localBridge.pairMac"].label, "Pair Mac")
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.trustedDevices"), maxScrolls: 5))
        XCTAssertTrue(waitForStaticText("No trusted devices stored yet.", timeout: 1, maxScrolls: 5))
        XCTAssertTrue(anyElement(withIdentifier: "localBridge.manualBootstrap").exists)
    }

    func testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks() {
        launchApp(localBridgeScenario: "pairing_required")
        openLocalBridge()

        XCTAssertTrue(waitForElement(app.buttons["localBridge.pairMac"], maxScrolls: 5))
        XCTAssertEqual(accessibilityValue(for: "localBridge.manualBootstrap", timeout: 5), "Hidden")
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.pairingCode"), maxScrolls: 2))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.nearby.advertise"], maxScrolls: 6))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.nearby.browse"], maxScrolls: 2))
        XCTAssertTrue(waitForStaticText("Scan QR", timeout: 1, maxScrolls: 3))
        XCTAssertTrue(waitForStaticText("Paste Bootstrap Token", timeout: 1, maxScrolls: 3))

        scrollToTop()
        app.buttons["localBridge.pairMac"].tap()
        XCTAssertTrue(app.navigationBars["Enter Pairing Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.pairingEntry.input"), maxScrolls: 2))
    }

    func testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal() {
        launchApp(localBridgeScenario: "ready")
        openLocalBridge()

        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.manualBootstrap"), maxScrolls: 6))
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.pairingCode"), maxScrolls: 2))
        XCTAssertEqual(accessibilityValue(for: "localBridge.manualBootstrap", timeout: 5), "Hidden")
        XCTAssertEqual(accessibilityValue(for: "localBridge.bootstrapToken", timeout: 5), "Hidden")
        XCTAssertTrue(waitForElement(app.buttons["localBridge.bootstrapToken.toggle"], maxScrolls: 2))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.bootstrapToken.copy"], maxScrolls: 1))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.nearby.sendLatestSnapshot"], maxScrolls: 6))
    }

    func testReviewScenarioShowsDistinctOperatorActionsAndDismissPath() {
        launchApp(localBridgeScenario: "review_ready")
        openLocalBridge()

        let pendingAction = anyElement(withIdentifier: "localBridge.pendingAction")
        XCTAssertTrue(pendingAction.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(for: "localBridge.pendingAction"), "Review Import")
        XCTAssertTrue(waitForElement(app.buttons["localBridge.dismissImportReview"], maxScrolls: 10))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.importReview.open"], maxScrolls: 3))
        app.buttons["localBridge.importReview.open"].tap()

        XCTAssertTrue(app.navigationBars["Import Review"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.importReview.concreteDiffs"), maxScrolls: 5))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.importReview.approve"], maxScrolls: 6))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.importReview.reject"], maxScrolls: 5))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.importReview.resetPending"], maxScrolls: 5))
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.importReview.packageID"), maxScrolls: 5))

        app.buttons["localBridge.importReview.reject"].tap()
        scrollToTop()
        XCTAssertEqual(accessibilityValue(for: "localBridge.importReview.operatorDecision", timeout: 5), "Rejected")
    }

    func testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply() {
        launchApp(localBridgeScenario: "review_blocked")
        openLocalBridge()

        let availability = anyElement(withIdentifier: "localBridge.availability")
        XCTAssertTrue(availability.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(for: "localBridge.availability"), "Update Required")
        XCTAssertTrue(waitForElement(app.buttons["localBridge.dismissImportReview"], maxScrolls: 6))
        XCTAssertTrue(waitForElement(app.buttons["localBridge.importReview.open"], maxScrolls: 6))
        app.buttons["localBridge.importReview.open"].tap()

        XCTAssertTrue(waitForStaticText("Validation", timeout: 1, maxScrolls: 2))
        XCTAssertTrue(waitForStaticText("Drift", timeout: 1, maxScrolls: 2))
        let approveButton = app.buttons["localBridge.importReview.approve"]
        XCTAssertTrue(waitForElement(approveButton, maxScrolls: 5))
        XCTAssertFalse(approveButton.isEnabled, "Approve must be disabled when blocking issues are present")
        XCTAssertTrue(waitForElement(anyElement(withIdentifier: "localBridge.importReview.applyHint"), maxScrolls: 5))
    }
}
