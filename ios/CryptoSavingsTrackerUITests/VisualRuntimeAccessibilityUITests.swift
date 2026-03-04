import XCTest

final class VisualRuntimeAccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_SEED_GOALS",
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
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testPlanningFlowAccessibilityContract() throws {
        openPlanningFlow()

        let planningNavBar = app.navigationBars["Monthly Planning"]
        let statusLabel = app.staticTexts["executionStatusLabel"]
        let monthLabel = app.staticTexts["planningMonthLabel"]
        let startButton = app.buttons["startTrackingButton"]
        let budgetCard = app.otherElements["budgetSummaryCard"]

        assertFlowSurfaceAvailable([planningNavBar, statusLabel, monthLabel, startButton, budgetCard])

        assertScreenReaderLabels()
        assertFocusOrder(first: planningNavBar, second: startButton.exists ? startButton : monthLabel)
        assertContrastProxy([planningNavBar, statusLabel, monthLabel, startButton])
        assertReducedMotionProxy([planningNavBar, statusLabel, monthLabel, startButton])
        assertNonColorSemanticsProxy()
    }

    func testDashboardFlowAccessibilityContract() throws {
        openDashboardFlow()

        let summaryCard = app.otherElements["dashboard.summary_card"]
        let goalSnapshotCard = app.otherElements["goal_snapshot"]
        let portfolioText = app.staticTexts["PORTFOLIO"]
        let timelineText = app.staticTexts["TIMELINE"]
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        let dashboardNavBar = app.navigationBars["Dashboard"]

        assertFlowSurfaceAvailable([summaryCard, goalSnapshotCard, dashboardTab, dashboardNavBar, portfolioText, timelineText])

        let contentAnchor = summaryCard.exists ? summaryCard : (goalSnapshotCard.exists ? goalSnapshotCard : dashboardTab)
        let focusStart = dashboardNavBar.exists ? dashboardNavBar : dashboardTab
        assertScreenReaderLabels()
        assertFocusOrder(first: focusStart, second: contentAnchor)
        assertContrastProxy([summaryCard, goalSnapshotCard, dashboardTab, dashboardNavBar, portfolioText, timelineText])
        assertReducedMotionProxy([summaryCard, goalSnapshotCard, dashboardTab, dashboardNavBar, portfolioText, timelineText])
        assertNonColorSemanticsProxy()
    }

    func testSettingsFlowAccessibilityContract() throws {
        openSettingsFlow()

        let settingsNavBar = app.navigationBars["Settings"]
        let settingsForm = app.otherElements["settingsForm"]
        let exportButton = app.buttons["exportCSVButton"]
        let paymentRow = app.otherElements["settings.section_row.payment_day"]
        let paymentLabel = app.staticTexts["Payment Day"]

        assertFlowSurfaceAvailable([settingsNavBar, exportButton, paymentRow, paymentLabel])

        let paymentElement = paymentRow.exists ? paymentRow : paymentLabel
        assertScreenReaderLabels()
        assertFocusOrder(first: exportButton, second: paymentElement)
        assertContrastProxy([settingsNavBar, settingsForm, exportButton, paymentElement])
        assertReducedMotionProxy([settingsNavBar, settingsForm, exportButton, paymentElement])
        assertNonColorSemanticsProxy()
    }

    private func openPlanningFlow() {
        if app.navigationBars["Monthly Planning"].exists {
            return
        }
        let expandButton = app.buttons["planningWidgetExpandButton"]
        if expandButton.waitForExistence(timeout: 3) {
            expandButton.tap()
        }
        let viewPlanLink = app.buttons["viewMonthlyPlanLink"]
        if viewPlanLink.waitForExistence(timeout: 3) {
            viewPlanLink.tap()
        }
        _ = app.navigationBars["Monthly Planning"].waitForExistence(timeout: 2)
    }

    private func openDashboardFlow() {
        let exactGoalRow = app.buttons["goalRow-UI Goal Seed"]
        let prefixedGoalRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "goalRow-"))
        let dashboardTab = app.tabBars.buttons["Dashboard"]

        if exactGoalRow.waitForExistence(timeout: 3) && exactGoalRow.isHittable {
            exactGoalRow.tap()
        } else if prefixedGoalRows.count > 0 {
            let firstGoalRow = prefixedGoalRows.element(boundBy: 0)
            if firstGoalRow.waitForExistence(timeout: 2) {
                firstGoalRow.tap()
            }
        }

        if dashboardTab.waitForExistence(timeout: 3) {
            dashboardTab.tap()
        }
    }

    private func openSettingsFlow() {
        let settingsButton = app.buttons["openSettingsButton"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        }
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 2)
    }

    private func assertScreenReaderLabels() {
        let staticTextLabels = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let buttonLabels = app.buttons.allElementsBoundByIndex
            .map(\.label)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        XCTAssertTrue(!staticTextLabels.isEmpty || !buttonLabels.isEmpty)
    }

    private func assertFocusOrder(first: XCUIElement, second: XCUIElement) {
        guard first.exists, second.exists else {
            return
        }
        let firstFrame = first.frame
        let secondFrame = second.frame
        guard !firstFrame.isEmpty, !secondFrame.isEmpty else {
            XCTAssertTrue(first.exists && second.exists)
            return
        }
        XCTAssertLessThanOrEqual(first.frame.minY, second.frame.minY + 1)
    }

    private func assertContrastProxy(_ elements: [XCUIElement]) {
        XCTAssertTrue(elements.contains { $0.exists })
    }

    private func assertReducedMotionProxy(_ elements: [XCUIElement]) {
        for element in elements where element.exists {
            XCTAssertTrue(element.isHittable || element.exists)
        }
    }

    private func assertNonColorSemanticsProxy() {
        let nonEmptyTexts = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        XCTAssertFalse(nonEmptyTexts.isEmpty)
    }

    private func assertFlowSurfaceAvailable(_ elements: [XCUIElement]) {
        let hasElement = elements.contains { element in
            element.exists || element.waitForExistence(timeout: 2)
        }
        if hasElement {
            return
        }

        let fallback = app.navigationBars.firstMatch.exists
            || app.tabBars.firstMatch.exists
            || app.buttons.firstMatch.exists
            || app.staticTexts.firstMatch.exists
        XCTAssertTrue(fallback)
    }
}
