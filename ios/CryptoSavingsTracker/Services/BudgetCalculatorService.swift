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
    private let now: () -> Date
    private let rateSnapshotTTL: TimeInterval

    // MARK: - Cache

    private var cachedPlan: BudgetCalculatorPlan?
    private var cacheInputSignature = ""
    private var cacheBudgetMinorUnitValue: Int64?
    private var cacheCurrency: String = ""
    private var lastCacheUpdate: Date = .distantPast
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    private var rateSnapshotCache: [String: CachedRateSnapshot] = [:]

    // MARK: - Published Properties

    @Published var isCalculating = false
    @Published var lastError: Error?

    // MARK: - Initialization

    init(
        exchangeRateService: ExchangeRateServiceProtocol,
        settings: MonthlyPlanningSettings? = nil,
        now: @escaping () -> Date = Date.init,
        rateSnapshotTTL: TimeInterval = 300
    ) {
        self.exchangeRateService = exchangeRateService
        self.settings = settings ?? MonthlyPlanningSettings.shared
        self.now = now
        self.rateSnapshotTTL = rateSnapshotTTL
    }

    // MARK: - Public API

    /// Calculate the minimum budget needed to meet all goal deadlines.
    /// Returns the MAX of all individual goal minimums (the binding constraint).
    func calculateMinimumBudget(
        goals: [Goal],
        currency: String,
        planningMonthLabel: String? = nil
    ) async -> Double {
        let planningMonthLabel = planningMonthLabel
            ?? PlanningMonthContract.storageLabel(for: now())
        let activeGoals = activeGoals(from: goals)
        guard !activeGoals.isEmpty else {
            lastError = nil
            return 0
        }

        let remainingState = await evaluateRemainingSnapshot(for: activeGoals)
        guard remainingState.isComplete else {
            lastError = remainingState.error
            return 0
        }

        let rateState = await evaluateRateSnapshot(
            for: activeGoals,
            targetCurrency: currency,
            reusing: nil
        )
        guard rateState.affectedCurrencies.isEmpty else {
            lastError = MonthlyPlanningError.currencyConversionFailed(
                rateState.affectedCurrencies.joined(separator: ", ")
            )
            return 0
        }

        lastError = nil
        return calculateMinimumBudget(
            goals: activeGoals,
            currency: currency,
            ratesByPair: rateState.ratesByPair,
            remainingByGoal: remainingState.remainingByGoal,
            planningMonthLabel: planningMonthLabel
        )
    }

    private func calculateMinimumBudget(
        goals: [Goal],
        currency: String,
        ratesByPair: [String: Double],
        remainingByGoal: [UUID: Double],
        planningMonthLabel: String
    ) -> Double {
        guard !goals.isEmpty else { return 0 }

        let activeGoals = activeGoals(from: goals)
        guard !activeGoals.isEmpty else { return 0 }

        var cumulativeRemaining: Double = 0
        var maxRequired: Double = 0

        for goal in activeGoals {
            var remaining = remainingByGoal[goal.id] ?? 0
            if goal.currency.uppercased() != currency.uppercased() {
                guard let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] else {
                    continue
                }
                remaining *= rate
            }

            if remaining <= 0 { continue }
            cumulativeRemaining += remaining

            guard let months = try? PlanningMonthContract.paymentPeriodsRemaining(
                in: planningMonthLabel,
                paymentDay: settings.paymentDay,
                deadline: goal.deadline,
                now: now()
            ) else {
                continue
            }
            let required = cumulativeRemaining / Double(months)
            maxRequired = max(maxRequired, required)
        }

        return maxRequired
    }

    /// Check if the given budget is sufficient for all goals.
    func checkFeasibility(
        goals: [Goal],
        budget: Double,
        currency: String,
        planningMonthLabel: String? = nil
    ) async -> FeasibilityResult {
        let planningMonthLabel = planningMonthLabel
            ?? PlanningMonthContract.storageLabel(for: now())
        let activeGoals = activeGoals(from: goals)
        guard !activeGoals.isEmpty else {
            lastError = nil
            return .empty
        }

        let remainingState = await evaluateRemainingSnapshot(for: activeGoals)
        guard remainingState.isComplete else {
            lastError = remainingState.error
            return .unavailable(currency: currency)
        }

        let rateState = await evaluateRateSnapshot(
            for: activeGoals,
            targetCurrency: currency,
            reusing: nil
        )
        guard rateState.affectedCurrencies.isEmpty else {
            lastError = MonthlyPlanningError.currencyConversionFailed(
                rateState.affectedCurrencies.joined(separator: ", ")
            )
            return .unavailable(currency: currency)
        }

        lastError = nil
        return checkFeasibility(
            goals: activeGoals,
            budget: budget,
            currency: currency,
            ratesByPair: rateState.ratesByPair,
            remainingByGoal: remainingState.remainingByGoal,
            planningMonthLabel: planningMonthLabel
        )
    }

    private func checkFeasibility(
        goals: [Goal],
        budget: Double,
        currency: String,
        ratesByPair: [String: Double],
        remainingByGoal: [UUID: Double],
        planningMonthLabel: String
    ) -> FeasibilityResult {
        guard !goals.isEmpty else {
            return .empty
        }

        let minimumRequired = calculateMinimumBudget(
            goals: goals,
            currency: currency,
            ratesByPair: ratesByPair,
            remainingByGoal: remainingByGoal,
            planningMonthLabel: planningMonthLabel
        )
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
                let remainingInGoalCurrency = remainingByGoal[goal.id] ?? 0
                var remaining = remainingInGoalCurrency
                var conversionRate: Double?
                if goal.currency.uppercased() != currency.uppercased() {
                    if let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] {
                        remaining *= rate
                        conversionRate = rate
                    }
                }

                if remaining <= 0 { continue }
                cumulativeRemaining += remaining

                guard let months = try? PlanningMonthContract.paymentPeriodsRemaining(
                    in: planningMonthLabel,
                    paymentDay: settings.paymentDay,
                    deadline: goal.deadline,
                    now: now()
                ) else {
                    continue
                }
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
        rateSnapshotId: String?,
        planningMonthLabel: String? = nil
    ) async -> BudgetComputationResult {
        let planningMonthLabel = planningMonthLabel
            ?? PlanningMonthContract.storageLabel(for: now())
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

        let remainingState = await evaluateRemainingSnapshot(for: activeGoals)
        guard remainingState.isComplete else {
            lastError = remainingState.error
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
                state: .blockedBalances,
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

        guard rateState.affectedCurrencies.isEmpty else {
            lastError = MonthlyPlanningError.currencyConversionFailed(
                rateState.affectedCurrencies.joined(separator: ", ")
            )
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
                state: .blockedRates,
                infeasibleGoals: [],
                suggestions: [],
                affectedCurrencies: rateState.affectedCurrencies
            )
        }

        lastError = nil
        let feasibility = checkFeasibility(
            goals: activeGoals,
            budget: enteredBudget.doubleValue,
            currency: enteredBudget.currency,
            ratesByPair: rateState.ratesByPair,
            remainingByGoal: remainingState.remainingByGoal,
            planningMonthLabel: planningMonthLabel
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

        let resolvedRateSnapshotId = rateState.snapshotId ?? deterministicRateSnapshotId(
            goalsSignature: goalsSignature,
            currency: enteredBudget.currency
        )

        let plan: BudgetCalculatorPlan?
        let timeline: [ScheduledGoalBlock]
        if state == .readyFeasible {
            let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
                goals: activeGoals,
                remainingByGoal: remainingState.remainingByGoal
            )
            let computedPlan = generateSchedule(
                goals: activeGoals,
                budget: enteredBudget.doubleValue,
                currency: enteredBudget.currency,
                ratesByPair: rateState.ratesByPair,
                remainingByGoal: remainingState.remainingByGoal,
                rateSnapshotId: resolvedRateSnapshotId,
                rateSnapshotTimestamp: rateState.lastUpdated,
                sourceStateSignature: sourceStateSignature,
                planningMonthLabel: planningMonthLabel
            )
            plan = computedPlan
            timeline = buildTimelineBlocks(from: computedPlan, goals: activeGoals)
        } else {
            plan = nil
            timeline = []
        }

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
    func generateSchedule(
        goals: [Goal],
        budget: Double,
        currency: String,
        planningMonthLabel: String? = nil
    ) async -> BudgetCalculatorPlan {
        let planningMonthLabel = planningMonthLabel
            ?? PlanningMonthContract.storageLabel(for: now())
        let activeGoals = activeGoals(from: goals)
        guard !activeGoals.isEmpty else {
            lastError = nil
            return unavailablePlan(budget: budget, currency: currency)
        }

        let remainingState = await evaluateRemainingSnapshot(for: activeGoals)
        guard remainingState.isComplete else {
            lastError = remainingState.error
            return unavailablePlan(budget: budget, currency: currency)
        }

        let rateState = await evaluateRateSnapshot(
            for: activeGoals,
            targetCurrency: currency,
            reusing: nil
        )
        guard rateState.affectedCurrencies.isEmpty else {
            lastError = MonthlyPlanningError.currencyConversionFailed(
                rateState.affectedCurrencies.joined(separator: ", ")
            )
            return unavailablePlan(budget: budget, currency: currency)
        }

        let goalsSignature = BudgetSnapshotIdentity.goalsSignature(
            goals: activeGoals,
            skippedGoalIds: []
        )
        let resolvedRateSnapshotId = rateState.snapshotId ?? deterministicRateSnapshotId(
            goalsSignature: goalsSignature,
            currency: currency
        )
        let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: activeGoals,
            remainingByGoal: remainingState.remainingByGoal
        )

        lastError = nil
        return generateSchedule(
            goals: activeGoals,
            budget: budget,
            currency: currency,
            ratesByPair: rateState.ratesByPair,
            remainingByGoal: remainingState.remainingByGoal,
            rateSnapshotId: resolvedRateSnapshotId,
            rateSnapshotTimestamp: rateState.lastUpdated,
            sourceStateSignature: sourceStateSignature,
            planningMonthLabel: planningMonthLabel
        )
    }

    private func generateSchedule(
        goals: [Goal],
        budget: Double,
        currency: String,
        ratesByPair: [String: Double],
        remainingByGoal: [UUID: Double],
        rateSnapshotId: String,
        rateSnapshotTimestamp: Date?,
        sourceStateSignature: String,
        planningMonthLabel: String
    ) -> BudgetCalculatorPlan {
        isCalculating = true
        defer { isCalculating = false }

        let canonicalBudget = MoneyQuantizer.normalize(
            Decimal(budget),
            currency: currency,
            mode: .halfUp
        )
        let canonicalBudgetValue = canonicalBudget.doubleValue
        let canonicalCurrency = canonicalBudget.currency.uppercased()
        let activeGoals = goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }

        guard !activeGoals.isEmpty else {
            return BudgetCalculatorPlan(
                monthlyBudget: budget,
                currency: canonicalCurrency,
                schedule: [],
                isLeveled: true,
                minimumRequired: 0,
                goalRemainingById: [:],
                rateSnapshotId: rateSnapshotId,
                rateSnapshotTimestamp: rateSnapshotTimestamp,
                applicationRatesByPair: [:],
                sourceStateSignature: sourceStateSignature
            )
        }

        var goalRemaining: [UUID: Double] = [:]
        var goalNames: [UUID: String] = [:]
        for goal in activeGoals {
            var remaining = remainingByGoal[goal.id] ?? 0
            if goal.currency.uppercased() != currency.uppercased() {
                if let rate = ratesByPair[rateKey(from: goal.currency, to: currency)] {
                    remaining *= rate
                }
            }
            goalRemaining[goal.id] = remaining
            goalNames[goal.id] = goal.name
        }

        let inputSignature = scheduleInputSignature(
            goals: activeGoals,
            remainingByGoal: goalRemaining
        ) + "|month:\(planningMonthLabel)"
        let applicationRatesByPair = makeApplicationRates(
            goals: activeGoals,
            budgetCurrency: canonicalCurrency,
            ratesByPair: ratesByPair
        )
        if let cached = cachedPlan,
           cacheInputSignature == inputSignature,
           cacheBudgetMinorUnitValue == canonicalBudget.minorUnitValue,
           cacheCurrency == canonicalCurrency,
           cached.rateSnapshotId == rateSnapshotId,
           cached.rateSnapshotTimestamp == rateSnapshotTimestamp,
           cached.sourceStateSignature == sourceStateSignature,
           now().timeIntervalSince(lastCacheUpdate) < cacheExpiration {
            return cached
        }

        guard canonicalBudget.minorUnitValue > 0 else {
            let minimumRequired = calculateMinimumBudget(
                goals: goals,
                currency: currency,
                ratesByPair: ratesByPair,
                remainingByGoal: remainingByGoal,
                planningMonthLabel: planningMonthLabel
            )
            return BudgetCalculatorPlan(
                monthlyBudget: canonicalBudgetValue,
                currency: canonicalCurrency,
                schedule: [],
                isLeveled: false,
                minimumRequired: minimumRequired,
                goalRemainingById: goalRemaining,
                rateSnapshotId: rateSnapshotId,
                rateSnapshotTimestamp: rateSnapshotTimestamp,
                applicationRatesByPair: applicationRatesByPair,
                sourceStateSignature: sourceStateSignature
            )
        }

        var payments: [ScheduledPayment] = []
        var paymentNumber = 1
        guard var paymentDate = try? PlanningMonthContract.nextPaymentDate(
            in: planningMonthLabel,
            paymentDay: settings.paymentDay,
            now: now()
        ) else {
            return unavailablePlan(budget: canonicalBudgetValue, currency: canonicalCurrency)
        }
        var goalRunningTotals: [UUID: Double] = [:]
        var scheduleRemainingByGoal = goalRemaining

        for goal in activeGoals {
            goalRunningTotals[goal.id] = 0
        }

        var safetyCounter = 0
        while scheduleRemainingByGoal.values.contains(where: { $0 > 0.01 }) && safetyCounter < 600 {
            safetyCounter += 1
            let startTotals = goalRunningTotals
            var paymentAllocations: [UUID: Double] = [:]
            var remainingBudget = canonicalBudgetValue

            for goal in activeGoals {
                guard paymentDate <= goal.deadline else { continue }
                let remaining = scheduleRemainingByGoal[goal.id] ?? 0
                guard remaining > 0.01 else { continue }
                let amount = min(remainingBudget, remaining)
                guard amount > 0.01 else { continue }
                paymentAllocations[goal.id, default: 0] += amount
                goalRunningTotals[goal.id, default: 0] += amount
                scheduleRemainingByGoal[goal.id, default: 0] = max(0, remaining - amount)
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
                let isComplete = (scheduleRemainingByGoal[goal.id] ?? 0) <= 0.01

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
            paymentDate = PlanningMonthContract.addingOneMonth(to: paymentDate) ?? paymentDate
        }

        let minimumRequired = calculateMinimumBudget(
            goals: goals,
            currency: currency,
            ratesByPair: ratesByPair,
            remainingByGoal: remainingByGoal,
            planningMonthLabel: planningMonthLabel
        )
        let plan = BudgetCalculatorPlan(
            monthlyBudget: canonicalBudgetValue,
            currency: canonicalCurrency,
            schedule: payments,
            isLeveled: MoneyQuantizer.minorUnitValue(
                for: Decimal(canonicalBudgetValue - minimumRequired),
                currency: canonicalCurrency
            ) == 0,
            minimumRequired: minimumRequired,
            goalRemainingById: goalRemaining,
            rateSnapshotId: rateSnapshotId,
            rateSnapshotTimestamp: rateSnapshotTimestamp,
            applicationRatesByPair: applicationRatesByPair,
            sourceStateSignature: sourceStateSignature
        )

        cachedPlan = plan
        cacheInputSignature = inputSignature
        cacheBudgetMinorUnitValue = canonicalBudget.minorUnitValue
        cacheCurrency = canonicalCurrency
        lastCacheUpdate = now()

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
        cacheInputSignature = ""
        cacheBudgetMinorUnitValue = nil
        cacheCurrency = ""
        lastCacheUpdate = .distantPast
        rateSnapshotCache = [:]
    }

    /// Force the next budget computation to fetch a fresh FX snapshot.
    func invalidateRateSnapshots() {
        clearCache()
    }

    /// Whether a computed rate snapshot is still eligible for Apply.
    func isRateSnapshotFresh(timestamp: Date?) -> Bool {
        guard let timestamp else { return false }
        let age = now().timeIntervalSince(timestamp)
        return age >= 0 && age < rateSnapshotTTL
    }

    // MARK: - Private Helpers

    private struct RateSnapshotState {
        let lastUpdated: Date?
        let snapshotId: String?
        let ratesByPair: [String: Double]
        let affectedCurrencies: [String]
    }

    private struct CachedRateSnapshot {
        let ratesByPair: [String: Double]
        let fetchedAt: Date
    }

    private struct RemainingSnapshotState {
        let remainingByGoal: [UUID: Double]
        let error: Error?

        var isComplete: Bool {
            error == nil
        }
    }

    private func activeGoals(from goals: [Goal]) -> [Goal] {
        goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { $0.deadline < $1.deadline }
    }

    private func evaluateRemainingSnapshot(for goals: [Goal]) async -> RemainingSnapshotState {
        var remainingByGoal: [UUID: Double] = [:]

        for goal in goals {
            let currentTotalResult = await GoalCalculationService.getCurrentTotalResult(for: goal)
            guard currentTotalResult.isComplete else {
                return RemainingSnapshotState(
                    remainingByGoal: [:],
                    error: MonthlyPlanningError.calculationFailed(
                        "Current balance is unavailable for \(goal.name). Refresh balances and retry."
                    )
                )
            }
            remainingByGoal[goal.id] = max(0, goal.targetAmount - currentTotalResult.total)
        }

        return RemainingSnapshotState(remainingByGoal: remainingByGoal, error: nil)
    }

    private func unavailablePlan(budget: Double, currency: String) -> BudgetCalculatorPlan {
        BudgetCalculatorPlan(
            monthlyBudget: budget,
            currency: currency,
            schedule: [],
            isLeveled: false,
            minimumRequired: 0,
            goalRemainingById: [:]
        )
    }

    private func evaluateRateSnapshot(
        for goals: [Goal],
        targetCurrency: String,
        reusing preferredSnapshotId: String?
    ) async -> RateSnapshotState {
        let targetCurrencyUpper = targetCurrency.uppercased()
        let conversions = Set(goals.map { $0.currency.uppercased() }.filter { $0 != targetCurrencyUpper })
        guard !conversions.isEmpty else {
            return RateSnapshotState(lastUpdated: now(), snapshotId: nil, ratesByPair: [:], affectedCurrencies: [])
        }

        let requiredKeys = conversions
            .sorted()
            .map { rateKey(from: $0, to: targetCurrencyUpper) }

        if let preferredSnapshotId,
           let cachedSnapshot = rateSnapshotCache[preferredSnapshotId] {
            let age = now().timeIntervalSince(cachedSnapshot.fetchedAt)
            if age >= 0,
               age < rateSnapshotTTL,
               requiredKeys.allSatisfy({ cachedSnapshot.ratesByPair[$0] != nil }) {
                return RateSnapshotState(
                    lastUpdated: cachedSnapshot.fetchedAt,
                    snapshotId: preferredSnapshotId,
                    ratesByPair: cachedSnapshot.ratesByPair,
                    affectedCurrencies: []
                )
            }
            rateSnapshotCache.removeValue(forKey: preferredSnapshotId)
        }

        var failed: [String] = []
        var ratesByPair: [String: Double] = [:]
        var snapshotEntries: [RateSnapshotEntry] = []
        let timestampFormatter = ISO8601DateFormatter()
        let snapshotDate = now()
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
        rateSnapshotCache[snapshotId] = CachedRateSnapshot(
            ratesByPair: ratesByPair,
            fetchedAt: snapshotDate
        )
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

    private func makeApplicationRates(
        goals: [Goal],
        budgetCurrency: String,
        ratesByPair: [String: Double]
    ) -> [String: Double] {
        let canonicalBudgetCurrency = budgetCurrency.uppercased()
        let goalCurrencies = Set(
            goals
                .map { $0.currency.uppercased() }
                .filter { $0 != canonicalBudgetCurrency }
        )

        return goalCurrencies.reduce(into: [:]) { result, goalCurrency in
            guard let sourceToBudgetRate = ratesByPair[
                rateKey(from: goalCurrency, to: canonicalBudgetCurrency)
            ],
            sourceToBudgetRate.isFinite,
            sourceToBudgetRate > 0 else {
                return
            }
            result[rateKey(from: canonicalBudgetCurrency, to: goalCurrency)] = 1 / sourceToBudgetRate
        }
    }

    private func scheduleInputSignature(
        goals: [Goal],
        remainingByGoal: [UUID: Double]
    ) -> String {
        let goalsCanonical = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { goal in
                let remaining = remainingByGoal[goal.id] ?? 0
                return [
                    goal.id.uuidString,
                    goal.name,
                    goal.currency.uppercased(),
                    goal.emoji ?? "",
                    String(goal.targetAmount.bitPattern),
                    String(goal.deadline.timeIntervalSinceReferenceDate.bitPattern),
                    String(remaining.bitPattern)
                ].joined(separator: "|")
            }
            .joined(separator: ";")
        let canonical = "paymentDay=\(settings.paymentDay);\(goalsCanonical)"
        return BudgetSnapshotIdentity.sha256(canonical)
    }

    private func deterministicRateSnapshotId(goalsSignature: String, currency: String) -> String {
        let payload = "\(goalsSignature)|\(currency.uppercased())|no-rates"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
