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
    private let tatumService: TatumServiceProtocol
    private let exchangeRateService: ExchangeRateServiceProtocol
    
    init(goal: Goal, tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
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
    
    convenience init(goal: Goal, modelContext: ModelContext, tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
        self.init(goal: goal, tatumService: tatumService, exchangeRateService: exchangeRateService)
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func refreshValues() async {
        isLoading = true
        
        // Add small delay to show loading state properly
        if currentTotal == 0 && progress == 0 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        let total = await calculateCurrentTotal()
        let prog = calculateProgress(currentTotal: total)
        let deposit = calculateSuggestedDeposit(currentTotal: total)
        
        await MainActor.run {
            self.currentTotal = total
            self.progress = prog
            self.suggestedDeposit = deposit
            self.isLoading = false
        }
    }
    
    private func calculateCurrentTotal() async -> Double {
        
        var total: Double = 0
        for (_,  allocation) in goal.allocations.enumerated() {
            guard let asset = allocation.asset else { continue }
            let assetBalance = await AssetViewModel.getCurrentAmount(for: asset)
            let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
            guard allocatedPortion > 0 else { continue }

            if asset.currency.uppercased() == goal.currency.uppercased() {
                total += allocatedPortion
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: asset.currency, to: goal.currency)
                    let convertedValue = allocatedPortion * rate
                    total += convertedValue
                } catch {
                    AppLog.error("Exchange rate failed for \(asset.currency) → \(goal.currency). Skipping value to avoid wrong totals. Error: \(error.localizedDescription)", category: .exchangeRate)
                    continue
                }
            }
        }
        
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
