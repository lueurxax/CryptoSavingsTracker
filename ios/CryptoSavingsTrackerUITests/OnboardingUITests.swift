//
//  OnboardingUITests.swift
//  CryptoSavingsTrackerUITests
//
//  Created by Codex.
//

import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testOnboardingHappyPathCompletesAndShowsGoals() throws {
#if os(macOS)
        throw XCTSkip("Onboarding flow is iOS-only.")
#endif
        launchOnboardingFlow(simulateGoalSaveFailure: false)
        completeOnboardingFlow(profileChoice: "Some experience", templateName: "Emergency Fund")

        let startSavingButton = app.buttons["Start Saving"]
        XCTAssertTrue(startSavingButton.waitForExistence(timeout: 5))
        startSavingButton.tap()

        XCTAssertTrue(
            app.navigationBars["Goals"].waitForExistence(timeout: 8) ||
            app.navigationBars["Crypto Goals"].waitForExistence(timeout: 1),
            "Onboarding should transition to goals after successful template creation"
        )
    }

    func testOnboardingSaveFailureShowsRetryAndCompletesAfterRetry() throws {
#if os(macOS)
        throw XCTSkip("Onboarding flow is iOS-only.")
#endif
        launchOnboardingFlow(simulateGoalSaveFailure: true)
        completeOnboardingFlow(profileChoice: "Some experience", templateName: "Emergency Fund")

        let startSavingButton = app.buttons["Start Saving"]
        XCTAssertTrue(startSavingButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Your \"Emergency Fund\" goal is ready to track."].waitForExistence(timeout: 5),
            "Template selection should remain visible before save attempt"
        )

        startSavingButton.tap()

        XCTAssertTrue(
            app.staticTexts["Goal Setup Failed"].waitForExistence(timeout: 5),
            "Recoverable save failure should surface onboarding retry banner"
        )
        XCTAssertTrue(
            app.buttons["Retry"].waitForExistence(timeout: 5),
            "Retry action should be available for recoverable failures"
        )
        XCTAssertTrue(
            app.staticTexts["Your \"Emergency Fund\" goal is ready to track."].waitForExistence(timeout: 3),
            "Recoverable failure should preserve setup selection state for retry"
        )

        app.buttons["Retry"].tap()

        XCTAssertTrue(
            app.navigationBars["Goals"].waitForExistence(timeout: 10) ||
            app.navigationBars["Crypto Goals"].waitForExistence(timeout: 1),
            "Onboarding should complete after a successful retry"
        )
        XCTAssertFalse(
            app.staticTexts["Goal Setup Failed"].exists,
            "Retry success should clear onboarding error state"
        )
    }

    private func launchOnboardingFlow(simulateGoalSaveFailure: Bool) {
        app = XCUIApplication()
        var launchArguments = [
            "UITEST_RESET_DATA",
            "UITEST_FORCE_ONBOARDING",
            "UITEST_UI_FLOW",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        if simulateGoalSaveFailure {
            launchArguments.append("UITEST_SIMULATE_GOAL_SAVE_FAILURE")
        }
        app.launchArguments = launchArguments
        app.launch()
    }

    private func completeOnboardingFlow(profileChoice: String, templateName: String) {
        XCTAssertTrue(app.staticTexts["Welcome to CryptoSavings"].waitForExistence(timeout: 5))

        tapIfExists(app.buttons["Continue"])

        let profileOption = app.buttons[profileChoice]
        if profileOption.waitForExistence(timeout: 5) {
            profileOption.tap()
        }
        tapIfExists(app.buttons["Continue"])

        let templateButton = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", templateName)
        ).firstMatch
        XCTAssertTrue(templateButton.waitForExistence(timeout: 5))
        templateButton.tap()

        tapIfExists(app.buttons["Continue"])
        XCTAssertTrue(app.staticTexts["You're all set!"].waitForExistence(timeout: 5))
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 5) && element.isHittable {
            element.tap()
            return true
        }
        if element.waitForExistence(timeout: 5) {
            element.tap()
            return true
        }
        XCTFail("Expected to find and tap element: \(element)")
        return false
    }
}

