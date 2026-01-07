import XCTest

final class MonthlyPlanningCycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_SEED_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testFinishMonthAdvancesToNextMonthPlanningAndStartTrackingTargetsNextMonth() throws {
        #if os(macOS)
        throw XCTSkip("Flow is automated on iOS simulator.")
        #endif

        openMonthlyPlan(app)
        dismissMonthlyPlanningSettingsIfPresent(app)

        startTracking(app)
        let trackingMonth = bannerMonthLabel(app, prefix: "Recording contributions for")

        finishMonth(app)
        let planningMonth = bannerMonthLabel(app, prefix: "Planning for")
        XCTAssertNotEqual(planningMonth, trackingMonth, "Expected planning month to advance after completion.")

        startTracking(app)
        let nextTrackingMonth = bannerMonthLabel(app, prefix: "Recording contributions for")
        XCTAssertEqual(nextTrackingMonth, planningMonth, "Expected tracking month to match the next-month planning banner.")
    }

    func testUndoStartTrackingReturnsToCurrentMonthPlanning() throws {
        #if os(macOS)
        throw XCTSkip("Flow is automated on iOS simulator.")
        #endif

        openMonthlyPlan(app)
        dismissMonthlyPlanningSettingsIfPresent(app)

        startTracking(app)
        let trackingMonth = bannerMonthLabel(app, prefix: "Recording contributions for")

        returnToPlanning(app)
        let planningMonth = bannerMonthLabel(app, prefix: "Planning for")
        XCTAssertEqual(planningMonth, trackingMonth, "Expected undo start tracking to return to current month planning.")
    }
}

// MARK: - Helpers

private func openMonthlyPlan(_ app: XCUIApplication) {
    if !app.buttons["viewMonthlyPlanLink"].exists {
        let expand = app.buttons["planningWidgetExpandButton"].firstMatch
        if expand.waitForExistence(timeout: 6) {
            tapForce(expand)
        }
    }

    let viewPlanCandidates = [
        app.buttons["viewMonthlyPlanLink"],
        app.otherElements["viewMonthlyPlanLink"],
        app.staticTexts["viewMonthlyPlanLink"]
    ]
    let viewPlan = viewPlanCandidates.first(where: { $0.exists }) ?? viewPlanCandidates[0]
    XCTAssertTrue(viewPlan.waitForExistence(timeout: 10))
    tapForce(viewPlan)

    XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 10))
}

private func startTracking(_ app: XCUIApplication) {
    let startButton = app.buttons["startTrackingButton"]
    XCTAssertTrue(startButton.waitForExistence(timeout: 10))
    tapForce(startButton)

    let alert = app.alerts["Start Tracking?"]
    if alert.waitForExistence(timeout: 2) {
        alert.buttons["Start Tracking"].firstMatch.tap()
    }

    XCTAssertTrue(app.buttons["finishMonthButton"].waitForExistence(timeout: 10))
}

private func finishMonth(_ app: XCUIApplication) {
    let finishButton = app.buttons["finishMonthButton"]
    XCTAssertTrue(finishButton.waitForExistence(timeout: 10))
    tapForce(finishButton)

    let alert = app.alerts["Complete this month?"]
    if alert.waitForExistence(timeout: 2) {
        let finishAlertButton = alert.buttons["Finish Month"]
        if finishAlertButton.exists {
            finishAlertButton.tap()
        }
    }

    // Wait for UI to transition back to planning mode
    // The startTrackingButton should appear after finishing the month
    _ = app.buttons["startTrackingButton"].waitForExistence(timeout: 10)

    // Allow extra time for banner text to update
    sleep(1)
}

private func returnToPlanning(_ app: XCUIApplication) {
    let returnButton = app.buttons["returnToPlanningButton"]
    XCTAssertTrue(returnButton.waitForExistence(timeout: 10))
    tapForce(returnButton)

    let alert = app.alerts["Return to Planning Mode?"]
    if alert.waitForExistence(timeout: 2) {
        let confirmButton = alert.buttons["Return to Planning"]
        if confirmButton.exists {
            confirmButton.tap()
        }
    }

    XCTAssertTrue(app.buttons["startTrackingButton"].waitForExistence(timeout: 10))
}

private func bannerMonthLabel(_ app: XCUIApplication, prefix: String) -> String {
    let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
    let label = app.staticTexts.matching(predicate).firstMatch

    // Give the UI time to settle and update the banner
    if !label.waitForExistence(timeout: 15) {
        // Try scrolling to find the label
        app.swipeDown()
        _ = label.waitForExistence(timeout: 5)
    }

    XCTAssertTrue(label.exists, "Expected to find label with prefix: '\(prefix)'")

    let raw = label.label
    let stripped = raw.replacingOccurrences(of: prefix, with: "")
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
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

    app.swipeDown()
    _ = navBar.waitForNonExistence(timeout: 2)
}

private func tapForce(_ element: XCUIElement) {
    if element.isHittable {
        element.tap()
    } else {
        let coord = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.tap()
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }
}
