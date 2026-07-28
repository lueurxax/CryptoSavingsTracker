//
//  GoalViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class GoalViewModel: ObservableObject, ErrorAwareViewModel {
    @Published var currentTotal: Double = 0
    @Published var progress: Double = 0
    @Published var suggestedDeposit: Double = 0
    @Published var isLoading: Bool = false
    @Published var balanceRefreshError: UserFacingError?
    @Published var viewState: ViewState = .idle
    var lastSuccessfulLoad: Date?
    
    private var goal: Goal
    private var goalGeneration = 0
    private var modelContext: ModelContext?
    private let tatumService: TatumServiceProtocol
    private let exchangeRateService: ExchangeRateServiceProtocol
    
    init(goal: Goal, tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
        self.goal = goal
        self.tatumService = tatumService
        self.exchangeRateService = exchangeRateService
        self.currentTotal = goal.manualTotal
        self.progress = goal.manualProgress
        self.suggestedDeposit = goal.suggestedDailyDeposit
    }
    
    // Convenience initializer that uses DI container for backward compatibility
    convenience init(goal: Goal) {
        let container = DIContainer.shared
        self.init(
            goal: goal,
            tatumService: container.tatumService,
            exchangeRateService: container.exchangeRateService
        )
    }
    
    convenience init(goal: Goal, modelContext: ModelContext, tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
        self.init(goal: goal, tatumService: tatumService, exchangeRateService: exchangeRateService)
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func updateGoal(_ goal: Goal) {
        guard self.goal.id != goal.id else { return }

        self.goal = goal
        goalGeneration += 1
        currentTotal = goal.manualTotal
        progress = goal.manualProgress
        suggestedDeposit = goal.suggestedDailyDeposit
        isLoading = false
        balanceRefreshError = nil
        viewState = .idle
        lastSuccessfulLoad = nil
    }
    
    @discardableResult
    func refreshValues() async -> GoalCurrentTotalResult {
        goalGeneration &+= 1
        let refreshGoal = goal
        let refreshGeneration = goalGeneration
        isLoading = true
        viewState = .loading

        // Add small delay to show loading state properly
        if currentTotal == 0 && progress == 0 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        let result = await calculateCurrentTotal(for: refreshGoal)
        let total = result.total
        let prog = calculateProgress(currentTotal: total, goal: refreshGoal)
        let deposit = refreshGoal.suggestedDailyDeposit(currentTotal: total)

        guard refreshGeneration == goalGeneration, refreshGoal.id == goal.id else {
            return result
        }

        currentTotal = total
        progress = prog
        suggestedDeposit = deposit
        isLoading = false
        balanceRefreshError = result.error
        lastSuccessfulLoad = Date()
        viewState = result.error == nil ? .loaded : .degraded(result.error?.message ?? "")
        return result
    }

    func retry() async {
        await refreshValues()
    }
    
    private func calculateCurrentTotal(for goal: Goal) async -> GoalCurrentTotalResult {
        var total: Double = 0
        var firstRefreshError: UserFacingError?
        var assetBalanceEvidence: [GoalFinancialInputEvidence.AssetBalance] = []
        var exchangeRateEvidence: [GoalFinancialInputEvidence.ExchangeRate] = []

        for allocation in goal.allocations ?? [] {
            guard let asset = allocation.asset else { continue }
            let balanceResult = await currentAmount(for: asset)
            assetBalanceEvidence.append(
                GoalFinancialInputEvidence.AssetBalance(
                    allocationID: allocation.id,
                    assetID: asset.id,
                    consumedAmount: balanceResult.amount.bitPattern,
                    authoritativeAmount: asset.currentAmount.bitPattern,
                    balanceCache: balanceCacheEvidence(for: asset)
                )
            )
            if balanceResult.error != nil, firstRefreshError == nil {
                firstRefreshError = balanceRefreshUserError()
            }

            let assetBalance = balanceResult.amount
            let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
            guard allocatedPortion > 0 else { continue }

            if asset.currency.uppercased() == goal.currency.uppercased() {
                total += allocatedPortion
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: asset.currency, to: goal.currency)
                    exchangeRateEvidence.append(
                        GoalFinancialInputEvidence.ExchangeRate(
                            allocationID: allocation.id,
                            from: asset.currency.uppercased(),
                            to: goal.currency.uppercased(),
                            consumedRate: rate.bitPattern,
                            authoritativeSnapshot: exchangeRateService.rateSnapshotEvidence(
                                from: asset.currency,
                                to: goal.currency
                            )
                        )
                    )
                    let convertedValue = allocatedPortion * rate
                    total += convertedValue
                } catch {
                    AppLog.error("Exchange rate failed for \(asset.currency) → \(goal.currency). Skipping value to avoid wrong totals. Error: \(error.localizedDescription)", category: .exchangeRate)
                    if firstRefreshError == nil {
                        firstRefreshError = balanceRefreshUserError()
                    }
                    continue
                }
            }
        }
        
        return GoalCurrentTotalResult(
            total: total,
            error: firstRefreshError,
            financialInputEvidence: GoalFinancialInputEvidence(
                goalID: goal.id,
                assetBalances: assetBalanceEvidence,
                exchangeRates: exchangeRateEvidence
            )
        )
    }

    private func balanceCacheEvidence(for asset: Asset) -> BalanceCacheSnapshotEvidence? {
        guard
            let chainID = asset.chainId,
            let address = asset.address,
            !chainID.isEmpty,
            !address.isEmpty
        else {
            return nil
        }
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: chainID,
            address: address,
            symbol: asset.currency
        )
        return BalanceCacheManager.shared.balanceSnapshotEvidence(for: cacheKey)
    }

    private func currentAmount(for asset: Asset) async -> (amount: Double, error: Error?) {
        var total = asset.manualBalance

        guard let address = asset.address,
              let chainId = asset.chainId,
              !address.isEmpty else {
            return (total, nil)
        }

        do {
            let onChainBalance = try await tatumService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: false
            )
            total += onChainBalance
            return (total, nil)
        } catch {
            AppLog.warning("Goal detail balance refresh kept manual balance after on-chain fetch failed: \(error.localizedDescription)", category: .balanceService)
            return (total, error)
        }
    }

    private func balanceRefreshUserError() -> UserFacingError {
        UserFacingError(
            title: "Balances Not Refreshed",
            message: "Some balances could not be updated. Existing values are still shown.",
            recoverySuggestion: "Check your connection and retry.",
            isRetryable: true,
            category: .network
        )
    }
    
    private func calculateProgress(currentTotal: Double, goal: Goal) -> Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(currentTotal / goal.targetAmount, 1.0)
    }
    
}
