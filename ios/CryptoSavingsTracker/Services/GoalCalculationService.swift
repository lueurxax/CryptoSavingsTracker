//
//  GoalCalculationService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation
import SwiftData

struct GoalFinancialInputEvidence: Equatable, Sendable {
    struct AssetBalance: Equatable, Sendable {
        let allocationID: UUID
        let assetID: UUID
        let consumedAmount: UInt64
        let authoritativeAmount: UInt64
        let balanceCache: BalanceCacheSnapshotEvidence?
    }

    struct ExchangeRate: Equatable, Sendable {
        let allocationID: UUID
        let from: String
        let to: String
        let consumedRate: UInt64
        let authoritativeSnapshot: ExchangeRateSnapshotEvidence?
    }

    let goalID: UUID
    let assetBalances: [AssetBalance]
    let exchangeRates: [ExchangeRate]

    init(
        goalID: UUID,
        assetBalances: [AssetBalance],
        exchangeRates: [ExchangeRate]
    ) {
        self.goalID = goalID
        self.assetBalances = assetBalances.sorted {
            $0.allocationID.uuidString < $1.allocationID.uuidString
        }
        self.exchangeRates = exchangeRates.sorted {
            $0.allocationID.uuidString < $1.allocationID.uuidString
        }
    }
}

struct GoalCurrentTotalResult: Equatable, Sendable {
    let total: Double
    let error: UserFacingError?
    let financialInputEvidence: GoalFinancialInputEvidence?

    init(
        total: Double,
        error: UserFacingError?,
        financialInputEvidence: GoalFinancialInputEvidence? = nil
    ) {
        self.total = total
        self.error = error
        self.financialInputEvidence = financialInputEvidence
    }

    var isComplete: Bool {
        error == nil
    }
}

/// Service for performing goal calculations with proper separation of concerns
/// This avoids having model objects directly instantiate ViewModels
@MainActor
class GoalCalculationService: GoalCalculationServiceProtocol {
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let tatumService: TatumServiceProtocol
    private let modelContext: ModelContext?

    init(exchangeRateService: ExchangeRateServiceProtocol,
         tatumService: TatumServiceProtocol,
         modelContext: ModelContext? = nil) {
        self.exchangeRateService = exchangeRateService
        self.tatumService = tatumService
        self.modelContext = modelContext
    }

    @MainActor
    convenience init(container: DIContainer? = nil, modelContext: ModelContext? = nil) {
        let resolvedContainer = container ?? DIContainer.shared
        self.init(
            exchangeRateService: resolvedContainer.exchangeRateService,
            tatumService: resolvedContainer.tatumService,
            modelContext: modelContext
        )
    }

    // Instance methods prefer injected services (better for testing)
    func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult {
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: tatumService,
            exchangeRateService: exchangeRateService
        )
        return await viewModel.refreshValues()
    }

    /// Validates only already-consumed financial inputs. It performs synchronous
    /// model/cache reads and never asks either provider to refresh.
    func financialInputEvidenceIsCurrent(
        _ evidence: GoalFinancialInputEvidence,
        for goal: Goal
    ) -> Bool {
        guard evidence.goalID == goal.id else { return false }

        for balance in evidence.assetBalances {
            guard
                let allocation = (goal.allocations ?? []).first(where: {
                    $0.id == balance.allocationID
                }),
                let asset = allocation.asset,
                asset.id == balance.assetID,
                balance.consumedAmount == balance.authoritativeAmount,
                asset.currentAmount.bitPattern == balance.authoritativeAmount,
                balanceCacheEvidence(for: asset) == balance.balanceCache
            else {
                return false
            }
        }

        for rate in evidence.exchangeRates {
            guard
                let allocation = (goal.allocations ?? []).first(where: {
                    $0.id == rate.allocationID
                }),
                let asset = allocation.asset,
                asset.currency.uppercased() == rate.from,
                goal.currency.uppercased() == rate.to
            else {
                return false
            }

            let currentSnapshot = exchangeRateService.rateSnapshotEvidence(
                from: rate.from,
                to: rate.to
            )
            if let authoritativeSnapshot = rate.authoritativeSnapshot {
                guard
                    authoritativeSnapshot.rate == rate.consumedRate,
                    currentSnapshot == authoritativeSnapshot
                else {
                    return false
                }
            } else if currentSnapshot != nil {
                return false
            }
        }

        return true
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

    func getCurrentTotal(for goal: Goal) async -> Double {
        await getCurrentTotalResult(for: goal).total
    }

    func getProgress(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }

    func getSuggestedDeposit(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        let remainingDays = max(Self.getDaysRemaining(for: goal), 1)
        guard goal.targetAmount > 0 else { return 0 }
        let remainingAmount = max(goal.targetAmount - total, 0)
        return remainingAmount / Double(remainingDays)
    }

    // MARK: - REMOVED: Contribution-Aware Calculations
    // These methods were implementing DOUBLE-COUNTING by adding contributions to asset totals.
    // Contributions are TRACKING RECORDS for monthly plan fulfillment, NOT part of goal totals.
    //
    // Correct calculation: Goal Total = Asset Values ONLY
    // Monthly fulfillment = sum(contributions for current month)
    //
    // The following methods have been removed:
    // - getCurrentTotalWithContributions() [DOUBLE-COUNTING BUG]
    // - getProgressWithContributions() [DOUBLE-COUNTING BUG]
    // - getSuggestedDepositWithContributions() [DOUBLE-COUNTING BUG]
    //
    // All callers should use:
    // - getCurrentTotal(for:) for asset-only totals
    // - Separate contribution queries for monthly plan tracking

    /// Calculate current total for a goal using proper ViewModel delegation
    @MainActor static func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult {
        let viewModel = GoalViewModel(goal: goal)
        return await viewModel.refreshValues()
    }

    /// Calculate current total for a goal using proper ViewModel delegation
    @MainActor static func getCurrentTotal(for goal: Goal) async -> Double {
        await getCurrentTotalResult(for: goal).total
    }
    
    /// Calculate progress percentage for a goal
    @MainActor static func getProgress(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }
    
    /// Calculate suggested daily deposit based on the remaining days until the deadline.
    @MainActor static func getSuggestedDeposit(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        let remainingDays = max(getDaysRemaining(for: goal), 1)
        guard goal.targetAmount > 0 else { return 0 }
        let remainingAmount = max(goal.targetAmount - total, 0)
        return remainingAmount / Double(remainingDays)
    }
    
    /// Calculate days remaining until goal deadline
    nonisolated static func getDaysRemaining(for goal: Goal) -> Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: goal.deadline)
        return max(components.day ?? 0, 0)
    }
    
    /// Calculate manual balance total (transactions only, no API calls)
    nonisolated static func getManualTotal(for goal: Goal) -> Double {
        return (goal.allocations ?? []).reduce(0) { result, allocation in
            guard let asset = allocation.asset else { return result }
            let allocatedPortion = min(max(0, allocation.amountValue), asset.manualBalance)
            return result + allocatedPortion
        }
    }
    
    /// Calculate basic progress using manual balance only
    nonisolated static func getManualProgress(for goal: Goal) -> Double {
        let total = getManualTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }
    
    // MARK: - Allocation-Aware Calculations
    
    /// Calculate total value for a goal including both manual balance and on-chain balance with currency conversion
    /// This method properly handles asset allocations and currency conversions
    @MainActor static func getTotalValue(for goal: Goal) async -> Double {
        var totalValue = 0.0
        
        for allocation in (goal.allocations ?? []) {
            guard let asset = allocation.asset else { continue }

            // Get the asset's total value (including on-chain balance if available)
            let assetViewModel = AssetViewModel(asset: asset, tatumService: DIContainer.shared.tatumService)
            await assetViewModel.refreshBalances()
            
            // Get asset value in the goal's currency
            let assetValueInGoalCurrency = await getAssetValueInGoalCurrency(
                asset: asset,
                goalCurrency: goal.currency,
                assetViewModel: assetViewModel
            )
            
            // Calculate allocated portion using the fixed-amount allocation target.
            let assetBalance = assetViewModel.totalBalance
            let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
            
            // Add the allocated portion to the total
            let totalAssetValue = assetBalance > 0 ? assetValueInGoalCurrency : 0
            let ratio = assetBalance > 0 ? allocatedPortion / assetBalance : 0
            totalValue += totalAssetValue * ratio
        }
        
        return totalValue
    }
    
    /// Helper method to get asset value in the goal's currency
    @MainActor
    private static func getAssetValueInGoalCurrency(
        asset: Asset,
        goalCurrency: String,
        assetViewModel: AssetViewModel
    ) async -> Double {
        let totalAssetValue = assetViewModel.totalBalance
        
        // If asset currency matches goal currency, no conversion needed
        if asset.currency.uppercased() == goalCurrency.uppercased() {
            return totalAssetValue
        }
        
        // Convert from asset currency to goal currency
        do {
            let exchangeRate = try await DIContainer.shared.exchangeRateService.fetchRate(
                from: asset.currency,
                to: goalCurrency
            )
            return totalAssetValue * exchangeRate
        } catch {
            print("Failed to get exchange rate from \(asset.currency) to \(goalCurrency): \(error)")
            // Fallback to manual balance only if conversion fails
            return asset.manualBalance
        }
    }
    
    /// Get allocated value from a specific asset to a goal
    @MainActor static func getAllocatedValue(from asset: Asset, to goal: Goal) async -> Double {
        guard let allocation = (goal.allocations ?? []).first(where: { $0.asset?.id == asset.id }) else {
            return 0.0
        }
        
        let assetViewModel = AssetViewModel(asset: asset, tatumService: DIContainer.shared.tatumService)
        await assetViewModel.refreshBalances()
        
        let assetValueInGoalCurrency = await getAssetValueInGoalCurrency(
            asset: asset,
            goalCurrency: goal.currency,
            assetViewModel: assetViewModel
        )
        
        let assetBalance = assetViewModel.totalBalance
        let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
        let ratio = assetBalance > 0 ? allocatedPortion / assetBalance : 0
        return assetValueInGoalCurrency * ratio
    }
    
    /// Get a breakdown of value contributions from each asset to a goal
    @MainActor static func getValueBreakdown(for goal: Goal) async -> [(asset: Asset, value: Double, percentage: Double)] {
        var breakdown: [(asset: Asset, value: Double, percentage: Double)] = []
        
        for allocation in (goal.allocations ?? []) {
            guard let asset = allocation.asset else { continue }

            let allocatedValue = await getAllocatedValue(from: asset, to: goal)
            
            breakdown.append((
                asset: asset,
                value: allocatedValue,
                percentage: 0 // percentage no longer relevant
            ))
        }
        
        return breakdown.sorted { $0.value > $1.value }
    }
}
