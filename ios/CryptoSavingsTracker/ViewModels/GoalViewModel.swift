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
        await balanceCalculator.calculateCurrentTotal(for: goal).currentTotalResult

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
