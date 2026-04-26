import Foundation

// MARK: - Projection Dirty Reason

/// Reason why a shared projection needs to be republished.
enum FamilyShareProjectionDirtyReason: Sendable {
    case goalMutation(goalIDs: Set<UUID>)
    case assetMutation(goalIDs: Set<UUID>)
    case transactionMutation(goalIDs: Set<UUID>)
    case rateDrift(goalIDs: Set<UUID>)
    case importOrRepair
    case manualRefresh
    case participantChange

    /// Union of all affected goal IDs from this reason.
    nonisolated var affectedGoalIDs: Set<UUID> {
        switch self {
        case .goalMutation(let ids), .assetMutation(let ids),
             .transactionMutation(let ids), .rateDrift(let ids):
            return ids
        case .importOrRepair, .manualRefresh, .participantChange:
            return []
        }
    }

    /// Mutations scoped to zero goals do not carry enough information to rebuild a useful projection.
    /// Unscoped reasons like manual refresh and participant changes remain valid.
    nonisolated var isEmptyScopedMutation: Bool {
        switch self {
        case .goalMutation(let ids), .assetMutation(let ids),
             .transactionMutation(let ids), .rateDrift(let ids):
            return ids.isEmpty
        case .importOrRepair, .manualRefresh, .participantChange:
            return false
        }
    }
}

// MARK: - Freshness Tier

/// Internal freshness state evaluated per namespace from composite effective age.
enum FamilyShareFreshnessTier: String, Sendable, Codable, CaseIterable, Equatable {
    case active
    case recentlyStale
    case stale
    case materiallyOutdated
    case temporarilyUnavailable
    case removedOrNoLongerShared
}

// MARK: - Freshness Substate

/// Transient UI state overlaying the freshness tier.
enum FamilyShareFreshnessSubstate: String, Sendable, Codable, CaseIterable, Equatable {
    case idle
    case checking
    case refreshFailed
    case checkedNoNewData
    case refreshSucceeded
    case cooldown
}

// MARK: - Governing Dependency

/// Which timestamp governs the composite freshness tier.
enum FamilyShareFreshnessGoverningDependency: Sendable, Equatable {
    case publishAge
    case rateAge

    nonisolated static func == (
        lhs: FamilyShareFreshnessGoverningDependency,
        rhs: FamilyShareFreshnessGoverningDependency
    ) -> Bool {
        switch (lhs, rhs) {
        case (.publishAge, .publishAge), (.rateAge, .rateAge):
            return true
        default:
            return false
        }
    }
}

// MARK: - Refresh Result

/// Outcome of an invitee refresh attempt.
enum FamilyShareRefreshResult: Sendable {
    case success(updatedProjection: Bool)
    case noNewData
    case failure(Error)
}

// MARK: - Last Published Snapshot

/// Lightweight local cache of the last published projection state per namespace.
struct FamilyShareLastPublishedSnapshot: Sendable, Codable {
    let namespaceKey: String
    let goalAmounts: [UUID: Decimal]
    let contentHash: String?
    let publishedAt: Date
    let rateSnapshotTimestamp: Date?
    let projectionServerTimestamp: Date?
}

// MARK: - Goal Progress Input (Sendable value types for GoalProgressCalculator)

/// Pure input for goal progress calculation. No SwiftData types.
struct GoalProgressInput: Sendable {
    let goalID: UUID
    let currency: String
    let targetAmount: Decimal
    let allocations: [AllocationInput]
}

/// Pure input for a single allocation.
struct AllocationInput: Sendable {
    let assetCurrency: String
    let allocatedAmount: Decimal
}

/// Immutable rate snapshot for deterministic calculation.
struct RateSnapshot: Sendable {
    let rates: [String: Decimal]
    let timestamp: Date

    nonisolated func rate(from: String, to: String) -> Decimal? {
        rates[CurrencyPair.canonicalKey(from: from, to: to)]
    }
}

/// Result of a goal progress calculation.
struct GoalProgressResult: Sendable {
    let currentAmount: Decimal
    let progressRatio: Double
}
