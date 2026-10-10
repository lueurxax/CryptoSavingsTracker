//
//  GoalBalanceCalculator.swift
//  CryptoSavingsTracker
//

import Foundation

/// Result of calculating a goal's current balance total from its asset allocations.
struct GoalBalanceCalculation: Sendable {
    let total: Double
    let hasConversionError: Bool
    let financialInputEvidence: GoalFinancialInputEvidence

    var currentTotalResult: GoalCurrentTotalResult {
        GoalCurrentTotalResult(
            total: total,
            error: hasConversionError ? UserFacingError(
                title: "Balances Not Refreshed",
                message: "Some balances could not be updated. Existing values are still shown.",
                recoverySuggestion: "Check your connection and retry.",
                isRetryable: true,
                category: .network
            ) : nil,
            financialInputEvidence: financialInputEvidence
        )
    }
}

/// Pure domain utility that calculates a goal's current balance total by summing its
/// allocated asset balances and converting them into the goal's currency.
///
/// This calculation previously lived only inside `GoalViewModel`, which forced any
/// non-UI caller (like `MonthlyPlanningService`) to instantiate and refresh a
/// `@MainActor` view model just to read a number. Both `GoalViewModel` and
/// `MonthlyPlanningService` share the allocation/currency-conversion logic and its
/// financial-input evidence without constructing a presentation object.
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
        let allocationID: UUID
        let assetID: UUID
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
        let goalID = goal.id
        let goalCurrency = goal.currency
        let snapshots: [AllocationSnapshot] = (goal.allocations ?? []).compactMap { allocation in
            guard let asset = allocation.asset else { return nil }
            return AllocationSnapshot(
                allocationID: allocation.id,
                assetID: asset.id,
                assetCurrency: asset.currency,
                manualBalance: asset.manualBalance,
                address: asset.address,
                chainId: asset.chainId,
                amountValue: allocation.amountValue
            )
        }

        let contributions = await withTaskGroup(of: GoalBalanceContribution.self) { group in
            for snapshot in snapshots {
                group.addTask {
                    await contribution(
                        for: snapshot,
                        goalCurrency: goalCurrency,
                        tatumService: tatumService,
                        exchangeRateService: exchangeRateService
                    )
                }
            }

            var results: [GoalBalanceContribution] = []
            results.reserveCapacity(snapshots.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        let evidence = GoalFinancialInputEvidence(
            goalID: goalID,
            assetBalances: contributions.map(\.balanceEvidence),
            exchangeRates: contributions.compactMap(\.exchangeRateEvidence)
        )
        return GoalBalanceCalculation(
            total: contributions.reduce(0) { $0 + $1.total },
            hasConversionError: contributions.contains { $0.hasConversionError },
            financialInputEvidence: evidence
        )
    }
}

private struct GoalBalanceContribution: Sendable {
    let balanceEvidence: GoalFinancialInputEvidence.AssetBalance
    let total: Double
    let hasConversionError: Bool
    let exchangeRateEvidence: GoalFinancialInputEvidence.ExchangeRate?
}

/// Computes from a value snapshot without sending SwiftData models to child tasks.
private func contribution(
    for snapshot: GoalBalanceCalculator.AllocationSnapshot,
    goalCurrency: String,
    tatumService: TatumServiceProtocol,
    exchangeRateService: ExchangeRateServiceProtocol
) async -> GoalBalanceContribution {
    let balanceResult = await currentAmount(
        manualBalance: snapshot.manualBalance,
        address: snapshot.address,
        chainId: snapshot.chainId,
        currency: snapshot.assetCurrency,
        tatumService: tatumService
    )
    // Retain the cache entry consumed by this balance before an FX request can suspend.
    // A later refresh with the same numeric balance must still invalidate its old receipt.
    let cacheEvidence = balanceCacheEvidence(
        chainID: snapshot.chainId,
        address: snapshot.address,
        currency: snapshot.assetCurrency
    )
    let authoritativeBalance = snapshot.manualBalance
        + (cacheEvidence.map { Double(bitPattern: $0.balance) } ?? 0)
    let balanceEvidence = GoalFinancialInputEvidence.AssetBalance(
        allocationID: snapshot.allocationID,
        assetID: snapshot.assetID,
        consumedAmount: balanceResult.amount.bitPattern,
        authoritativeAmount: authoritativeBalance.bitPattern,
        balanceCache: cacheEvidence
    )
    let allocatedPortion = max(0, min(max(0, snapshot.amountValue), balanceResult.amount))
    var total = allocatedPortion
    var hasConversionError = balanceResult.error != nil
    var exchangeRateEvidence: GoalFinancialInputEvidence.ExchangeRate?

    if allocatedPortion > 0, snapshot.assetCurrency.uppercased() != goalCurrency.uppercased() {
        do {
            let rate = try await exchangeRateService.fetchRate(from: snapshot.assetCurrency, to: goalCurrency)
            total = allocatedPortion * rate
            exchangeRateEvidence = GoalFinancialInputEvidence.ExchangeRate(
                allocationID: snapshot.allocationID,
                from: snapshot.assetCurrency.uppercased(),
                to: goalCurrency.uppercased(),
                consumedRate: rate.bitPattern,
                authoritativeSnapshot: exchangeRateService.rateSnapshotEvidence(
                    from: snapshot.assetCurrency,
                    to: goalCurrency
                )
            )
        } catch {
            AppLog.error("Exchange rate failed for \(snapshot.assetCurrency) → \(goalCurrency). Skipping value to avoid wrong totals. Error: \(error.localizedDescription)", category: .exchangeRate)
            total = 0
            hasConversionError = true
        }
    }

    return GoalBalanceContribution(
        balanceEvidence: balanceEvidence,
        total: total,
        hasConversionError: hasConversionError,
        exchangeRateEvidence: exchangeRateEvidence
    )
}

private func balanceCacheEvidence(
    chainID: String?,
    address: String?,
    currency: String
) -> BalanceCacheSnapshotEvidence? {
    guard let chainID, let address,
          !chainID.isEmpty, !address.isEmpty else { return nil }
    let cacheKey = BalanceCacheManager.balanceCacheKey(
        chainId: chainID,
        address: address,
        symbol: currency
    )
    return BalanceCacheManager.shared.balanceSnapshotEvidence(for: cacheKey)
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
