import XCTest

final class GoalCompletionSettlementUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_UI_FLOW",
            "UITEST_SEED_FINISHED_SETTLEMENTS",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launch()
        openGoalsTab()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testManualGoalFinishesAutomaticallyWithoutSettlementSheet() throws {
        try finishGoal(named: "Manual Finish Goal")

        XCTAssertFalse(
            app.descendants(matching: .any)["goalCompletionSettlementSheet"].waitForExistence(timeout: 2),
            "Manual-only completion must not ask for a settlement decision."
        )
        assertGoalIsAbsentFromActiveList(named: "Manual Finish Goal")
    }

    func testOnChainGoalFinishesAutomaticallyWithoutSettlementSheet() throws {
        try finishGoal(named: "On-chain Finish Goal")

        XCTAssertFalse(
            app.descendants(matching: .any)["goalCompletionSettlementSheet"].waitForExistence(timeout: 2),
            "Wallet-only completion must not ask for a settlement decision."
        )
        assertGoalIsAbsentFromActiveList(named: "On-chain Finish Goal")
    }

    func testMixedGoalRequiresChoiceAndShowsReleaseSummary() throws {
        try beginFinishGoal(named: "Mixed Finish Goal")

        let sheet = app.descendants(matching: .any)["goalCompletionSettlementSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Mixed completion must present the settlement sheet.")

        let apply = app.buttons["applyGoalCompletionSettlement"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "Apply must remain disabled until every mixed allocation has a choice.")

        let settlementChoice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "settlementChoice-"))
            .firstMatch
        XCTAssertTrue(settlementChoice.waitForExistence(timeout: 5))
        settlementChoice.tap()
        chooseMenuItem(named: "Balance already decreased")

        waitUntilEnabled(apply)
        XCTAssertTrue(app.staticTexts["Released for new goals"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["USDT"].waitForExistence(timeout: 5))

        apply.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        assertGoalIsAbsentFromActiveList(named: "Mixed Finish Goal")
    }

    func testLegacyReviewIsDeferredAndAppliesAllGoalAllocationsAtomically() throws {
        openGoal(named: "Legacy Review Host")

        let assetRow = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "assetRow-USDT",
                "USDT"
            )
        ).firstMatch
        XCTAssertTrue(assetRow.waitForExistence(timeout: 10))
        tapDisclosureArea(of: assetRow)

        let manageAllocations = app.buttons["manageAllocationButton"].firstMatch
        if manageAllocations.waitForExistence(timeout: 2) == false {
            tapDisclosureArea(of: assetRow)
        }
        XCTAssertTrue(manageAllocations.waitForExistence(timeout: 8))
        manageAllocations.tap()

        let pendingSection = app.descendants(matching: .any)["pendingReviewAllocationsSection"]
        XCTAssertTrue(pendingSection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Pending review"].waitForExistence(timeout: 5))

        let review = app.buttons["Review finished allocations"].firstMatch
        XCTAssertTrue(
            waitForHittableWithScroll(review),
            "The legacy review action must be reachable from the pending section."
        )
        review.tap()

        let reviewSheet = app.descendants(matching: .any)["legacyFinishedAllocationReviewSheet"]
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["USDT"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BTC"].waitForExistence(timeout: 5))

        app.buttons["laterLegacyFinishedAllocationReview"].tap()
        XCTAssertTrue(reviewSheet.waitForNonExistence(timeout: 8))
        XCTAssertTrue(pendingSection.waitForExistence(timeout: 5), "Later must leave the legacy allocation pending.")

        review.tap()
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 10))
        chooseEveryLegacySettlement(named: "Keep as spent", expectedCount: 2)

        let applyReview = app.buttons["applyLegacyFinishedAllocationReview"]
        waitUntilEnabled(applyReview)
        applyReview.tap()

        XCTAssertTrue(reviewSheet.waitForNonExistence(timeout: 10))
        XCTAssertTrue(pendingSection.waitForNonExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["reservedAsSpentAllocationsSection"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Reserved as spent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Legacy Finished Goal"].waitForExistence(timeout: 5))
    }

    private func openGoalsTab() {
        let goalsTab = app.tabBars.buttons["Goals"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 15))
        goalsTab.tap()
        XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 10))
    }

    private func openGoal(named name: String) {
        let row = app.buttons["goalRow-\(name)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Seeded goal row was not found: \(name)")
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), "Goal detail did not open: \(name)")
    }

    private func beginFinishGoal(named name: String) throws {
        openGoal(named: name)

        let actions = app.buttons["Goal actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()

        let delete = app.buttons["Delete Goal"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let finish = app.buttons["Finish Goal"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
    }

    private func finishGoal(named name: String) throws {
        try beginFinishGoal(named: name)
    }

    private func assertGoalIsAbsentFromActiveList(named name: String) {
        if app.navigationBars[name].exists {
            app.navigationBars[name].buttons.element(boundBy: 0).tap()
        }
        if app.navigationBars["Goals"].waitForExistence(timeout: 5) == false {
            openGoalsTab()
        }
        XCTAssertTrue(
            app.buttons["goalRow-\(name)"].waitForNonExistence(timeout: 10),
            "Finished goal must disappear from the active goals list: \(name)"
        )
    }

    private func chooseEveryLegacySettlement(named option: String, expectedCount: Int) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "legacySettlementChoice-")
        let choices = app.descendants(matching: .any).matching(predicate)
        XCTAssertEqual(choices.count, expectedCount, "The review must include every allocation of the legacy goal.")

        for index in 0..<expectedCount {
            let choice = choices.element(boundBy: index)
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            chooseMenuItem(named: option)
        }
    }

    private func chooseMenuItem(named name: String) {
        let item = app.buttons[name].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Settlement option was not visible: \(name)")
        item.tap()
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func tapDisclosureArea(of assetRow: XCUIElement) {
        assetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func waitForHittableWithScroll(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
        }
        return false
    }
}
