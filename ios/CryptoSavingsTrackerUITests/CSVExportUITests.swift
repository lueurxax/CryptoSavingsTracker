import XCTest

final class CSVExportUITests: XCTestCase {
    private func element(_ app: XCUIApplication, labelContains labelFragment: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", labelFragment))
            .firstMatch
    }

    private func findExportControl(_ app: XCUIApplication) -> XCUIElement {
        let candidates = [
            app.buttons["exportCSVButton"],
            app.otherElements["exportCSVButton"],
            app.staticTexts["exportCSVButton"],
            app.buttons["Export Data (CSV)"],
            app.otherElements["Export Data (CSV)"],
            app.staticTexts["Export Data (CSV)"],
            element(app, labelContains: "Export")
        ]

        return candidates.first(where: { $0.exists }) ?? candidates.last!
    }

    @MainActor
    func testExportCSVFromSettingsShowsThreeFiles() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()

        let settingsButton = app.buttons["openSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        XCTAssertTrue(app.buttons["dismissSettingsButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        var exportElement = findExportControl(app)
        if !exportElement.exists {
            let formContainer: XCUIElement = {
                if app.otherElements["settingsForm"].exists { return app.otherElements["settingsForm"] }
                if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
                return app
            }()
            let scrollContainer: XCUIElement = formContainer.scrollViews.firstMatch.exists
                ? formContainer.scrollViews.firstMatch
                : formContainer
            for _ in 0..<20 {
                scrollContainer.swipeUp()
                exportElement = findExportControl(app)
                if exportElement.exists { break }
            }
        }
        XCTAssertTrue(exportElement.waitForExistence(timeout: 2))
        exportElement.tap()

        XCTAssertTrue(app.otherElements["csvExportShareView"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["csvExportHeader"].exists)
        XCTAssertTrue(app.staticTexts["csvFileName-goals.csv"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["csvFileName-assets.csv"].exists)
        XCTAssertTrue(app.staticTexts["csvFileName-value_changes.csv"].exists)
    }
}
