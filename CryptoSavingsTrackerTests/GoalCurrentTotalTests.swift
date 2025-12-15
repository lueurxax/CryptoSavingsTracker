//
//  GoalCurrentTotalTests.swift
//  CryptoSavingsTrackerTests
//
//  Minimal placeholder to satisfy legacy references.
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct GoalCurrentTotalTests {
    @Test("Current total placeholder")
    func testCurrentTotalPlaceholder() async throws {
        // Basic sanity: a goal with no allocations has zero current total.
        let goal = Goal(
            name: "Placeholder",
            currency: "USD",
            targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400)
        )
        #expect(goal.currentTotal == 0)
    }
}
