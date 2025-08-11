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
class GoalViewModel: ObservableObject {
    @Published var currentTotal: Double = 0
    @Published var progress: Double = 0
    @Published var suggestedDeposit: Double = 0
    @Published var isLoading: Bool = false
    
    private let goal: Goal
    private var modelContext: ModelContext?
    private let tatumService: TatumService
    private let exchangeRateService: ExchangeRateService
    
    init(goal: Goal, tatumService: TatumService, exchangeRateService: ExchangeRateService) {
        self.goal = goal
        self.tatumService = tatumService
        self.exchangeRateService = exchangeRateService
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
    
    convenience init(goal: Goal, modelContext: ModelContext, tatumService: TatumService, exchangeRateService: ExchangeRateService) {
        self.init(goal: goal, tatumService: tatumService, exchangeRateService: exchangeRateService)
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func refreshValues() async {
        isLoading = true
        
        let total = await calculateCurrentTotal()
        let prog = calculateProgress(currentTotal: total)
        let deposit = calculateSuggestedDeposit(currentTotal: total)
        
        self.currentTotal = total
        self.progress = prog
        self.suggestedDeposit = deposit
        
        isLoading = false
    }
    
    private func calculateCurrentTotal() async -> Double {
        AppLog.debug("Calculating current total for goal '\(goal.name)' (currency: \(goal.currency), assets: \(goal.assets.count))", category: .goalList)
        
        var total: Double = 0
        for (index, asset) in goal.assets.enumerated() {
            AppLog.debug("Processing asset [\(index)]: \(asset.currency) (address: \(asset.address ?? "none"), chainId: \(asset.chainId ?? "none"))", category: .goalList)
            
            let assetValue = await AssetViewModel.getCurrentAmount(for: asset)
            AppLog.debug("Asset value: \(assetValue) \(asset.currency)", category: .goalList)
            
            if asset.currency == goal.currency {
                total += assetValue
                AppLog.debug("Same currency - added directly: \(assetValue) \(asset.currency)", category: .goalList)
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: asset.currency, to: goal.currency)
                    let convertedValue = assetValue * rate
                    total += convertedValue
                    AppLog.debug("Converted \(assetValue) \(asset.currency) to \(convertedValue) \(goal.currency) (rate: \(rate))", category: .exchangeRate)
                } catch {
                    total += assetValue
                    AppLog.warning("Exchange rate failed for \(asset.currency) → \(goal.currency), using raw value: \(assetValue) \(asset.currency). Error: \(error.localizedDescription)", category: .exchangeRate)
                }
            }
            AppLog.debug("Running total: \(total) \(goal.currency)", category: .goalList)
        }
        
        AppLog.debug("Final total for goal '\(goal.name)': \(total) \(goal.currency)", category: .goalList)
        return total
    }
    
    private func calculateProgress(currentTotal: Double) -> Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(currentTotal / goal.targetAmount, 1.0)
    }
    
    private func calculateSuggestedDeposit(currentTotal: Double) -> Double {
        let remaining = goal.remainingDates.count
        guard remaining > 0, goal.targetAmount > 0 else { return 0 }
        
        let remainingAmount = max(goal.targetAmount - currentTotal, 0)
        return remainingAmount / Double(remaining)
    }
}