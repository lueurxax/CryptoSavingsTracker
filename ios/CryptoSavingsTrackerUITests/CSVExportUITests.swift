import XCTest

final class CSVExportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if os(iOS)
        XCUIDevice.shared.orientation = .portrait
#endif
    }

    @MainActor
    func testPublicMVPSettingsDoNotExposeCSVExport() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()

        let settingsButton = app.buttons["openSettingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        } else {
            let settingsTab = app.tabBars.buttons["Settings"]
            XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should be visible")
            settingsTab.tap()
        }

        XCTAssertTrue(app.buttons["dismissSettingsButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["exportCSVButton"].exists)
        XCTAssertFalse(app.staticTexts["Export Data (CSV)"].exists)
        XCTAssertFalse(app.otherElements["csvExportShareView"].exists)
    }
}
