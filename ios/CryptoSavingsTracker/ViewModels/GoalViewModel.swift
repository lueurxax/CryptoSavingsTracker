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
    
    private let goal: Goal
    private var modelContext: ModelContext?
    private let balanceCalculator: GoalBalanceCalculator
    
    init(goal: Goal, tatumService: TatumServiceProtocol, exchangeRateService: ExchangeRateServiceProtocol) {
        self.goal = goal
        self.balanceCalculator = GoalBalanceCalculator(tatumService: tatumService, exchangeRateService: exchangeRateService)
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
    
    func refreshValues() async {
        isLoading = true
        viewState = .loading

        // Add small delay to show loading state properly
        if currentTotal == 0 && progress == 0 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        let result = await calculateCurrentTotal()
        let total = result.total
        let prog = calculateProgress(currentTotal: total)
        let deposit = calculateSuggestedDeposit(currentTotal: total)

        await MainActor.run {
            self.currentTotal = total
            self.progress = prog
            self.suggestedDeposit = deposit
            self.isLoading = false
            self.balanceRefreshError = result.error
            self.lastSuccessfulLoad = Date()
            self.viewState = result.error == nil ? .loaded : .degraded(result.error?.message ?? "")
        }
    }

    func retry() async {
        await refreshValues()
    }
    
    private func calculateCurrentTotal() async -> (total: Double, error: UserFacingError?) {
        let result = await balanceCalculator.calculateCurrentTotal(for: goal)
        let error = result.hasConversionError ? balanceRefreshUserError() : nil
        return (result.total, error)
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
