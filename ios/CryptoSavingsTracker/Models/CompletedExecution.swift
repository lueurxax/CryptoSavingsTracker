//
//  CompletedExecution.swift
//  CryptoSavingsTracker
//
//  Immutable snapshot metadata for completed executions.
//

import SwiftData
import Foundation

struct CompletedExecutionContributionSnapshot: Codable, Sendable {
    let timestamp: Date
    let source: ContributionSource
    let assetId: UUID
    let assetCurrency: String
    let goalId: UUID
    let goalCurrency: String
    /// Delta in the asset currency (e.g., 0.01 BTC).
    let assetAmount: Double
    /// Value in goal currency using `exchangeRateUsed`.
    let amountInGoalCurrency: Double
    let exchangeRateUsed: Double
}

@Model
final class CompletedExecution {
    @Attribute(.unique) var id: UUID
    var monthLabel: String
    var completedAt: Date

    // SwiftData doesn't reliably persist [String: Double] dictionaries, so store encoded Data.
    var exchangeRatesSnapshotData: Data?
    // Snapshot of goals and contributions at completion for immutability.
    var goalSnapshotsData: Data?
    var contributionSnapshotsData: Data?

    init(
        monthLabel: String,
        completedAt: Date,
        exchangeRatesSnapshot: [String: Double],
        goalSnapshots: [ExecutionGoalSnapshot],
        contributionSnapshots: [CompletedExecutionContributionSnapshot]
    ) {
        self.id = UUID()
        self.monthLabel = monthLabel
        self.completedAt = completedAt
        self.exchangeRatesSnapshotData = (try? JSONEncoder().encode(exchangeRatesSnapshot)) ?? Data()
        self.goalSnapshotsData = (try? JSONEncoder().encode(goalSnapshots)) ?? Data()
        self.contributionSnapshotsData = (try? JSONEncoder().encode(contributionSnapshots)) ?? Data()
    }

    var exchangeRatesSnapshot: [String: Double] {
        let data = exchangeRatesSnapshotData ?? Data()
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    var goalSnapshots: [ExecutionGoalSnapshot] {
        let data = goalSnapshotsData ?? Data()
        return (try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: data)) ?? []
    }

    var contributionSnapshots: [CompletedExecutionContributionSnapshot] {
        let data = contributionSnapshotsData ?? Data()
        return (try? JSONDecoder().decode([CompletedExecutionContributionSnapshot].self, from: data)) ?? []
    }

    var contributedTotalsByGoalId: [UUID: Double] {
        contributionSnapshots.reduce(into: [:]) { partial, snapshot in
            partial[snapshot.goalId, default: 0] += snapshot.amountInGoalCurrency
        }
    }
}
