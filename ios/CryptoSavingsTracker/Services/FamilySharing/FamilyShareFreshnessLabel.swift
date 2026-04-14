import Foundation

final class FamilyShareClockSkewTelemetryDeduper: @unchecked Sendable {
    nonisolated static let shared = FamilyShareClockSkewTelemetryDeduper()

    private let lock = NSLock()
    private nonisolated(unsafe) var emittedKeys: Set<String> = []

    nonisolated func shouldEmit(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return emittedKeys.insert(key).inserted
    }

    nonisolated func reset() {
        lock.lock()
        emittedKeys.removeAll()
        lock.unlock()
    }
}

/// Canonical freshness string model for shared-goals surfaces.
///
/// Instantiated per namespace. Produces dependency-aware copy:
/// - Publish-governed: "Shared X ago"
/// - Rate-governed: "Rates are X old — values may have changed"
///
/// Shared between list header and detail Freshness card.
struct FamilyShareFreshnessLabel: Sendable {

    let tier: FamilyShareFreshnessTier
    let governing: FamilyShareFreshnessGoverningDependency
    let substate: FamilyShareFreshnessSubstate
    let publishedAt: Date
    let rateSnapshotAt: Date?
    let lastChecked: Date?
    let clockSkewDiagnostics: FamilyShareFreshnessPolicy.ClockSkewDiagnostics

    private let clock: FamilyShareClock

    nonisolated init(
        publishedAt: Date,
        rateSnapshotAt: Date?,
        substate: FamilyShareFreshnessSubstate = .idle,
        lastChecked: Date? = nil,
        clock: FamilyShareClock = SystemClock(),
        tierOverride: FamilyShareFreshnessTier? = nil,
        governingOverride: FamilyShareFreshnessGoverningDependency? = nil,
        namespaceKey: String? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker()
    ) {
        self.publishedAt = publishedAt
        self.rateSnapshotAt = rateSnapshotAt
        self.substate = substate
        self.lastChecked = lastChecked
        self.clock = clock

        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let result = policy.evaluate(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        self.tier = tierOverride ?? result.tier
        self.governing = governingOverride ?? result.governing
        self.clockSkewDiagnostics = policy.clockSkewDiagnostics(
            publishedAt: publishedAt,
            rateSnapshotAt: rateSnapshotAt
        )

        if let namespaceKey, clockSkewDiagnostics.hasSkew {
            if let publishSkewSeconds = clockSkewDiagnostics.publishSkewSeconds {
                let dedupeKey = "\(namespaceKey)|publish"
                if FamilyShareClockSkewTelemetryDeduper.shared.shouldEmit(key: dedupeKey) {
                    telemetry.track(
                        .clockSkewDetected,
                        payload: [
                            "namespace": namespaceKey,
                            "source": "publish",
                            "skewSeconds": "\(Int(publishSkewSeconds.rounded()))"
                        ]
                    )
                }
            }

            if let rateSkewSeconds = clockSkewDiagnostics.rateSkewSeconds {
                let dedupeKey = "\(namespaceKey)|rate"
                if FamilyShareClockSkewTelemetryDeduper.shared.shouldEmit(key: dedupeKey) {
                    telemetry.track(
                        .clockSkewDetected,
                        payload: [
                            "namespace": namespaceKey,
                            "source": "rate",
                            "skewSeconds": "\(Int(rateSkewSeconds.rounded()))"
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Primary Message

    /// The primary freshness message for list headers.
    var primaryMessage: String {
        // Substates that override the primary message
        switch substate {
        case .checking:
            return "Checking for updates..."
        case .refreshFailed:
            return "Couldn't refresh — showing last shared update"
        default:
            break
        }

        // Tier-based message split by governing dependency
        switch (tier, governing) {
        // Active
        case (.active, _):
            return "Shared \(relativeTime(publishedAt))"

        // Recently Stale
        case (.recentlyStale, .publishAge):
            return "Shared \(relativeTime(publishedAt))"
        case (.recentlyStale, .rateAge):
            return "Rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old"

        // Stale
        case (.stale, .publishAge):
            return "Last shared \(relativeTime(publishedAt)) — values may have changed"
        case (.stale, .rateAge):
            return "Rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old — values may have changed"

        // Materially Outdated
        case (.materiallyOutdated, .publishAge):
            return "Last shared \(relativeTime(publishedAt)) — values may have changed significantly"
        case (.materiallyOutdated, .rateAge):
            return "Rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old — values may have changed significantly"

        // Error states
        case (.temporarilyUnavailable, _):
            return "Shared goals temporarily unavailable"
        case (.removedOrNoLongerShared, _):
            return "This shared goal set is no longer available"
        }
    }

    /// Secondary line for `checkedNoNewData` substate.
    var secondaryMessage: String? {
        guard substate == .checkedNoNewData else { return nil }
        return "Checked just now — no newer update yet"
    }

    // MARK: - VoiceOver

    /// VoiceOver announcement text.
    var voiceOverMessage: String {
        switch substate {
        case .checking:
            return "Checking for updates"
        case .refreshFailed:
            return "Couldn't refresh. Showing last shared update."
        default:
            break
        }

        switch (tier, governing) {
        case (.active, _):
            return "Shared \(relativeTime(publishedAt))"
        case (.recentlyStale, .publishAge):
            return "Shared \(relativeTime(publishedAt))"
        case (.recentlyStale, .rateAge):
            return "Rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old"
        case (.stale, .publishAge):
            return "Warning: last shared \(relativeTime(publishedAt)), values may have changed"
        case (.stale, .rateAge):
            return "Warning: rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old, values may have changed"
        case (.materiallyOutdated, .publishAge):
            return "Warning: last shared \(relativeTime(publishedAt)), values may have changed significantly"
        case (.materiallyOutdated, .rateAge):
            return "Warning: rates are \(relativeTime(rateSnapshotAt ?? publishedAt)) old, values may have changed significantly"
        case (.temporarilyUnavailable, _):
            return "Shared goals temporarily unavailable. Activate Retry to check again."
        case (.removedOrNoLongerShared, _):
            return "This shared goal set is no longer available."
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: clock.now())
    }
}
