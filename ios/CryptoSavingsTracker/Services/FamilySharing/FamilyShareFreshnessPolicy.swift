import Foundation

/// Defines SLA thresholds, cooldowns, debounce windows, and composite staleness
/// boundaries for the shared-goals freshness pipeline.
///
/// All time-based computations use an injected `FamilyShareClock` for testability.
struct FamilyShareFreshnessPolicy: Sendable {
    struct ClockSkewDiagnostics: Sendable, Equatable {
        let publishSkewSeconds: TimeInterval?
        let rateSkewSeconds: TimeInterval?

        var hasSkew: Bool {
            publishSkewSeconds != nil || rateSkewSeconds != nil
        }
    }

    // MARK: - Thresholds

    /// Maximum age (seconds) for `active` tier.
    static let activeThreshold: TimeInterval = 30 * 60          // 30 minutes

    /// Maximum age (seconds) for `recentlyStale` tier.
    static let recentlyStaleThreshold: TimeInterval = 4 * 3600  // 4 hours

    /// Maximum age (seconds) for `stale` tier. Beyond this is `materiallyOutdated`.
    static let staleThreshold: TimeInterval = 24 * 3600         // 24 hours

    // MARK: - Cooldowns and Debounce

    /// Minimum seconds between invitee refresh attempts per namespace.
    static let refreshCooldown: TimeInterval = 30

    /// Debounce window for mutation-triggered dirty events.
    static let mutationDebounce: TimeInterval = 2.0

    /// Debounce window for rate-drift dirty events.
    static let rateDriftDebounce: TimeInterval = 5.0

    /// Exponential backoff schedule for repeated publish failures (seconds).
    static let backoffSchedule: [TimeInterval] = [5, 15, 60, 300]

    /// Maximum time to wait for CloudKit import fence before suppressing publish.
    static let importFenceTimeout: TimeInterval = 10.0

    /// Auto-dismiss interval for `refreshFailed` substate.
    static let refreshFailedAutoDismiss: TimeInterval = 60.0

    /// Auto-dismiss interval for `checkedNoNewData` substate.
    static let checkedNoNewDataAutoDismiss: TimeInterval = 120.0

    /// Clock-skew tolerance before emitting telemetry (seconds into the future).
    static let clockSkewTolerance: TimeInterval = 60.0

    /// Rate cache TTL — the interval at which `FamilyShareForegroundRateRefreshDriver` ticks.
    static let rateCacheTTL: TimeInterval = 300.0  // 5 minutes

    /// Periodic guard interval (safety net for missed rate refreshes).
    static let periodicGuardInterval: TimeInterval = 15 * 60    // 15 minutes

    // MARK: - Clock

    private let clock: FamilyShareClock

    init(clock: FamilyShareClock = SystemClock()) {
        self.clock = clock
    }

    // MARK: - Tier Resolution

    /// Compute the composite effective age from publish and rate ages.
    ///
    /// Effective age = `max(publishAge, rateAge)`. This ensures stale rates
    /// escalate the freshness tier even when the projection was recently published.
    func effectiveAge(publishedAt: Date, rateSnapshotAt: Date?) -> TimeInterval {
        let publishAge = clampedAge(for: publishedAt).age
        let rateAge = rateSnapshotAt.map { clampedAge(for: $0).age } ?? publishAge
        return max(publishAge, rateAge)
    }

    /// Determine the freshness tier from the composite effective age.
    func tier(forEffectiveAge age: TimeInterval) -> FamilyShareFreshnessTier {
        switch age {
        case ..<Self.activeThreshold:
            return .active
        case ..<Self.recentlyStaleThreshold:
            return .recentlyStale
        case ..<Self.staleThreshold:
            return .stale
        default:
            return .materiallyOutdated
        }
    }

    /// Determine which dependency governs the composite freshness.
    func governingDependency(publishedAt: Date, rateSnapshotAt: Date?) -> FamilyShareFreshnessGoverningDependency {
        let publishAge = clampedAge(for: publishedAt).age
        let rateAge = rateSnapshotAt.map { clampedAge(for: $0).age } ?? publishAge
        return rateAge > publishAge ? .rateAge : .publishAge
    }

    /// Compute freshness tier and governing dependency in one call.
    func evaluate(publishedAt: Date, rateSnapshotAt: Date?) -> (tier: FamilyShareFreshnessTier, governing: FamilyShareFreshnessGoverningDependency) {
        let age = effectiveAge(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        let tier = tier(forEffectiveAge: age)
        let governing = governingDependency(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        return (tier, governing)
    }

    // MARK: - Clock Skew

    /// Check if a timestamp is in the future beyond the tolerance window.
    /// Returns the clamped age (zero if future) and whether skew was detected.
    func clampedAge(for timestamp: Date) -> (age: TimeInterval, skewDetected: Bool) {
        let now = clock.now()
        let age = now.timeIntervalSince(timestamp)
        if age < -Self.clockSkewTolerance {
            // Timestamp is in the future beyond tolerance
            return (0, true)
        } else if age < 0 {
            // Within tolerance, treat as zero-age
            return (0, false)
        }
        return (age, false)
    }

    func clockSkewDiagnostics(publishedAt: Date, rateSnapshotAt: Date?) -> ClockSkewDiagnostics {
        let now = clock.now()
        let publishDelta = now.timeIntervalSince(publishedAt)
        let publishSkewSeconds = publishDelta < -Self.clockSkewTolerance ? abs(publishDelta) : nil

        let rateSkewSeconds: TimeInterval?
        if let rateSnapshotAt {
            let rateDelta = now.timeIntervalSince(rateSnapshotAt)
            rateSkewSeconds = rateDelta < -Self.clockSkewTolerance ? abs(rateDelta) : nil
        } else {
            rateSkewSeconds = nil
        }

        return ClockSkewDiagnostics(
            publishSkewSeconds: publishSkewSeconds,
            rateSkewSeconds: rateSkewSeconds
        )
    }

    // MARK: - Backoff

    /// Get the backoff delay for a given failure count.
    func backoffDelay(forFailureCount count: Int) -> TimeInterval {
        let index = min(count, Self.backoffSchedule.count - 1)
        return Self.backoffSchedule[max(0, index)]
    }
}
