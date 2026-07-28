import XCTest

final class MonthlyPlanningWidgetRoutingUITests: XCTestCase {
    @MainActor
    func testPlanningAddGoalUsesNavigationDestinationInsteadOfSettingsSheet() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_SEED_GOALS",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()

        let planningTab = app.tabBars.buttons["Planning"]
        XCTAssertTrue(planningTab.waitForExistence(timeout: 10))
        planningTab.tap()

        XCTAssertTrue(app.navigationBars["Monthly Planning"].waitForExistence(timeout: 10))

        let addGoalButton = app.buttons["addGoalButton"]
        XCTAssertTrue(addGoalButton.waitForExistence(timeout: 10))
        addGoalButton.tap()

        XCTAssertFalse(app.navigationBars["Monthly Planning Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.navigationBars["New Goal"].waitForExistence(timeout: 10)
                || app.navigationBars["Add Goal"].waitForExistence(timeout: 10)
        )
    }
}
