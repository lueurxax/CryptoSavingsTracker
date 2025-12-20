//
//  ExecutionProgressCalculator.swift
//  CryptoSavingsTracker
//
//  Derives execution contributions from transactions + allocation history timestamps.
//

import Foundation
import SwiftData

@MainActor
final class ExecutionProgressCalculator {
    struct DerivedEvent {
        let timestamp: Date
        let source: ContributionSource
        let assetId: UUID
        let assetCurrency: String
        let goalId: UUID
        let goalCurrency: String
        /// Delta of the funded amount for this goal-asset pair in the asset currency.
        let assetDelta: Double
    }

    private let modelContext: ModelContext
    private let exchangeRateService: ExchangeRateServiceProtocol

    init(modelContext: ModelContext, exchangeRateService: ExchangeRateServiceProtocol) {
        self.modelContext = modelContext
        self.exchangeRateService = exchangeRateService
    }

    func derivedEvents(for record: MonthlyExecutionRecord, end: Date) throws -> [DerivedEvent] {
        guard let startedAt = record.startedAt else { return [] }

        let trackedGoalIds = Set(record.goalIds)
        guard !trackedGoalIds.isEmpty else { return [] }

        let goals = try modelContext.fetch(FetchDescriptor<Goal>()).filter { trackedGoalIds.contains($0.id) }
        let goalCurrencyById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.currency) })

        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let allHistories = (try? modelContext.fetch(FetchDescriptor<AllocationHistory>())) ?? []

        // Index histories by asset id for faster access.
        var historiesByAssetId: [UUID: [AllocationHistory]] = [:]
        historiesByAssetId.reserveCapacity(assets.count)
        for history in allHistories {
            guard let assetId = history.assetId,
                  let goalId = history.goalId,
                  trackedGoalIds.contains(goalId),
                  history.timestamp <= end
            else { continue }
            historiesByAssetId[assetId, default: []].append(history)
        }

        var derived: [DerivedEvent] = []
        derived.reserveCapacity(64)

        let epsilon = 0.0000001

        for asset in assets {
            // Only process assets relevant to this execution (allocated to tracked goals OR has relevant history).
            let hasTrackedAllocation = asset.allocations.contains(where: { allocation in
                guard let goalId = allocation.goal?.id else { return false }
                return trackedGoalIds.contains(goalId)
            })
            guard hasTrackedAllocation || historiesByAssetId[asset.id] != nil else { continue }

            let histories = historiesByAssetId[asset.id] ?? []

            // Compute balance at start by reversing from the best-known balance at `end`.
            // This keeps the calculator usable even when we don't have a full pre-start transaction ledger
            // (e.g., on-chain assets where we only persist a rolling window of chain history).
            let endBalance = max(0, asset.currentAmount)
            let deltaDuringWindow = asset.transactions
                .filter { $0.date >= startedAt && $0.date <= end }
                .reduce(0.0) { $0 + $1.amount }
            let startBalance = max(0, endBalance - deltaDuringWindow)

            // Determine targets at start (latest history <= startedAt).
            var targetsByGoalId: [UUID: Double] = [:]
            targetsByGoalId.reserveCapacity(trackedGoalIds.count)

            for goalId in trackedGoalIds {
                // Latest history <= startedAt for this pair.
                if let latest = histories
                    .filter({ $0.goalId == goalId && $0.timestamp <= startedAt })
                    .max(by: { lhs, rhs in
                        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                        return lhs.effectiveCreatedAt < rhs.effectiveCreatedAt
                    }) {
                    targetsByGoalId[goalId] = max(0, latest.amount)
                }
            }

            // Defensive fallback for dedicated assets:
            // If an asset is allocated to exactly one tracked goal but lacks a baseline history at/Before `startedAt`,
            // use the current allocation target as the starting target. This prevents "missing contributions"
            // when AllocationHistory writes are absent (e.g., older data or edge UI flows), while still avoiding
            // guessing for shared assets.
            let trackedAllocations = asset.allocations.compactMap { allocation -> (goalId: UUID, amount: Double)? in
                guard let goalId = allocation.goal?.id, trackedGoalIds.contains(goalId) else { return nil }
                return (goalId, max(0, allocation.amountValue))
            }
            if trackedAllocations.count == 1 {
                let only = trackedAllocations[0]
                if targetsByGoalId[only.goalId] == nil {
                    targetsByGoalId[only.goalId] = only.amount
                }
            }

            var balance = startBalance
            var fundedByGoalId = fundedAmounts(
                balance: balance,
                targetsByGoalId: targetsByGoalId
            )

            // Group transactions and allocation updates by timestamp within the window.
            var txAmountByTimestamp: [Date: Double] = [:]
            for tx in asset.transactions where tx.date >= startedAt && tx.date <= end {
                txAmountByTimestamp[tx.date, default: 0] += tx.amount
            }

            var allocationUpdatesByTimestamp: [Date: [UUID: (amount: Double, createdAt: Date)]] = [:]
            for history in histories where history.timestamp > startedAt && history.timestamp <= end {
                guard let goalId = history.goalId else { continue }
                let newEntry = (amount: max(0, history.amount), createdAt: history.effectiveCreatedAt)
                if let existing = allocationUpdatesByTimestamp[history.timestamp]?[goalId] {
                    if newEntry.createdAt > existing.createdAt {
                        allocationUpdatesByTimestamp[history.timestamp]?[goalId] = newEntry
                    }
                } else {
                    allocationUpdatesByTimestamp[history.timestamp, default: [:]][goalId] = newEntry
                }
            }

            let allTimestamps = Set(txAmountByTimestamp.keys).union(allocationUpdatesByTimestamp.keys)
            let timestamps = allTimestamps.sorted()

            for timestamp in timestamps {
                if let updates = allocationUpdatesByTimestamp[timestamp], !updates.isEmpty {
                    for (goalId, entry) in updates {
                        targetsByGoalId[goalId] = max(0, entry.amount)
                    }
                    let newFunded = fundedAmounts(
                        balance: balance,
                        targetsByGoalId: targetsByGoalId
                    )
                    let deltas = deltasByGoalId(from: fundedByGoalId, to: newFunded, epsilon: epsilon)
                    appendEvents(
                        deltasByGoalId: deltas,
                        timestamp: timestamp,
                        source: .assetReallocation,
                        asset: asset,
                        goalCurrencyById: goalCurrencyById,
                        into: &derived
                    )
                    fundedByGoalId = newFunded
                }

                if let txDelta = txAmountByTimestamp[timestamp], abs(txDelta) > epsilon {
                    balance += txDelta
                    let newFunded = fundedAmounts(
                        balance: balance,
                        targetsByGoalId: targetsByGoalId
                    )
                    let deltas = deltasByGoalId(from: fundedByGoalId, to: newFunded, epsilon: epsilon)
                    appendEvents(
                        deltasByGoalId: deltas,
                        timestamp: timestamp,
                        source: .manualDeposit,
                        asset: asset,
                        goalCurrencyById: goalCurrencyById,
                        into: &derived
                    )
                    fundedByGoalId = newFunded
                }
            }
        }

        return derived.sorted(by: { $0.timestamp < $1.timestamp })
    }

    func contributionTotalsInGoalCurrency(for record: MonthlyExecutionRecord, end: Date) async throws -> [UUID: Double] {
        let events = try derivedEvents(for: record, end: end)
        guard !events.isEmpty else { return [:] }

        // Net deltas per (goal, assetCurrency) in asset currency.
        var netByGoalByAssetCurrency: [UUID: [String: Double]] = [:]
        var goalCurrencyByGoalId: [UUID: String] = [:]
        for event in events {
            netByGoalByAssetCurrency[event.goalId, default: [:]][event.assetCurrency, default: 0] += event.assetDelta
            goalCurrencyByGoalId[event.goalId] = event.goalCurrency
        }

        var totals: [UUID: Double] = [:]
        totals.reserveCapacity(netByGoalByAssetCurrency.count)

        var rateCache: [String: Double] = [:]

        for (goalId, byAssetCurrency) in netByGoalByAssetCurrency {
            guard let goalCurrency = goalCurrencyByGoalId[goalId] else { continue }
            var total = 0.0

            for (assetCurrency, assetDelta) in byAssetCurrency {
                guard abs(assetDelta) > 0.0000001 else { continue }
                if assetCurrency.uppercased() == goalCurrency.uppercased() {
                    total += assetDelta
                    continue
                }
                let key = "\(assetCurrency.uppercased())->\(goalCurrency.uppercased())"
                let rate: Double
                if let cached = rateCache[key] {
                    rate = cached
                } else {
                    do {
                        rate = try await exchangeRateService.fetchRate(from: assetCurrency, to: goalCurrency)
                        rateCache[key] = rate
                    } catch {
                        AppLog.warning("Exchange rate failed for \(key) during execution calculation: \(error)", category: .exchangeRate)
                        continue
                    }
                }

                total += assetDelta * rate
            }

            totals[goalId] = total
        }

        return totals
    }

    private func fundedAmounts(
        balance: Double,
        targetsByGoalId: [UUID: Double]
    ) -> [UUID: Double] {
        guard balance > 0 else {
            return targetsByGoalId.reduce(into: [:]) { partial, item in
                partial[item.key] = 0
            }
        }

        let totalTargets = targetsByGoalId.values.reduce(0, +)
        guard totalTargets > 0 else {
            return [:]
        }

        if balance >= totalTargets {
            return targetsByGoalId
        }

        return targetsByGoalId.reduce(into: [:]) { partial, item in
            let ratio = item.value / totalTargets
            partial[item.key] = balance * ratio
        }
    }

    private func deltasByGoalId(from previous: [UUID: Double], to next: [UUID: Double], epsilon: Double) -> [UUID: Double] {
        let keys = Set(previous.keys).union(next.keys)
        var deltas: [UUID: Double] = [:]
        deltas.reserveCapacity(keys.count)
        for key in keys {
            let old = previous[key] ?? 0
            let new = next[key] ?? 0
            let delta = new - old
            if abs(delta) > epsilon {
                deltas[key] = delta
            }
        }
        return deltas
    }

    private func appendEvents(
        deltasByGoalId: [UUID: Double],
        timestamp: Date,
        source: ContributionSource,
        asset: Asset,
        goalCurrencyById: [UUID: String],
        into derived: inout [DerivedEvent]
    ) {
        for (goalId, delta) in deltasByGoalId {
            guard let goalCurrency = goalCurrencyById[goalId] else { continue }
            derived.append(
                DerivedEvent(
                    timestamp: timestamp,
                    source: source,
                    assetId: asset.id,
                    assetCurrency: asset.currency,
                    goalId: goalId,
                    goalCurrency: goalCurrency,
                    assetDelta: delta
                )
            )
        }
    }
}
