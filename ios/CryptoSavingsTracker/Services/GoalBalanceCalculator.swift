//
//  GoalBalanceCalculator.swift
//  CryptoSavingsTracker
//

import Foundation

/// Result of calculating a goal's current balance total from its asset allocations.
struct GoalBalanceCalculation: Sendable {
    let total: Double
    let hasConversionError: Bool
}

/// Pure domain utility that calculates a goal's current balance total by summing its
/// allocated asset balances and converting them into the goal's currency.
///
/// This calculation previously lived only inside `GoalViewModel`, which forced any
/// non-UI caller (like `MonthlyPlanningService`) to instantiate and refresh a
/// `@MainActor` view model just to read a number. `GoalBalanceCalculator` has no
/// main-actor or presentation-layer dependency, so both `GoalViewModel` and
/// `MonthlyPlanningService` can share the same allocation/currency-conversion logic
/// without one depending on the other.
struct GoalBalanceCalculator {
    private let tatumService: TatumServiceProtocol
    private let exchangeRateService: ExchangeRateServiceProtocol

    init(tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
        self.tatumService = tatumService
        self.exchangeRateService = exchangeRateService
    }

    /// Value-type snapshot of the data an allocation's contribution needs, captured up front
    /// (on the caller's actor) so the actual balance/rate fetching can safely run concurrently
    /// without sharing non-`Sendable` SwiftData model instances across tasks.
    fileprivate struct AllocationSnapshot: Sendable {
        let assetCurrency: String
        let manualBalance: Double
        let address: String?
        let chainId: String?
        let amountValue: Double
    }

    /// Calculate the current total balance allocated to `goal`, converting each asset's
    /// balance into the goal's currency. Also reports whether any balance refresh or
    /// currency conversion failed along the way.
    ///
    /// Each allocation's balance refresh and currency conversion are independent of the
    /// others, so they are fetched concurrently via a `TaskGroup` rather than sequentially,
    /// which matters when a goal has many asset allocations.
    func calculateCurrentTotal(for goal: Goal) async -> GoalBalanceCalculation {
        let goalCurrency = goal.currency
        let snapshots: [AllocationSnapshot] = (goal.allocations ?? []).compactMap { allocation in
            guard let asset = allocation.asset else { return nil }
            return AllocationSnapshot(
                assetCurrency: asset.currency,
                manualBalance: asset.manualBalance,
                address: asset.address,
                chainId: asset.chainId,
                amountValue: allocation.amountValue
            )
        }

        guard !snapshots.isEmpty else {
            return GoalBalanceCalculation(total: 0, hasConversionError: false)
        }

        let contributions: [(total: Double, hasConversionError: Bool)] = await withTaskGroup(of: (total: Double, hasConversionError: Bool).self) { group in
            for snapshot in snapshots {
                group.addTask {
                    await contribution(for: snapshot, goalCurrency: goalCurrency, tatumService: tatumService, exchangeRateService: exchangeRateService)
                }
            }

            var results: [(total: Double, hasConversionError: Bool)] = []
            results.reserveCapacity(snapshots.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        let total = contributions.reduce(0) { $0 + $1.total }
        let hasConversionError = contributions.contains { $0.hasConversionError }
        return GoalBalanceCalculation(total: total, hasConversionError: hasConversionError)
    }
}

/// Computes a single allocation's contribution to the goal total. Kept as a free function
/// (rather than an instance method) so it can be safely passed to `TaskGroup.addTask`
/// without capturing the non-`Sendable` `GoalBalanceCalculator` instance.
private func contribution(
    for snapshot: GoalBalanceCalculator.AllocationSnapshot,
    goalCurrency: String,
    tatumService: TatumServiceProtocol,
    exchangeRateService: ExchangeRateServiceProtocol
) async -> (total: Double, hasConversionError: Bool) {
    let balanceResult = await currentAmount(
        manualBalance: snapshot.manualBalance,
        address: snapshot.address,
        chainId: snapshot.chainId,
        currency: snapshot.assetCurrency,
        tatumService: tatumService
    )
    var hasConversionError = balanceResult.error != nil

    let assetBalance = balanceResult.amount
    let allocatedPortion = min(max(0, snapshot.amountValue), assetBalance)
    guard allocatedPortion > 0 else { return (0, hasConversionError) }

    if snapshot.assetCurrency.uppercased() == goalCurrency.uppercased() {
        return (allocatedPortion, hasConversionError)
    } else {
        do {
            let rate = try await exchangeRateService.fetchRate(from: snapshot.assetCurrency, to: goalCurrency)
            return (allocatedPortion * rate, hasConversionError)
        } catch {
            AppLog.error("Exchange rate failed for \(snapshot.assetCurrency) → \(goalCurrency). Skipping value to avoid wrong totals. Error: \(error.localizedDescription)", category: .exchangeRate)
            hasConversionError = true
            return (0, hasConversionError)
        }
    }
}

private func currentAmount(
    manualBalance: Double,
    address: String?,
    chainId: String?,
    currency: String,
    tatumService: TatumServiceProtocol
) async -> (amount: Double, error: Error?) {
    var total = manualBalance

    guard let address, let chainId, !address.isEmpty else {
        return (total, nil)
    }

    do {
        let onChainBalance = try await tatumService.fetchBalance(
            chainId: chainId,
            address: address,
            symbol: currency,
            forceRefresh: false
        )
        total += onChainBalance
        return (total, nil)
    } catch {
        AppLog.warning("Goal balance refresh kept manual balance after on-chain fetch failed: \(error.localizedDescription)", category: .balanceService)
        return (total, error)
    }
}
