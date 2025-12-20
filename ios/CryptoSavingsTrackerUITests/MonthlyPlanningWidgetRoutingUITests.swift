import XCTest

final class MonthlyPlanningWidgetRoutingUITests: XCTestCase {
    @MainActor
    func testViewMonthlyPlanDoesNotOpenPlanningSettingsSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_SEED_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()

        let expandButton = app.buttons["planningWidgetExpandButton"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10))
        expandButton.tap()

        let viewPlanCandidates = [
            app.buttons["viewMonthlyPlanLink"],
            app.otherElements["viewMonthlyPlanLink"],
            app.staticTexts["viewMonthlyPlanLink"]
        ]
        let viewPlan = viewPlanCandidates.first(where: { $0.exists }) ?? viewPlanCandidates[0]
        XCTAssertTrue(viewPlan.waitForExistence(timeout: 10))
        viewPlan.tap()

        XCTAssertFalse(app.navigationBars["Monthly Planning Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 10))
    }
}

