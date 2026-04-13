import XCTest

final class PresentationScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        outputDirectory = ProcessInfo.processInfo.environment["PRESENTATION_SCREENSHOT_OUTPUT_DIR"]
        app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_SEED_MANY_GOALS",
            "UITEST_UI_FLOW",
            "-visual_system.debug_override.visual_system.wave1_planning",
            "YES",
            "-visual_system.debug_override.visual_system.wave2_dashboard",
            "YES",
            "-visual_system.debug_override.visual_system.wave3_settings",
            "YES",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        if let outputDirectory, !outputDirectory.isEmpty {
            app.launchEnvironment["PRESENTATION_SCREENSHOT_OUTPUT_DIR"] = outputDirectory
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCapturePresentationScreenshots() throws {
        launchAtHome()
        captureScreen(named: "01-goals-overview")

        openGoal(named: "UI Goal 1")
        captureScreen(named: "02-goal-detail")

        openDashboardTab()
        captureScreen(named: "03-goal-dashboard")

        launchAtHome()
        openSettings()
        captureScreen(named: "04-settings")
    }

    private func launchAtHome() {
        if app.state == .runningForeground {
            app.terminate()
        }
        app.launch()
        dismissMonthlyPlanningSettingsIfPresent(app)
        XCTAssertTrue(app.buttons["goalRow-UI Goal 1"].waitForExistence(timeout: 12), "Seeded goals list did not load")
        waitForSettledUI()
    }

    private func openGoal(named goalName: String) {
        let goalButton = app.buttons["goalRow-\(goalName)"]
        XCTAssertTrue(goalButton.waitForExistence(timeout: 8), "Goal row missing: \(goalName)")
        tapForce(goalButton)
        let detailsTab = app.tabBars.buttons["Details"]
        if detailsTab.waitForExistence(timeout: 3) {
            tapForce(detailsTab)
        }
        XCTAssertTrue(
            app.buttons["addAssetButton"].waitForExistence(timeout: 8) || app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 8),
            "Goal detail did not load"
        )
        waitForSettledUI()
    }

    private func openDashboardTab() {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 6), "Dashboard tab missing")
        tapForce(dashboardTab)

        let dashboardMarkers = [
            app.otherElements["dashboard.summary_card"],
            app.otherElements["goal_snapshot"],
            app.navigationBars["Dashboard"],
            app.staticTexts["PORTFOLIO"]
        ]
        XCTAssertTrue(
            dashboardMarkers.contains(where: { $0.waitForExistence(timeout: 6) || $0.exists }),
            "Dashboard view did not load"
        )
        waitForSettledUI(timeout: 10)
    }

    private func openSettings() {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 8), "Settings tab missing")
        tapForce(settingsTab)

        let settingsMarkers = [
            app.navigationBars["Settings"],
            app.staticTexts["Preferences"],
            app.otherElements["settingsForm"]
        ]
        XCTAssertTrue(
            settingsMarkers.contains(where: { $0.waitForExistence(timeout: 8) || $0.exists }),
            "Settings screen did not load"
        )
        waitForSettledUI()
    }

    private func captureScreen(named name: String) {
        let outputDirRaw = outputDirectory ?? ""
        XCTAssertFalse(outputDirRaw.isEmpty, "PRESENTATION_SCREENSHOT_OUTPUT_DIR is required")

        let outputDir = URL(fileURLWithPath: outputDirRaw, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let fileURL = outputDir.appendingPathComponent("\(name).png")
            let screenshot = app.screenshot()
            try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)
        } catch {
            XCTFail("Failed to write screenshot \(name): \(error)")
        }
    }

    private func waitForSettledUI(
        timeout: TimeInterval = 8,
        blockedTexts: [String] = ["Calculating...", "Loading...", "Refreshing..."]
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let hasBlockedText = blockedTexts.contains { app.staticTexts[$0].exists }
            let hasSpinner = app.activityIndicators.allElementsBoundByIndex.contains(where: \.exists)

            if !hasBlockedText && !hasSpinner {
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let textReturned = blockedTexts.contains { app.staticTexts[$0].exists }
                let spinnerReturned = app.activityIndicators.allElementsBoundByIndex.contains(where: \.exists)
                if !textReturned && !spinnerReturned {
                    return
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail("UI did not settle before screenshot capture")
    }
}

private func dismissMonthlyPlanningSettingsIfPresent(_ app: XCUIApplication) {
    let navBar = app.navigationBars["Monthly Planning Settings"]
    guard navBar.exists || navBar.waitForExistence(timeout: 0.5) else { return }

    let dismissButtons: [XCUIElement] = [
        navBar.buttons["Done"],
        navBar.buttons["Cancel"],
        app.buttons["Done"],
        app.buttons["Cancel"]
    ]

    for button in dismissButtons where button.exists {
        tapForce(button)
        _ = navBar.waitForNonExistence(timeout: 2)
        if !navBar.exists {
            return
        }
    }

    app.swipeDown()
    _ = navBar.waitForNonExistence(timeout: 2)
}

private func tapForce(_ element: XCUIElement) {
    if element.isHittable {
        element.tap()
    } else {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
