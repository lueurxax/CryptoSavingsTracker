//
//  BudgetCalculatorService.swift
//  CryptoSavingsTracker
//
//  Computes budget-based contribution previews for monthly planning.
//

import Foundation
import SwiftData
import Combine
import CryptoKit

/// Service for computing budget calculator previews with optimal contribution sequencing.
@MainActor
final class BudgetCalculatorService: ObservableObject {

    // MARK: - Dependencies

    private let exchangeRateService: ExchangeRateServiceProtocol
    private let settings: MonthlyPlanningSettings

    // MARK: - Cache

    private var cachedPlan: BudgetCalculatorPlan?
    private var cacheGoalIds: Set<UUID> = []
    private var cacheBudget: Double = 0
    private var cacheCurrency: String = ""
    private var lastCacheUpdate: Date = .distantPast
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    private var rateSnapshotCache: [String: [String: Double]] = [:]

    // MARK: - Published Properties

    @Published var isCalculating = false
    @Published var lastError: Error?

    // MARK: - Initialization

    init(exchangeRateService: ExchangeRateServiceProtocol, settings: MonthlyPlanningSettings? = nil) {
        self.exchangeRateService = exchangeRateService
        self.settings = settings ?? MonthlyPlanningSettings.shared
    }

    // MARK: - Public API

    /// Calculate the minimum budget needed to meet all goal deadlines.
    /// Returns the MAX of all individual goal minimums (the binding constraint).
    func calculateMinimumBudget(goals: [Goal], currency: String) async -> Double {
        await calculateMinimumBudget(goals: goals, currency: currency, ratesByPair: nil)
    }

    private func calculateMinimumBudget(
        goals: [Goal],
        currency: String,
        ratesByPair: [String: Double]?
    ) async -> Double {
        guard !goals.isEmpty else { return 0 }

        let activeGoals = goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }
        guard !activeGoals.isEmpty else { return 0 }

        var cumulativeRemaining: Double = 0
        var maxRequired: Double = 0

        for goal in activeGoals {
            var remaining = await calculateRemaining(for: goal)
            if goal.currency != currency {
                if let ratesByPair {
                    guard let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] else {
                        continue
                    }
                    remaining *= rate
                } else {
                    do {
                        let rate = try await exchangeRateService.fetchRate(from: goal.currency, to: currency)
                        remaining *= rate
                    } catch {
                        AppLog.warning("Budget conversion failed: \(error.localizedDescription)", category: .exchangeRate)
                    }
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

    /// Check if the given budget is sufficient for all goals.
    func checkFeasibility(goals: [Goal], budget: Double, currency: String) async -> FeasibilityResult {
        await checkFeasibility(goals: goals, budget: budget, currency: currency, ratesByPair: nil)
    }

    private func checkFeasibility(
        goals: [Goal],
        budget: Double,
        currency: String,
        ratesByPair: [String: Double]?
    ) async -> FeasibilityResult {
        guard !goals.isEmpty else {
            return .empty
        }

        let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency, ratesByPair: ratesByPair)
        let isFeasible = budget >= minimumRequired && budget > 0

        var infeasibleGoals: [InfeasibleGoal] = []
        var suggestions: [FeasibilitySuggestion] = []
        var addedGoalSuggestions = false

        if !isFeasible {
            let activeGoals = goals
                .filter { $0.lifecycleStatus == .active }
                .sorted { $0.deadline < $1.deadline }
            var cumulativeRemaining: Double = 0

            for goal in activeGoals {
                let remainingInGoalCurrency = await calculateRemaining(for: goal)
                var remaining = remainingInGoalCurrency
                var conversionRate: Double?
                if goal.currency != currency {
                    if let ratesByPair {
                        if let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] {
                            remaining *= rate
                            conversionRate = rate
                        }
                    } else if let rate = try? await exchangeRateService.fetchRate(from: goal.currency, to: currency) {
                        remaining *= rate
                        conversionRate = rate
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

                    if !addedGoalSuggestions, budget > 0 {
                        let monthsNeeded = Int(ceil(cumulativeRemaining / budget))
                        let extensionMonths = max(0, monthsNeeded - months)
                        if extensionMonths > 0 {
                            suggestions.append(
                                .extendDeadline(
                                    goalId: goal.id,
                                    goalName: goal.name,
                                    byMonths: extensionMonths
                                )
                            )
                        }

                        let reductionBudget = shortfall * Double(months)
                        let reductionGoalCurrency = conversionRate.map { reductionBudget / $0 } ?? reductionBudget
                        let proposedTarget = max(goal.currentTotal, goal.targetAmount - reductionGoalCurrency)
                        if proposedTarget < goal.targetAmount {
                            suggestions.append(
                                .reduceTarget(
                                    goalId: goal.id,
                                    goalName: goal.name,
                                    to: proposedTarget,
                                    currency: goal.currency
                                )
                            )
                        }

                        suggestions.append(.editGoal(goalId: goal.id, goalName: goal.name))
                        addedGoalSuggestions = true
                    }
                }
            }

            if !infeasibleGoals.isEmpty {
                suggestions.append(.increaseBudget(to: minimumRequired, currency: currency))
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

    /// Compute an atomic budget snapshot used for save gating and preview rendering.
    func computeBudgetSnapshot(
        requestId: UUID,
        goals: [Goal],
        enteredBudget: MoneyAmount,
        goalsSignature: String,
        rateSnapshotId: String?
    ) async -> BudgetComputationResult {
        let activeGoals = goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }
        let positiveBudget = enteredBudget.minorUnitValue > 0

        guard !activeGoals.isEmpty, positiveBudget else {
            let zero = MoneyQuantizer.normalize(0, currency: enteredBudget.currency, mode: .halfUp)
            return BudgetComputationResult(
                requestId: requestId,
                enteredBudgetCanonical: enteredBudget,
                minimumRequiredCanonical: zero,
                shortfallCanonical: zero,
                isFeasible: false,
                plan: nil,
                timeline: [],
                rateSnapshotTimestamp: nil,
                rateSnapshotId: rateSnapshotId,
                state: .blockedInfeasible,
                infeasibleGoals: [],
                suggestions: [],
                affectedCurrencies: []
            )
        }

        let rateState = await evaluateRateSnapshot(
            for: activeGoals,
            targetCurrency: enteredBudget.currency,
            reusing: rateSnapshotId
        )
        if !rateState.affectedCurrencies.isEmpty {
            BudgetPlanAnalytics.log(.blockedRatesImpression, properties: [
                "affected_count": String(rateState.affectedCurrencies.count)
            ])
        }

        let feasibility = await checkFeasibility(
            goals: activeGoals,
            budget: enteredBudget.doubleValue,
            currency: enteredBudget.currency,
            ratesByPair: rateState.ratesByPair
        )

        let minimumCanonical = MoneyQuantizer.normalize(
            Decimal(feasibility.minimumRequired),
            currency: enteredBudget.currency,
            mode: .up
        )
        let shortfallCanonical: MoneyAmount
        if MoneyQuantizer.compare(minimumCanonical, enteredBudget) == .orderedDescending {
            shortfallCanonical = MoneyQuantizer.difference(minimumCanonical, enteredBudget)
        } else {
            shortfallCanonical = MoneyQuantizer.normalize(0, currency: enteredBudget.currency, mode: .halfUp)
        }

        let hasRates = rateState.affectedCurrencies.isEmpty
        let isFeasible = hasRates && MoneyQuantizer.compare(enteredBudget, minimumCanonical) != .orderedAscending

        let state: BudgetComputationState
        if !hasRates {
            state = .blockedRates
        } else if isFeasible {
            state = .readyFeasible
        } else {
            state = .blockedInfeasible
        }

        let plan: BudgetCalculatorPlan?
        let timeline: [ScheduledGoalBlock]
        if state == .readyFeasible {
            let computedPlan = await generateSchedule(
                goals: activeGoals,
                budget: enteredBudget.doubleValue,
                currency: enteredBudget.currency,
                ratesByPair: rateState.ratesByPair
            )
            plan = computedPlan
            timeline = buildTimelineBlocks(from: computedPlan, goals: activeGoals)
        } else {
            plan = nil
            timeline = []
        }

        let resolvedRateSnapshotId = rateState.snapshotId ?? deterministicRateSnapshotId(
            goalsSignature: goalsSignature,
            currency: enteredBudget.currency
        )

        return BudgetComputationResult(
            requestId: requestId,
            enteredBudgetCanonical: enteredBudget,
            minimumRequiredCanonical: minimumCanonical,
            shortfallCanonical: shortfallCanonical,
            isFeasible: isFeasible,
            plan: plan,
            timeline: timeline,
            rateSnapshotTimestamp: rateState.lastUpdated,
            rateSnapshotId: resolvedRateSnapshotId,
            state: state,
            infeasibleGoals: feasibility.infeasibleGoals,
            suggestions: feasibility.suggestions,
            affectedCurrencies: rateState.affectedCurrencies
        )
    }

    /// Generate the optimal contribution schedule.
    func generateSchedule(goals: [Goal], budget: Double, currency: String) async -> BudgetCalculatorPlan {
        await generateSchedule(goals: goals, budget: budget, currency: currency, ratesByPair: nil)
    }

    private func generateSchedule(
        goals: [Goal],
        budget: Double,
        currency: String,
        ratesByPair: [String: Double]?
    ) async -> BudgetCalculatorPlan {
        isCalculating = true
        defer { isCalculating = false }

        let goalIds = Set(goals.map { $0.id })
        if let cached = cachedPlan,
           cacheGoalIds == goalIds,
           abs(cacheBudget - budget) < 0.01,
           cacheCurrency == currency,
           Date().timeIntervalSince(lastCacheUpdate) < cacheExpiration {
            return cached
        }

        let activeGoals = goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }

        guard !activeGoals.isEmpty else {
            return BudgetCalculatorPlan(
                monthlyBudget: budget,
                currency: currency,
                schedule: [],
                isLeveled: true,
                minimumRequired: 0,
                goalRemainingById: [:]
            )
        }

        var goalRemaining: [UUID: Double] = [:]
        var goalNames: [UUID: String] = [:]
        for goal in activeGoals {
            var remaining = await calculateRemaining(for: goal)
            if goal.currency != currency {
                if let ratesByPair {
                    if let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] {
                        remaining *= rate
                    }
                } else if let rate = try? await exchangeRateService.fetchRate(from: goal.currency, to: currency) {
                    remaining *= rate
                }
            }
            goalRemaining[goal.id] = remaining
            goalNames[goal.id] = goal.name
        }

        guard budget > 0 else {
            let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency, ratesByPair: ratesByPair)
            return BudgetCalculatorPlan(
                monthlyBudget: budget,
                currency: currency,
                schedule: [],
                isLeveled: false,
                minimumRequired: minimumRequired,
                goalRemainingById: goalRemaining
            )
        }

        var payments: [ScheduledPayment] = []
        var paymentNumber = 1
        var paymentDate = nextPaymentDate()
        var goalRunningTotals: [UUID: Double] = [:]
        var remainingByGoal = goalRemaining

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

        let minimumRequired = await calculateMinimumBudget(goals: goals, currency: currency, ratesByPair: ratesByPair)
        let plan = BudgetCalculatorPlan(
            monthlyBudget: budget,
            currency: currency,
            schedule: payments,
            isLeveled: abs(budget - minimumRequired) < 0.01,
            minimumRequired: minimumRequired,
            goalRemainingById: goalRemaining
        )

        cachedPlan = plan
        cacheGoalIds = goalIds
        cacheBudget = budget
        cacheCurrency = currency
        lastCacheUpdate = Date()

        return plan
    }

    /// Build timeline blocks for visualization.
    func buildTimelineBlocks(from plan: BudgetCalculatorPlan, goals: [Goal]) -> [ScheduledGoalBlock] {
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
                // Calculate payment count from payment number range (not from loop increments)
                let correctPaymentCount = summary.endPayment - summary.startPayment + 1
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
                    paymentCount: correctPaymentCount
                )
            }
    }

    /// Clear the cache.
    func clearCache() {
        cachedPlan = nil
        cacheGoalIds = []
        cacheBudget = 0
        cacheCurrency = ""
        lastCacheUpdate = .distantPast
        rateSnapshotCache = [:]
    }

    // MARK: - Private Helpers

    private struct RateSnapshotState {
        let lastUpdated: Date?
        let snapshotId: String?
        let ratesByPair: [String: Double]
        let affectedCurrencies: [String]
    }

    private func calculateRemaining(for goal: Goal) async -> Double {
        let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        return max(0, goal.targetAmount - currentTotal)
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

    private func evaluateRateSnapshot(
        for goals: [Goal],
        targetCurrency: String,
        reusing preferredSnapshotId: String?
    ) async -> RateSnapshotState {
        let targetCurrencyUpper = targetCurrency.uppercased()
        let conversions = Set(goals.map { $0.currency.uppercased() }.filter { $0 != targetCurrencyUpper })
        guard !conversions.isEmpty else {
            return RateSnapshotState(lastUpdated: Date(), snapshotId: nil, ratesByPair: [:], affectedCurrencies: [])
        }

        let requiredKeys = conversions
            .sorted()
            .map { rateKey(from: $0, to: targetCurrencyUpper) }

        if let preferredSnapshotId,
           let cachedRates = rateSnapshotCache[preferredSnapshotId],
           requiredKeys.allSatisfy({ cachedRates[$0] != nil }) {
            return RateSnapshotState(
                lastUpdated: Date(),
                snapshotId: preferredSnapshotId,
                ratesByPair: cachedRates,
                affectedCurrencies: []
            )
        }

        var failed: [String] = []
        var ratesByPair: [String: Double] = [:]
        var snapshotEntries: [RateSnapshotEntry] = []
        let timestampFormatter = ISO8601DateFormatter()
        let snapshotDate = Date()
        let snapshotTimestamp = timestampFormatter.string(from: snapshotDate)

        for source in conversions.sorted() {
            do {
                let rate = try await exchangeRateService.fetchRate(from: source, to: targetCurrency)
                ratesByPair[rateKey(from: source, to: targetCurrencyUpper)] = rate
                snapshotEntries.append(
                    RateSnapshotEntry(
                        from: source,
                        to: targetCurrencyUpper,
                        rate: Decimal(rate),
                        timestampISO8601: snapshotTimestamp
                    )
                )
            } catch {
                failed.append(source)
            }
        }

        if !failed.isEmpty {
            return RateSnapshotState(lastUpdated: nil, snapshotId: nil, ratesByPair: [:], affectedCurrencies: failed.sorted())
        }

        let snapshotId = BudgetSnapshotIdentity.rateSnapshotId(fromRates: snapshotEntries)
        rateSnapshotCache[snapshotId] = ratesByPair
        return RateSnapshotState(
            lastUpdated: snapshotDate,
            snapshotId: snapshotId,
            ratesByPair: ratesByPair,
            affectedCurrencies: []
        )
    }

    private func rateKey(from: String, to: String) -> String {
        "\(from.uppercased())->\(to.uppercased())"
    }

    private func deterministicRateSnapshotId(goalsSignature: String, currency: String) -> String {
        let payload = "\(goalsSignature)|\(currency.uppercased())|no-rates"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
