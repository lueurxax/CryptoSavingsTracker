//
//  FixedBudgetPlanningService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 03/01/2026.
//

import Foundation
import SwiftData
import Combine

/// Service for computing fixed budget plans with optimal contribution sequencing
@MainActor
final class FixedBudgetPlanningService: ObservableObject {

    // MARK: - Dependencies

    private let exchangeRateService: ExchangeRateServiceProtocol
    private let settings: MonthlyPlanningSettings

    // MARK: - Cache

    private var cachedPlan: FixedBudgetPlan?
    private var cacheGoalIds: Set<UUID> = []
    private var cacheBudget: Double = 0
    private var lastCacheUpdate: Date = .distantPast
    private let cacheExpiration: TimeInterval = 300 // 5 minutes

    // MARK: - Published Properties

    @Published var isCalculating = false
    @Published var lastError: Error?

    // MARK: - Initialization

    init(exchangeRateService: ExchangeRateServiceProtocol, settings: MonthlyPlanningSettings = .shared) {
        self.exchangeRateService = exchangeRateService
        self.settings = settings
    }

    // MARK: - Public API

    /// Calculate the minimum budget needed to meet all goal deadlines
    /// Returns the MAX of all individual goal minimums (the binding constraint)
    func calculateMinimumBudget(goals: [Goal], currency: String) async -> Double {
        guard !goals.isEmpty else { return 0 }

        let activeGoals = goals.filter { $0.lifecycleStatus == .active }.sorted { $0.deadline < $1.deadline }
        guard !activeGoals.isEmpty else { return 0 }

        var cumulativeRemaining: Double = 0
        var maxRequired: Double = 0

        for goal in activeGoals {
            var remaining = await calculateRemaining(for: goal)
            if goal.currency != currency {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: goal.currency, to: currency)
                    remaining *= rate
                } catch {
                    AppLog.warning("Currency conversion failed: \(error.localizedDescription)", category: .exchangeRate)
                }
            }

            if remaining <= 0 { continue }
            cumulativeRemaining += remaining

            let months = max(1, calculateMonthsRemaining(from: Date(), to: goal.deadline))
            let required = cumulativeRemaining / Double(months)
            maxRequired = max(maxRequired, required)
        }

        return maxRequired
    }

    /// Calculate the leveled budget (total remaining / months to last deadline)
    func calculateLeveledBudget(goals: [Goal], currency: String) async -> Double {
        guard !goals.isEmpty else { return 0 }

        let activeGoals = goals.filter { $0.lifecycleStatus == .active }
        guard !activeGoals.isEmpty else { return 0 }

        var totalRemaining: Double = 0
        var latestDeadline = Date()

        for goal in activeGoals {
            let remaining = await calculateRemaining(for: goal)

            // Convert to target currency
            var convertedRemaining = remaining
            if goal.currency != currency {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: goal.currency, to: currency)
                    convertedRemaining = remaining * rate
                } catch {
                    AppLog.warning("Currency conversion failed: \(error.localizedDescription)", category: .exchangeRate)
                }
            }

            totalRemaining += convertedRemaining

            if goal.deadline > latestDeadline {
                latestDeadline = goal.deadline
            }
        }

        let monthsToLast = max(1, calculateMonthsRemaining(from: Date(), to: latestDeadline))
        return totalRemaining / Double(monthsToLast)
    }

    /// Check if the given budget is sufficient for all goals
    func checkFeasibility(goals: [Goal], budget: Double, currency: String) async -> FeasibilityResult {
        guard !goals.isEmpty else {
            return .empty
        }

        let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency)
        let isFeasible = budget >= minimumRequired && budget > 0

        var infeasibleGoals: [InfeasibleGoal] = []
        var suggestions: [FeasibilitySuggestion] = []

        if !isFeasible {
            let activeGoals = goals.filter { $0.lifecycleStatus == .active }.sorted { $0.deadline < $1.deadline }
            var cumulativeRemaining: Double = 0

            for goal in activeGoals {
                var remaining = await calculateRemaining(for: goal)
                if goal.currency != currency {
                    if let rate = try? await exchangeRateService.fetchRate(from: goal.currency, to: currency) {
                        remaining *= rate
                    }
                }

                if remaining <= 0 { continue }
                cumulativeRemaining += remaining

                let months = max(1, calculateMonthsRemaining(from: Date(), to: goal.deadline))
                let required = cumulativeRemaining / Double(months)

                if required > budget {
                    let shortfall = required - budget
                    infeasibleGoals.append(InfeasibleGoal(
                        id: UUID(),
                        goalId: goal.id,
                        goalName: goal.name,
                        deadline: goal.deadline,
                        requiredMonthly: required,
                        shortfall: shortfall,
                        currency: currency
                    ))
                }
            }

            // Generate suggestions
            if !infeasibleGoals.isEmpty {
                // Suggest increasing budget
                suggestions.append(.increaseBudget(to: minimumRequired, currency: currency))

                // Suggest extending deadlines
                for infeasible in infeasibleGoals.prefix(2) {
                    // Calculate months needed at current budget
                    let remaining = await calculateRemainingForGoal(id: infeasible.goalId, in: goals)
                    guard budget > 0, budget.isFinite, remaining.isFinite else { continue }
                    let monthsNeededDouble = remaining / budget
                    guard monthsNeededDouble.isFinite else { continue }
                    let cappedMonthsNeeded = min(monthsNeededDouble, Double(Int.max))
                    let monthsNeeded = Int(ceil(cappedMonthsNeeded))
                    let currentMonths = calculateMonthsRemaining(from: Date(), to: infeasible.deadline)
                    let extensionNeeded = monthsNeeded - currentMonths

                    if extensionNeeded > 0 && extensionNeeded <= 12 {
                        suggestions.append(.extendDeadline(
                            goalId: infeasible.goalId,
                            goalName: infeasible.goalName,
                            byMonths: extensionNeeded
                        ))
                    }
                }
            }
        }

        return FeasibilityResult(
            isFeasible: isFeasible,
            minimumRequired: minimumRequired,
            currency: currency,
            infeasibleGoals: infeasibleGoals,
            suggestions: suggestions
        )
    }

    /// Generate the optimal contribution schedule
    func generateSchedule(goals: [Goal], budget: Double, currency: String) async -> FixedBudgetPlan {
        isCalculating = true
        defer { isCalculating = false }

        let goalIds = Set(goals.map { $0.id })
        if let cached = cachedPlan,
           cacheGoalIds == goalIds,
           abs(cacheBudget - budget) < 0.01,
           Date().timeIntervalSince(lastCacheUpdate) < cacheExpiration {
            return cached
        }

        // Sort goals by deadline (earliest first)
        let activeGoals = goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }

        guard !activeGoals.isEmpty else {
            return FixedBudgetPlan(
                monthlyBudget: budget,
                currency: currency,
                schedule: [],
                isLeveled: true,
                minimumRequired: 0,
                goalRemainingById: [:]
            )
        }

        // Calculate remaining amounts for each goal (converted to target currency)
        var goalRemaining: [UUID: Double] = [:]
        var goalNames: [UUID: String] = [:]
        for goal in activeGoals {
            var remaining = await calculateRemaining(for: goal)
            if goal.currency != currency {
                if let rate = try? await exchangeRateService.fetchRate(from: goal.currency, to: currency) {
                    remaining *= rate
                }
            }
            goalRemaining[goal.id] = remaining
            goalNames[goal.id] = goal.name
        }

        guard budget > 0 else {
            let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency)
            return FixedBudgetPlan(
                monthlyBudget: budget,
                currency: currency,
                schedule: [],
                isLeveled: false,
                minimumRequired: minimumRequired,
                goalRemainingById: goalRemaining
            )
        }

        // Generate payment dates starting from next payment day
        var payments: [ScheduledPayment] = []
        var paymentNumber = 1
        var paymentDate = nextPaymentDate()
        var goalRunningTotals: [UUID: Double] = [:]
        var remainingByGoal = goalRemaining

        // Initialize running totals
        for goal in activeGoals {
            goalRunningTotals[goal.id] = 0
        }

        var safetyCounter = 0
        while remainingByGoal.values.contains(where: { $0 > 0.01 }) && safetyCounter < 600 {
            safetyCounter += 1
            let startTotals = goalRunningTotals
            var paymentAllocations: [UUID: Double] = [:]
            var remainingBudget = budget

            for goal in activeGoals {
                guard paymentDate <= goal.deadline else { continue }
                let remaining = remainingByGoal[goal.id] ?? 0
                guard remaining > 0.01 else { continue }
                let amount = min(remainingBudget, remaining)
                guard amount > 0.01 else { continue }
                paymentAllocations[goal.id, default: 0] += amount
                goalRunningTotals[goal.id, default: 0] += amount
                remainingByGoal[goal.id, default: 0] = max(0, remaining - amount)
                remainingBudget -= amount
                if remainingBudget <= 0.01 { break }
            }

            if paymentAllocations.isEmpty {
                break
            }

            let contributions = activeGoals.compactMap { goal -> GoalContribution? in
                guard let amount = paymentAllocations[goal.id], amount > 0.01 else { return nil }
                let startingTotal = startTotals[goal.id] ?? 0
                let newTotal = (goalRunningTotals[goal.id] ?? 0)
                let isStart = startingTotal <= 0.01
                let isComplete = (remainingByGoal[goal.id] ?? 0) <= 0.01

                return GoalContribution(
                    goalId: goal.id,
                    goalName: goalNames[goal.id] ?? goal.name,
                    amount: amount,
                    isGoalStart: isStart,
                    isGoalComplete: isComplete,
                    runningTotal: newTotal
                )
            }

            if !contributions.isEmpty {
                payments.append(ScheduledPayment(
                    paymentDate: paymentDate,
                    paymentNumber: paymentNumber,
                    contributions: contributions
                ))
            }

            paymentNumber += 1
            paymentDate = Calendar.current.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency)
        let plan = FixedBudgetPlan(
            monthlyBudget: budget,
            currency: currency,
            schedule: payments,
            isLeveled: abs(budget - minimumRequired) < 0.01,
            minimumRequired: minimumRequired,
            goalRemainingById: goalRemaining
        )

        // Cache the result
        cachedPlan = plan
        cacheGoalIds = goalIds
        cacheBudget = budget
        lastCacheUpdate = Date()

        return plan
    }

    /// Build timeline blocks for visualization
    func buildTimelineBlocks(from plan: FixedBudgetPlan, goals: [Goal]) -> [ScheduledGoalBlock] {
        let deadlines = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.deadline) })
        var summaries: [UUID: (goalName: String, startPayment: Int, endPayment: Int, startDate: Date, endDate: Date, totalAmount: Double, paymentCount: Int)] = [:]

        for payment in plan.schedule {
            for contribution in payment.contributions {
                guard let deadline = deadlines[contribution.goalId], payment.paymentDate <= deadline else { continue }
                if var existing = summaries[contribution.goalId] {
                    existing.endPayment = payment.paymentNumber
                    existing.endDate = payment.paymentDate
                    existing.totalAmount += contribution.amount
                    existing.paymentCount += 1
                    summaries[contribution.goalId] = existing
                } else {
                    summaries[contribution.goalId] = (
                        goalName: contribution.goalName,
                        startPayment: payment.paymentNumber,
                        endPayment: payment.paymentNumber,
                        startDate: payment.paymentDate,
                        endDate: payment.paymentDate,
                        totalAmount: contribution.amount,
                        paymentCount: 1
                    )
                }
            }
        }

        return summaries
            .sorted { $0.value.startPayment < $1.value.startPayment }
            .map { goalId, summary in
                let goal = goals.first { $0.id == goalId }
                return ScheduledGoalBlock(
                    id: UUID(),
                    goalId: goalId,
                    goalName: summary.goalName,
                    emoji: goal?.emoji,
                    startPaymentNumber: summary.startPayment,
                    endPaymentNumber: summary.endPayment,
                    startDate: summary.startDate,
                    endDate: summary.endDate,
                    totalAmount: summary.totalAmount,
                    paymentCount: summary.paymentCount
                )
            }
    }

    /// Clear the cache
    func clearCache() {
        cachedPlan = nil
        cacheGoalIds = []
        cacheBudget = 0
        lastCacheUpdate = .distantPast
    }

    // MARK: - Recalculation with CompletionBehavior

    /// Recalculate the schedule after an actual contribution that differs from the planned amount.
    /// Uses the CompletionBehavior setting to determine how to handle the difference.
    ///
    /// - Parameters:
    ///   - plan: The original fixed budget plan
    ///   - actualContribution: The amount actually contributed this period
    ///   - forPaymentNumber: The payment number where the contribution was made
    ///   - goals: Current list of active goals
    ///   - behavior: How to handle over/under contributions
    /// - Returns: A new plan reflecting the recalculated schedule
    func recalculateAfterContribution(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int,
        goals: [Goal],
        behavior: CompletionBehavior
    ) async -> FixedBudgetPlan {
        clearCache()

        // Calculate total remaining after this payment
        let completedPayments = plan.schedule.prefix(forPaymentNumber)
        let totalContributedBefore = completedPayments.reduce(0) { $0 + $1.totalAmount }
        let adjustedTotalContributed = totalContributedBefore - (completedPayments.last?.totalAmount ?? 0) + actualContribution

        // Calculate remaining amount for all goals
        var totalRemaining: Double = 0
        for goal in goals.filter({ $0.lifecycleStatus == .active }) {
            let remaining = await calculateRemaining(for: goal)
            var convertedRemaining = remaining
            if goal.currency != plan.currency {
                if let rate = try? await exchangeRateService.fetchRate(from: goal.currency, to: plan.currency) {
                    convertedRemaining = remaining * rate
                }
            }
            totalRemaining += convertedRemaining
        }

        // Subtract what's already contributed
        let remainingAfterContribution = max(0, totalRemaining - adjustedTotalContributed)

        switch behavior {
        case .finishFaster:
            // Keep the same monthly budget, goals complete earlier if over-contributed
            // Just regenerate the schedule from the current state
            return await generateSchedule(goals: goals, budget: plan.monthlyBudget, currency: plan.currency)

        case .lowerPayments:
            // Recalculate to spread remaining amount over remaining months
            // Keep original timeline, reduce monthly amount
            let remainingPayments = plan.schedule.count - forPaymentNumber
            guard remainingPayments > 0 else {
                // No more payments needed
                return await generateSchedule(goals: goals, budget: plan.monthlyBudget, currency: plan.currency)
            }

            let newMonthlyBudget = remainingAfterContribution / Double(remainingPayments)
            // Ensure we don't go below minimum required
            let minimum = await calculateMinimumBudget(goals: goals, currency: plan.currency)
            let adjustedBudget = max(newMonthlyBudget, minimum)

            return await generateSchedule(goals: goals, budget: adjustedBudget, currency: plan.currency)
        }
    }

    /// Calculate the difference between planned and actual contribution
    func contributionDifference(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int
    ) -> Double {
        guard forPaymentNumber > 0 && forPaymentNumber <= plan.schedule.count else {
            return 0
        }
        let plannedAmount = plan.schedule[forPaymentNumber - 1].totalAmount
        return actualContribution - plannedAmount
    }

    /// Get the adjusted schedule after applying a contribution difference
    func adjustedScheduleSummary(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int,
        behavior: CompletionBehavior
    ) -> (newMonthlyAmount: Double?, monthsSaved: Int?) {
        let difference = contributionDifference(plan: plan, actualContribution: actualContribution, forPaymentNumber: forPaymentNumber)

        switch behavior {
        case .finishFaster:
            // Calculate how many months could be saved
            if difference > 0 {
                let remainingPayments = plan.schedule.count - forPaymentNumber
                let monthsSaved = Int(difference / plan.monthlyBudget)
                return (nil, min(monthsSaved, remainingPayments))
            }
            return (nil, nil)

        case .lowerPayments:
            // Calculate new monthly amount
            let totalRemaining = plan.schedule.suffix(from: forPaymentNumber).reduce(0) { $0 + $1.totalAmount }
            let adjustedRemaining = totalRemaining - difference
            let remainingPayments = plan.schedule.count - forPaymentNumber
            guard remainingPayments > 0 else { return (nil, nil) }

            let newMonthly = adjustedRemaining / Double(remainingPayments)
            return (newMonthly, nil)
        }
    }

    // MARK: - Private Helpers

    private func calculateRemaining(for goal: Goal) async -> Double {
        let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        return max(0, goal.targetAmount - currentTotal)
    }

    private func calculateRemainingForGoal(id: UUID, in goals: [Goal]) async -> Double {
        guard let goal = goals.first(where: { $0.id == id }) else { return 0 }
        return await calculateRemaining(for: goal)
    }

    private func calculateMonthsRemaining(from startDate: Date, to endDate: Date) -> Int {
        let paymentDay = settings.paymentDay
        let calendar = Calendar.current

        var components = calendar.dateComponents([.year, .month], from: startDate)
        components.day = paymentDay
        guard var paymentDate = calendar.date(from: components) else {
            return max(1, calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 1)
        }

        if paymentDate <= startDate {
            paymentDate = calendar.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        var count = 0
        while paymentDate < endDate {
            count += 1
            paymentDate = calendar.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        return max(1, count)
    }

    private func nextPaymentDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let paymentDay = settings.paymentDay

        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = paymentDay

        guard var paymentDate = calendar.date(from: components) else {
            return now
        }

        if paymentDate <= now {
            paymentDate = calendar.date(byAdding: .month, value: 1, to: paymentDate) ?? paymentDate
        }

        return paymentDate
    }
}
