//
//  CommitDockAnalyticsTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct CommitDockAnalyticsTests {

    // MARK: - Phase change logging with cooldown = 0

    @Test("Phase change logs immediately with zero cooldown")
    func phaseChangeLogsWithZeroCooldown() {
        let tracker = CommitDockAnalyticsTracker(
            clock: { Date() },
            transitionCooldown: 0
        )

        let logged = tracker.logPhaseChange(to: .collapsed)
        #expect(logged == true)
        #expect(tracker.sessionCollapseCount == 1)
        #expect(tracker.sessionExpandCount == 0)
    }

    // MARK: - Cooldown suppression

    @Test("Cooldown suppresses rapid successive logs")
    func cooldownSuppressesRapidLogs() {
        let fixedDate = Date()
        var currentTime = fixedDate

        let tracker = CommitDockAnalyticsTracker(
            clock: { currentTime },
            transitionCooldown: 1.0
        )

        // First log succeeds
        let first = tracker.logPhaseChange(to: .collapsed)
        #expect(first == true)
        #expect(tracker.sessionCollapseCount == 1)

        // Advance by 0.5s (within cooldown) — should be suppressed
        currentTime = fixedDate.addingTimeInterval(0.5)
        let second = tracker.logPhaseChange(to: .expanded)
        #expect(second == false)
        #expect(tracker.sessionExpandCount == 0)

        // Advance past cooldown — should succeed
        currentTime = fixedDate.addingTimeInterval(1.1)
        let third = tracker.logPhaseChange(to: .expanded)
        #expect(third == true)
        #expect(tracker.sessionExpandCount == 1)
    }

    // MARK: - Independent instances

    @Test("Independent instances don't share state")
    func independentInstances() {
        let tracker1 = CommitDockAnalyticsTracker(
            clock: { Date() },
            transitionCooldown: 0
        )
        let tracker2 = CommitDockAnalyticsTracker(
            clock: { Date() },
            transitionCooldown: 0
        )

        tracker1.logPhaseChange(to: .collapsed)
        tracker1.logPhaseChange(to: .collapsed)

        #expect(tracker1.sessionCollapseCount == 2)
        #expect(tracker2.sessionCollapseCount == 0)
    }

    // MARK: - Session lifecycle: reset()

    @Test("reset() clears counters and cooldown")
    func resetClearsState() {
        let fixedDate = Date()
        var currentTime = fixedDate

        let tracker = CommitDockAnalyticsTracker(
            clock: { currentTime },
            transitionCooldown: 10.0 // high cooldown
        )

        tracker.logPhaseChange(to: .collapsed)
        #expect(tracker.sessionCollapseCount == 1)

        // Reset clears everything
        tracker.reset()
        #expect(tracker.sessionCollapseCount == 0)
        #expect(tracker.sessionExpandCount == 0)

        // Should be able to log immediately after reset (cooldown cleared)
        currentTime = fixedDate.addingTimeInterval(0.1) // still within original cooldown
        let logged = tracker.logPhaseChange(to: .expanded)
        #expect(logged == true)
        #expect(tracker.sessionExpandCount == 1)
    }

    // MARK: - Alternating transitions

    @Test("Alternating transitions count correctly")
    func alternatingTransitions() {
        var time = Date()

        let tracker = CommitDockAnalyticsTracker(
            clock: { time },
            transitionCooldown: 0
        )

        // collapse → expand → collapse → expand
        tracker.logPhaseChange(to: .collapsed)
        time = time.addingTimeInterval(0.01)
        tracker.logPhaseChange(to: .expanded)
        time = time.addingTimeInterval(0.01)
        tracker.logPhaseChange(to: .collapsed)
        time = time.addingTimeInterval(0.01)
        tracker.logPhaseChange(to: .expanded)

        #expect(tracker.sessionCollapseCount == 2)
        #expect(tracker.sessionExpandCount == 2)
    }
}
