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
    
    // MARK: - Performance Cache
    private var planCache: [UUID: CachedPlan] = [:]
    private var lastCacheUpdate: Date = Date()
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Published Properties
    @Published var isCalculating = false
    @Published var lastCalculationError: Error?
    
    // MARK: - Initialization
    init(exchangeRateService: ExchangeRateServiceProtocol) {
        self.exchangeRateService = exchangeRateService
    }
    
    // MARK: - Public API
    
    /// Calculate monthly requirements for all goals
    func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement] {
        guard !goals.isEmpty else { return [] }
        
        isCalculating = true
        defer { isCalculating = false }
        
        var requirements: [MonthlyRequirement] = []
        
        for goal in goals {
            let requirement = await calculateRequirementForGoal(goal)
            requirements.append(requirement)
        }
        
        lastCalculationError = nil
        return requirements.sorted { $0.goalName < $1.goalName }
    }
    
    /// Calculate total monthly requirement in display currency
    func calculateTotalRequired(for goals: [Goal], displayCurrency: String) async -> Double {
        let requirements = await calculateMonthlyRequirements(for: goals)
        
        var total: Double = 0
        
        for requirement in requirements {
            if requirement.currency == displayCurrency {
                total += requirement.requiredMonthly
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: requirement.currency, to: displayCurrency)
                    total += requirement.requiredMonthly * rate
                } catch {
                    AppLog.warning("Currency conversion failed for \(requirement.currency) to \(displayCurrency): \(error.localizedDescription)", category: .exchangeRate)
                    total += requirement.requiredMonthly // Fallback to 1:1
                }
            }
        }
        
        return total
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
    private func calculateRequirementForGoal(_ goal: Goal) async -> MonthlyRequirement {
        // Calculate current total
        let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        let remaining = max(0, goal.targetAmount - currentTotal)
        let monthsRemaining = max(1, calculateMonthsRemaining(from: Date(), to: goal.deadline))
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

    /// Calculate how many payment periods remain until the deadline
    /// Uses the payment day from MonthlyPlanningSettings
    ///
    /// Example: Today Dec 18, payment day 25th, deadline March 1
    /// Payment dates: Dec 25, Jan 25, Feb 25 = 3 periods
    private func calculateMonthsRemaining(from startDate: Date, to endDate: Date) -> Int {
        let settings = MonthlyPlanningSettings.shared
        let paymentDay = settings.paymentDay
        let calendar = Calendar.current

        // Find the next payment date from startDate
        var components = calendar.dateComponents([.year, .month], from: startDate)
        components.day = paymentDay
        guard var paymentDate = calendar.date(from: components) else {
            // Fallback to simple month calculation
            return max(1, calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 1)
        }

        // If payment date this month has passed, start from next month
        if paymentDate <= startDate {
            paymentDate = calendar.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        // Count payment dates until we pass the deadline
        var count = 0
        while paymentDate < endDate {
            count += 1
            paymentDate = calendar.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        // Ensure at least 1 payment period
        return max(1, count)
    }
    
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