//
//  MonthlyPlanService.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Unified Monthly Planning Architecture
//  Single source of truth for monthly plan management with duplicate prevention
//

import SwiftData
import Foundation

@MainActor
final class MonthlyPlanService {
    let modelContext: ModelContext
    let goalCalculationService: GoalCalculationService
    // Shared executor so multiple service instances (via DI) still serialize critical sections
    private static let sharedExecutor = AsyncSerialExecutor()

    init(modelContext: ModelContext, goalCalculationService: GoalCalculationService) {
        self.modelContext = modelContext
        self.goalCalculationService = goalCalculationService
    }

    // MARK: - Plan Creation with Duplicate Prevention

    /// Get existing plans OR create new ones for current month (with duplicate prevention)
    /// This is the main entry point - ensures only one set of plans exists per month
    /// Uses AsyncSerialExecutor to prevent race conditions during concurrent access
    func getOrCreatePlansForCurrentMonth(goals: [Goal]) async throws -> [MonthlyPlan] {
        return try await Self.sharedExecutor.enqueue {
            let monthLabel = self.currentMonthLabel()

            // GUARD 1: Check if ANY plans exist for this month (any state)
            let existingPlans = try self.fetchPlans(for: monthLabel, state: nil)

            if !existingPlans.isEmpty {
                AppLog.info("Found \(existingPlans.count) existing plans for \(monthLabel)", category: .monthlyPlanning)

                // Check if we need to create plans for new goals
                let existingGoalIds = Set(existingPlans.map { $0.goalId })
                let currentGoalIds = Set(goals.map { $0.id })
                let missingGoalIds = currentGoalIds.subtracting(existingGoalIds)

                if !missingGoalIds.isEmpty {
                    AppLog.info("Creating plans for \(missingGoalIds.count) new goals", category: .monthlyPlanning)
                    let missingGoals = goals.filter { missingGoalIds.contains($0.id) }
                    let newPlans = try await self.createPlansFor(goals: missingGoals, monthLabel: monthLabel)
                    return existingPlans + newPlans
                }

                return existingPlans
            }

            // Only create if NO plans exist
            return try await self.createPlansFor(goals: goals, monthLabel: monthLabel)
        }
    }

    /// Create plans for specific goals in specific month (with individual duplicate checks)
    private func createPlansFor(goals: [Goal], monthLabel: String) async throws -> [MonthlyPlan] {
        var plans: [MonthlyPlan] = []

        for goal in goals {
            // GUARD 2: Check if plan already exists for this (goal, month)
            if let existingPlan = try fetchPlan(for: goal.id, in: monthLabel) {
                AppLog.warning("Plan already exists for goal \(goal.name) in \(monthLabel), skipping creation", category: .monthlyPlanning)
                plans.append(existingPlan)
                continue
            }

            // Safe to create
            let requirement = await calculateRequirement(for: goal, in: monthLabel)
            let plan = MonthlyPlan(
                goalId: goal.id,
                monthLabel: monthLabel,
                requiredMonthly: requirement.requiredMonthly,
                remainingAmount: requirement.remainingAmount,
                monthsRemaining: requirement.monthsRemaining,
                currency: goal.currency,
                status: requirement.status,
                state: .draft
            )
            modelContext.insert(plan)
            plans.append(plan)

        }

        try modelContext.save()
        AppLog.info("Created \(plans.count) new plans for \(monthLabel)", category: .monthlyPlanning)
        return plans
    }

    // MARK: - Plan Calculation (Asset-Only - CORRECT)

    /// Calculate monthly requirement using ASSET-ONLY totals (no double-counting)
    /// Contributions are tracked separately for monthly plan fulfillment
    private func calculateRequirement(for goal: Goal, in monthLabel: String) async -> MonthlyRequirement {
        // Goal total = ASSETS ONLY (crypto holdings at current prices)
        // This is the CORRECT calculation - contributions are NOT added
        let currentTotal = await goalCalculationService.getCurrentTotal(for: goal)

        let remaining = max(0, goal.targetAmount - currentTotal)

        // Calculate months left
        let calendar = Calendar.current
        let now = Date()
        let monthsLeft = max(1, calendar.dateComponents([.month], from: now, to: goal.deadline).month ?? 1)

        let monthlyAmount = remaining / Double(monthsLeft)

        // Determine status
        let status: RequirementStatus
        if remaining <= 0 {
            status = .completed
        } else if monthlyAmount > 10000 {
            status = .critical
        } else if monthlyAmount > 5000 || monthsLeft <= 1 {
            status = .attention
        } else {
            status = .onTrack
        }

        let progress = goal.targetAmount > 0 ? min(currentTotal / goal.targetAmount, 1.0) : 0.0

        return MonthlyRequirement(
            goalId: goal.id,
            goalName: goal.name,
            currency: goal.currency,
            targetAmount: goal.targetAmount,
            currentTotal: currentTotal,
            remainingAmount: remaining,
            monthsRemaining: monthsLeft,
            requiredMonthly: monthlyAmount,
            progress: progress,
            deadline: goal.deadline,
            status: status
        )
    }

    // MARK: - Plan Fetching

    /// Fetch plans for specific month (with optional state filter)
    func fetchPlans(for monthLabel: String, state: MonthlyPlan.PlanState? = nil) throws -> [MonthlyPlan] {
        if let state = state {
            // Filter by state
            let predicate = #Predicate<MonthlyPlan> { plan in
                plan.monthLabel == monthLabel && plan.stateRawValue == state.rawValue
            }
            let descriptor = FetchDescriptor<MonthlyPlan>(predicate: predicate)
            return try modelContext.fetch(descriptor)
        } else {
            // All states
            let predicate = #Predicate<MonthlyPlan> { plan in
                plan.monthLabel == monthLabel
            }
            let descriptor = FetchDescriptor<MonthlyPlan>(predicate: predicate)
            return try modelContext.fetch(descriptor)
        }
    }

    /// Fetch specific plan by goal and month
    func fetchPlan(for goalId: UUID, in monthLabel: String) throws -> MonthlyPlan? {
        let predicate = #Predicate<MonthlyPlan> { plan in
            plan.goalId == goalId && plan.monthLabel == monthLabel
        }
        let descriptor = FetchDescriptor<MonthlyPlan>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    /// Fetch current month's plans (all states by default)
    func fetchCurrentMonthPlans(state: MonthlyPlan.PlanState? = nil) throws -> [MonthlyPlan] {
        return try fetchPlans(for: currentMonthLabel(), state: state)
    }

    /// Fetch only draft plans for current month
    func fetchCurrentMonthDraftPlans() throws -> [MonthlyPlan] {
        return try fetchPlans(for: currentMonthLabel(), state: .draft)
    }

    // MARK: - Plan Updates (Incremental)

    /// Update plan with new calculation while preserving user preferences
    func updatePlan(_ plan: MonthlyPlan, withGoal goal: Goal) async throws {
        let requirement = await calculateRequirement(for: goal, in: plan.monthLabel)

        // Preserve user overrides (customAmount, flexState, isSkipped)
        plan.updateCalculation(
            requiredMonthly: requirement.requiredMonthly,
            remainingAmount: requirement.remainingAmount,
            monthsRemaining: requirement.monthsRemaining,
            status: requirement.status
        )

        try modelContext.save()
    }

    /// Update custom amount for a plan
    func setCustomAmount(_ amount: Double?, for plan: MonthlyPlan) throws {
        plan.setCustomAmount(amount)
        try modelContext.save()
    }

    /// Toggle protection status
    func toggleProtection(for plan: MonthlyPlan) throws {
        plan.toggleProtection()
        try modelContext.save()
    }

    /// Skip or unskip a plan
    func skipPlan(_ plan: MonthlyPlan, skip: Bool = true) throws {
        plan.skipThisMonth(skip)
        try modelContext.save()
    }

    // MARK: - Plan Lifecycle State Transitions

    /// Transition plans from draft to executing
    func startExecution(for plans: [MonthlyPlan]) throws {
        for plan in plans {
            guard plan.state == .draft else {
                AppLog.warning("Cannot start execution for plan in state: \(plan.state.displayName)", category: .monthlyPlanning)
                continue
            }
            plan.state = .executing
        }
        try modelContext.save()
        AppLog.info("Started execution for \(plans.count) plans", category: .monthlyPlanning)
    }

    /// Transition plans from executing to completed
    func completePlans(for plans: [MonthlyPlan]) throws {
        for plan in plans {
            guard plan.state == .executing else {
                AppLog.warning("Cannot complete plan in state: \(plan.state.displayName)", category: .monthlyPlanning)
                continue
            }
            plan.state = .completed
        }
        try modelContext.save()
        AppLog.info("Completed \(plans.count) plans", category: .monthlyPlanning)
    }

    /// Update totalContributed for a plan (called when contributions are added)
    func updateContributionTotal(for plan: MonthlyPlan) throws {
        let contributions = plan.contributions ?? []
        plan.totalContributed = contributions.reduce(0) { $0 + $1.amount }
        try modelContext.save()
    }

    // MARK: - Helper Methods

    /// Get current month label (yyyy-MM format)
    func currentMonthLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    /// Delete a plan (use with caution)
    func deletePlan(_ plan: MonthlyPlan) throws {
        modelContext.delete(plan)
        try modelContext.save()
    }

    /// Get plan summary for display
    func getPlanSummary(for monthLabel: String) throws -> PlanSummary {
        let plans = try fetchPlans(for: monthLabel)

        let totalRequired = plans.reduce(0) { $0 + $1.effectiveAmount }
        let totalContributed = plans.reduce(0) { $0 + $1.totalContributed }
        let fulfilledCount = plans.filter { $0.totalContributed >= $0.effectiveAmount }.count
        let skippedCount = plans.filter { $0.isSkipped }.count

        return PlanSummary(
            monthLabel: monthLabel,
            totalPlans: plans.count,
            totalRequired: totalRequired,
            totalContributed: totalContributed,
            fulfilledCount: fulfilledCount,
            skippedCount: skippedCount,
            activeCount: plans.count - skippedCount
        )
    }

    // MARK: - Bulk Flex Adjustment

    /// Apply flex adjustment to multiple plans with proper state management
    /// This is the single source of truth for flex application
    func applyBulkFlexAdjustment(
        plans: [MonthlyPlan],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>
    ) async throws {

        // Use serial executor to ensure atomicity
        try await Self.sharedExecutor.enqueue { [weak self] in
            guard let self = self else { return }

            // Validate all plans are in draft state
            let nonDraftPlans = plans.filter { $0.state != .draft }
            guard nonDraftPlans.isEmpty else {
                let goalIds = nonDraftPlans.map { $0.goalId.uuidString }.joined(separator: ", ")
                throw PlanError.invalidState("Can only adjust draft plans. Non-draft plans: \(goalIds)")
            }

            // Categorize and update plans
            for plan in plans {
                if skippedGoalIds.contains(plan.goalId) {
                    // Mark as skipped
                    plan.skipThisMonth(true)
                } else if protectedGoalIds.contains(plan.goalId) {
                    // Mark as protected
                    if plan.flexState != .protected {
                        plan.toggleProtection()
                    }
                    // Protected plans keep their original requiredMonthly or user override
                    // Do not clear customAmount to preserve user-entered overrides
                } else {
                    // Flexible plan - apply adjustment
                    plan.flexState = .flexible
                    let adjustedAmount = plan.requiredMonthly * adjustment

                    // Validation: no zero or negative amounts
                    guard adjustedAmount > 0 else {
                        throw PlanError.invalidAmount("Adjusted amount must be positive for goal \(plan.goalId)")
                    }

                    plan.setCustomAmount(adjustedAmount)
                }
            }

            // Save all changes
            try self.modelContext.save()

            let flexibleCount = plans.filter { !protectedGoalIds.contains($0.goalId) && !skippedGoalIds.contains($0.goalId) }.count
            AppLog.info("Applied flex adjustment (\(Int(adjustment * 100))%) to \(flexibleCount) flexible plans",
                        category: .monthlyPlanning)
        }
    }

    /// Validate plans before state transition to execution
    func validatePlansForExecution(_ plans: [MonthlyPlan]) throws {
        var errors: [String] = []

        for plan in plans {
            // Check state
            if plan.state != .draft {
                errors.append("Plan for goal \(plan.goalId) is not in draft state (current: \(plan.state.displayName))")
            }

            // Check amounts for non-skipped plans
            if !plan.isSkipped && plan.effectiveAmount <= 0 {
                errors.append("Plan for goal \(plan.goalId) has zero or negative effective amount: \(plan.effectiveAmount)")
            }

            // Check month label
            if plan.monthLabel.isEmpty {
                errors.append("Plan for goal \(plan.goalId) has empty month label")
            }
        }

        if !errors.isEmpty {
            throw PlanError.validationFailed(errors.joined(separator: "; "))
        }

    }
}

// MARK: - Supporting Types

enum PlanError: LocalizedError {
    case invalidState(String)
    case invalidAmount(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid plan state: \(message)"
        case .invalidAmount(let message):
            return "Invalid amount: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

struct PlanSummary {
    let monthLabel: String
    let totalPlans: Int
    let totalRequired: Double
    let totalContributed: Double
    let fulfilledCount: Int
    let skippedCount: Int
    let activeCount: Int

    var progress: Double {
        guard totalRequired > 0 else { return 1.0 }
        return min(totalContributed / totalRequired, 1.0)
    }

    var isComplete: Bool {
        return fulfilledCount == activeCount
    }
}
