//
//  CommitDockAnalytics.swift
//  CryptoSavingsTracker
//
//  Lightweight telemetry for Commit Dock scroll-collapse behaviour.
//  Logs through AppLogger; wire to a real backend when one is adopted.
//

import Foundation

enum CommitDockAnalytics {

    enum Event: String {
        case impression       = "commit_dock_impression"
        case collapsed        = "commit_dock_collapsed"
        case expanded         = "commit_dock_expanded"
        case fabTap           = "commit_dock_fab_tap"
        case fullButtonTap    = "commit_dock_full_button_tap"
    }

    static func log(_ event: Event, properties: [String: String] = [:]) {
        let props = properties.isEmpty
            ? ""
            : " " + properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        AppLog.info("[\(event.rawValue)]\(props)", category: .monthlyPlanning)
    }
}

// MARK: - Session-scoped analytics tracker

@MainActor
final class CommitDockAnalyticsTracker {

    /// Injectable clock for deterministic testing.
    private let clock: () -> Date

    /// Minimum interval between successive phase-change logs.
    let transitionCooldown: TimeInterval

    /// Running counts for the current session.
    private(set) var sessionCollapseCount: Int = 0
    private(set) var sessionExpandCount: Int = 0

    /// Timestamp of last logged phase change (nil = never).
    private var lastLogTimestamp: Date?

    init(clock: @escaping () -> Date = { Date() }, transitionCooldown: TimeInterval = 1.0) {
        self.clock = clock
        self.transitionCooldown = transitionCooldown
    }

    /// Log a dock phase transition, respecting the cooldown guard.
    /// Returns `true` if the event was actually logged, `false` if suppressed.
    @discardableResult
    func logPhaseChange(to phase: DockPhase) -> Bool {
        let now = clock()
        if let last = lastLogTimestamp, now.timeIntervalSince(last) < transitionCooldown {
            return false
        }

        lastLogTimestamp = now

        switch phase {
        case .collapsed:
            sessionCollapseCount += 1
            CommitDockAnalytics.log(.collapsed, properties: [
                "session_collapse_count": "\(sessionCollapseCount)"
            ])
        case .expanded:
            sessionExpandCount += 1
            CommitDockAnalytics.log(.expanded, properties: [
                "session_expand_count": "\(sessionExpandCount)"
            ])
        }
        return true
    }

    /// Reset counters and cooldown (e.g. on view appear).
    func reset() {
        sessionCollapseCount = 0
        sessionExpandCount = 0
        lastLogTimestamp = nil
    }
}
