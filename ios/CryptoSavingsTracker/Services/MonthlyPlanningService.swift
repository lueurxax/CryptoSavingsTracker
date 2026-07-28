//
//  MonthlyPlanningService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation
import SwiftData
import Combine

/// Service responsible for calculating monthly savings requirements and managing payment plans
@MainActor
final class MonthlyPlanningService: MonthlyPlanningServiceProtocol, ObservableObject {
    
    // MARK: - Dependencies
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let now: () -> Date
    
    // MARK: - Performance Cache
    private var planCache: [UUID: CachedPlan] = [:]
    private var lastCacheUpdate: Date = Date()
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Published Properties
    @Published var isCalculating = false
    @Published var lastCalculationError: Error?
    
    // MARK: - Initialization
    init(
        exchangeRateService: ExchangeRateServiceProtocol,
        now: @escaping () -> Date = Date.init
    ) {
        self.exchangeRateService = exchangeRateService
        self.now = now
    }
    
    // MARK: - Public API
    
    /// Calculate monthly requirements for all goals
    func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement] {
        guard !goals.isEmpty else { return [] }
        
        isCalculating = true
        defer { isCalculating = false }
        
        var requirements: [MonthlyRequirement] = []
        
        for goal in goals {
            do {
                let requirement = try await calculateRequirementForGoal(goal)
                requirements.append(requirement)
            } catch {
                lastCalculationError = error
                return []
            }
        }
        
        lastCalculationError = nil
        return requirements.sorted { $0.goalName < $1.goalName }
    }
    
    /// Calculate total monthly requirement in display currency
    func calculateTotalRequired(for goals: [Goal], displayCurrency: String) async -> Double {
        let requirements = await calculateMonthlyRequirements(for: goals)
        guard lastCalculationError == nil else {
            return 0
        }
        
        let targetCurrency = displayCurrency.uppercased()
        let sourceCurrencies = Set(
            requirements
                .map { $0.currency.uppercased() }
                .filter { $0 != targetCurrency }
        )
        var ratesBySource: [String: Double] = [:]

        for sourceCurrency in sourceCurrencies.sorted() {
            do {
                ratesBySource[sourceCurrency] = try await exchangeRateService.fetchRate(
                    from: sourceCurrency,
                    to: targetCurrency
                )
            } catch {
                AppLog.warning(
                    "Currency conversion failed for \(sourceCurrency) to \(targetCurrency): \(error.localizedDescription)",
                    category: .exchangeRate
                )
                lastCalculationError = MonthlyPlanningError.currencyConversionFailed(
                    "\(sourceCurrency) to \(targetCurrency)"
                )
                return 0
            }
        }

        lastCalculationError = nil
        return requirements.reduce(into: 0) { total, requirement in
            let sourceCurrency = requirement.currency.uppercased()
            if sourceCurrency == targetCurrency {
                total += requirement.requiredMonthly
            } else if let rate = ratesBySource[sourceCurrency] {
                total += requirement.requiredMonthly * rate
            }
        }
    }
    
    /// Get monthly requirement for a single goal
    func getMonthlyRequirement(for goal: Goal) async -> MonthlyRequirement? {
        let requirements = await calculateMonthlyRequirements(for: [goal])
        return requirements.first
    }
    
    /// Clear cache to force recalculation
    func clearCache() {
        planCache.removeAll()
        lastCacheUpdate = Date()
    }
    
    /// Calculate requirement for a single goal
    private func calculateRequirementForGoal(_ goal: Goal) async throws -> MonthlyRequirement {
        // Calculate current total
        let currentTotalResult = await GoalCalculationService.getCurrentTotalResult(for: goal)
        guard currentTotalResult.isComplete else {
            throw MonthlyPlanningError.calculationFailed(
                "Current balance is unavailable for \(goal.name). Refresh balances and retry."
            )
        }
        let currentTotal = currentTotalResult.total
        let remaining = max(0, goal.targetAmount - currentTotal)
        let reference = now()
        let monthsRemaining = try PlanningMonthContract.paymentPeriodsRemaining(
            in: PlanningMonthContract.storageLabel(for: reference),
            paymentDay: MonthlyPlanningSettings.shared.paymentDay,
            deadline: goal.deadline,
            now: reference
        )
        let requiredMonthly = remaining / Double(monthsRemaining)
        let progress = goal.targetAmount > 0 ? min(currentTotal / goal.targetAmount, 1.0) : 0
        
        let status = determineRequirementStatus(
            remaining: remaining,
            monthsRemaining: monthsRemaining,
            requiredMonthly: requiredMonthly
        )
        
        return MonthlyRequirement(
            goalId: goal.id,
            goalName: goal.name,
            currency: goal.currency,
            targetAmount: goal.targetAmount,
            currentTotal: currentTotal,
            remainingAmount: remaining,
            monthsRemaining: monthsRemaining,
            requiredMonthly: requiredMonthly,
            progress: progress,
            deadline: goal.deadline,
            status: status
        )
    }
    
    /// Check if cache needs refresh
    var needsCacheRefresh: Bool {
        Date().timeIntervalSince(lastCacheUpdate) > cacheExpiration
    }
    
    // MARK: - Private Implementation

    /// Determine the status based on requirement calculations
    private func determineRequirementStatus(
        remaining: Double,
        monthsRemaining: Int,
        requiredMonthly: Double
    ) -> RequirementStatus {
        // Goal is complete
        if remaining <= 0 {
            return .completed
        }
        
        // Very high monthly requirement (over 10k)
        if requiredMonthly > 10000 {
            return .critical
        }
        
        // High monthly requirement (over 5k) or very short time
        if requiredMonthly > 5000 || monthsRemaining <= 1 {
            return .attention
        }
        
        // Normal requirement
        return .onTrack
    }
}

// MARK: - Supporting Data Structures

/// Internal data structure for cached calculations
private struct CachedPlan: Identifiable, Sendable {
    let id = UUID()
    let goalId: UUID
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let currency: String
    let status: RequirementStatus
    let lastCalculated: Date
}

// MARK: - Error Types

enum MonthlyPlanningError: LocalizedError, Sendable {
    case calculationFailed(String)
    case currencyConversionFailed(String)
    case invalidGoalData(String)
    
    var errorDescription: String? {
        switch self {
        case .calculationFailed(let message):
            return "Monthly calculation failed: \(message)"
        case .currencyConversionFailed(let message):
            return "Currency conversion failed: \(message)"
        case .invalidGoalData(let message):
            return "Invalid goal data: \(message)"
        }
    }
}
