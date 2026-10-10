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
    private let saveChanges: () throws -> Void
    private let now: () -> Date
    private let planDeletionFetchByIDs: (ModelContext, [UUID]) throws -> [MonthlyPlan]
    // Shared executor so multiple service instances (via DI) still serialize critical sections
    private static let sharedExecutor = AsyncSerialExecutor()

    init(
        modelContext: ModelContext,
        goalCalculationService: GoalCalculationService,
        saveChanges: (() throws -> Void)? = nil,
        now: @escaping () -> Date = Date.init,
        planDeletionFetchByIDs: ((
            ModelContext,
            [UUID]
        ) throws -> [MonthlyPlan])? = nil
    ) {
        self.modelContext = modelContext
        self.goalCalculationService = goalCalculationService
        self.now = now
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.planDeletionFetchByIDs = planDeletionFetchByIDs ?? { context, ids in
            let planIDs = ids
            let descriptor = FetchDescriptor<MonthlyPlan>(
                predicate: #Predicate<MonthlyPlan> { candidate in
                    planIDs.contains(candidate.id)
                }
            )
            return try context.fetch(descriptor)
        }
    }

    // MARK: - Plan Creation with Duplicate Prevention

    /// Get existing plans OR create new ones for current month (with duplicate prevention)
    /// This is the main entry point - ensures only one set of plans exists per month
    /// Uses AsyncSerialExecutor to prevent race conditions during concurrent access
    func getOrCreatePlansForCurrentMonth(goals: [Goal]) async throws -> [MonthlyPlan] {
        let monthLabel = currentMonthLabel()
        return try await getOrCreatePlans(for: monthLabel, goals: goals)
    }

    /// Get existing plans OR create new ones for a specific month (with duplicate prevention)
    /// Uses AsyncSerialExecutor to prevent race conditions during concurrent access
    func getOrCreatePlans(for monthLabel: String, goals: [Goal]) async throws -> [MonthlyPlan] {
        let sourceFingerprint = MonthlyPlanFinancialSourceFingerprint(goals: goals)
        return try await Self.sharedExecutor.enqueue {
            let activeGoals = goals.filter { $0.lifecycleStatus == .active }
            let activeGoalIDs = Set(activeGoals.map(\.id))

            // GUARD 1: Check if ANY plans exist for this month (any state)
            let existingPlans = try self.fetchPlans(for: monthLabel, state: nil)

            if !existingPlans.isEmpty {
                AppLog.info("Found \(existingPlans.count) existing plans for \(monthLabel)", category: .monthlyPlanning)
                let activeExistingPlans = existingPlans.filter {
                    activeGoalIDs.contains($0.goalId)
                }

                // Recalculate draft plans to ensure they reflect current allocation state.
                // Without this, plans created before an allocation was deleted would show
                // stale remainingAmount/requiredMonthly values.
                var recalculations: [(plan: MonthlyPlan, requirement: MonthlyRequirement)] = []
                var financialValidations: [
                    (goal: Goal, evidence: GoalFinancialInputEvidence?)
                ] = []
                for plan in activeExistingPlans where plan.state == .draft {
                    guard let goal = activeGoals.first(where: { $0.id == plan.goalId }) else {
                        continue
                    }
                    let calculation = try await self.calculateRequirement(
                        for: goal,
                        in: monthLabel
                    )
                    recalculations.append((plan, calculation.requirement))
                    financialValidations.append((goal, calculation.financialInputEvidence))
                }

                let existingGoalIds = Set(activeExistingPlans.map(\.goalId))
                let currentGoalIds = Set(activeGoals.map(\.id))
                let missingGoalIds = currentGoalIds.subtracting(existingGoalIds)
                let missingGoals = activeGoals.filter { missingGoalIds.contains($0.id) }
                var missingRequirements: [(goal: Goal, requirement: MonthlyRequirement)] = []
                for goal in missingGoals {
                    let calculation = try await self.calculateRequirement(
                        for: goal,
                        in: monthLabel
                    )
                    missingRequirements.append((goal, calculation.requirement))
                    financialValidations.append((goal, calculation.financialInputEvidence))
                }

                guard !recalculations.isEmpty || !missingRequirements.isEmpty else {
                    return activeExistingPlans
                }

                let recalculationSnapshots = recalculations.map {
                    MonthlyPlanMutationSnapshot(plan: $0.plan)
                }
                var insertedPlans: [MonthlyPlan] = []
                try sourceFingerprint.assertMatches(goals: goals)
                try self.assertFinancialInputsAreCurrent(financialValidations)
                return try PersistenceOperationTransaction.perform(
                    in: self.modelContext,
                    saveChanges: self.saveChanges,
                    allowingPreexistingChangesTo: recalculations.map(\.plan),
                    restoreTouchedState: {
                        recalculationSnapshots.forEach { $0.restore() }
                        PersistenceOperationTransaction.discardInserted(
                            insertedPlans,
                            from: self.modelContext
                        )
                    }
                ) {
                    for (plan, requirement) in recalculations {
                        plan.updateCalculation(
                            requiredMonthly: requirement.requiredMonthly,
                            remainingAmount: requirement.remainingAmount,
                            monthsRemaining: requirement.monthsRemaining,
                            status: requirement.status
                        )
                    }

                    if !missingRequirements.isEmpty {
                        AppLog.info(
                            "Creating plans for \(missingGoalIds.count) new goals",
                            category: .monthlyPlanning
                        )
                        for (goal, requirement) in missingRequirements {
                            let plan = self.makePlan(
                                for: goal,
                                monthLabel: monthLabel,
                                requirement: requirement
                            )
                            self.modelContext.insert(plan)
                            insertedPlans.append(plan)
                        }
                    }

                    return activeExistingPlans + insertedPlans
                }
            }

            // Only create if NO plans exist
            return try await self.createPlansFor(
                goals: activeGoals,
                monthLabel: monthLabel,
                sourceFingerprint: sourceFingerprint,
                validationGoals: goals
            )
        }
    }

    /// Roll forward stale draft plans to the target month when no execution is active.
    /// Returns true if any plans were moved or merged.
    func rollForwardDraftPlans(to targetMonthLabel: String) async throws -> Bool {
        return try await Self.sharedExecutor.enqueue {
            let predicate = #Predicate<MonthlyPlan> { plan in
                plan.stateRawValue == "draft" && plan.monthLabel < targetMonthLabel
            }
            let stalePlans = try self.modelContext.fetch(FetchDescriptor<MonthlyPlan>(predicate: predicate))
            guard !stalePlans.isEmpty else { return false }
            let activeGoalIDs = try self.fetchActiveGoalIDs()

            let targetPlans = try self.fetchPlans(for: targetMonthLabel, state: nil)
            var targetByGoal: [UUID: MonthlyPlan] = [:]
            for plan in targetPlans {
                targetByGoal[plan.goalId] = plan
            }

            let snapshots = (stalePlans + targetPlans).map(MonthlyPlanMutationSnapshot.init)
            let affectedGoalIDs = Set(stalePlans.map(\.goalId))
            let didChange = try PersistenceOperationTransaction.perform(
                in: self.modelContext,
                saveChanges: self.saveChanges,
                allowingPreexistingChangesTo: stalePlans + targetPlans,
                restoreTouchedState: {
                    snapshots.forEach { $0.restore(in: self.modelContext) }
                }
            ) {
                var didChange = false
                for stale in stalePlans.sorted(by: {
                    if $0.lastModifiedDate == $1.lastModifiedDate {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.lastModifiedDate < $1.lastModifiedDate
                }) {
                    guard activeGoalIDs.contains(stale.goalId) else {
                        self.modelContext.delete(stale)
                        didChange = true
                        continue
                    }
                    if let target = targetByGoal[stale.goalId] {
                        if stale.lastModifiedDate > target.lastModifiedDate {
                            target.customAmount = stale.customAmount
                            target.isProtected = stale.isProtected
                            target.isSkipped = stale.isSkipped
                            target.flexState = stale.flexState
                            target.lastModifiedDate = stale.lastModifiedDate
                        }
                        self.modelContext.delete(stale)
                        didChange = true
                    } else {
                        stale.monthLabel = targetMonthLabel
                        targetByGoal[stale.goalId] = stale
                        didChange = true
                    }
                }
                return didChange
            }
            self.postSharedGoalDataDidChange(goalIDs: affectedGoalIDs)
            return didChange
        }
    }

    /// Create plans for specific goals in specific month (with individual duplicate checks)
    private func createPlansFor(
        goals: [Goal],
        monthLabel: String,
        sourceFingerprint: MonthlyPlanFinancialSourceFingerprint,
        validationGoals: [Goal]
    ) async throws -> [MonthlyPlan] {
        var plans: [MonthlyPlan] = []
        var plansToCreate: [(goal: Goal, requirement: MonthlyRequirement)] = []
        var financialValidations: [
            (goal: Goal, evidence: GoalFinancialInputEvidence?)
        ] = []

        for goal in goals {
            // GUARD 2: Check if plan already exists for this (goal, month)
            if let existingPlan = try fetchPlan(for: goal.id, in: monthLabel) {
                AppLog.warning("Plan already exists for goal \(goal.name) in \(monthLabel), skipping creation", category: .monthlyPlanning)
                plans.append(existingPlan)
                continue
            }

            let calculation = try await calculateRequirement(for: goal, in: monthLabel)
            plansToCreate.append((goal, calculation.requirement))
            financialValidations.append((goal, calculation.financialInputEvidence))
        }

        guard !plansToCreate.isEmpty else { return plans }
        try sourceFingerprint.assertMatches(goals: validationGoals)
        try assertFinancialInputsAreCurrent(financialValidations)
        let newPlans = plansToCreate.map { entry in
            makePlan(for: entry.goal, monthLabel: monthLabel, requirement: entry.requirement)
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [],
            restoreTouchedState: {
                PersistenceOperationTransaction.discardInserted(newPlans, from: modelContext)
            }
        ) {
            for plan in newPlans {
                modelContext.insert(plan)
            }
        }
        plans.append(contentsOf: newPlans)
        AppLog.info("Created \(plans.count) new plans for \(monthLabel)", category: .monthlyPlanning)
        return plans
    }

    // MARK: - Plan Calculation (Asset-Only - CORRECT)

    /// Calculate monthly requirement using ASSET-ONLY totals (no double-counting)
    /// Contributions are tracked separately for monthly plan fulfillment
    private func calculateRequirement(
        for goal: Goal,
        in monthLabel: String
    ) async throws -> (
        requirement: MonthlyRequirement,
        financialInputEvidence: GoalFinancialInputEvidence?
    ) {
        // Goal total = ASSETS ONLY (crypto holdings at current prices)
        // This is the CORRECT calculation - contributions are NOT added
        let currentTotalResult = await goalCalculationService.getCurrentTotalResult(for: goal)
        guard currentTotalResult.isComplete else {
            throw PlanError.dataUnavailable(
                "Current balance is unavailable for \(goal.name). Refresh balances and retry."
            )
        }
        let currentTotal = currentTotalResult.total

        let remaining = max(0, goal.targetAmount - currentTotal)

        // Calculate payment periods remaining (uses payment day from settings)
        let monthsLeft = try calculatePaymentPeriodsRemaining(
            in: monthLabel,
            until: goal.deadline
        )

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

        let requirement = MonthlyRequirement(
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
        return (requirement, currentTotalResult.financialInputEvidence)
    }

    private func makePlan(
        for goal: Goal,
        monthLabel: String,
        requirement: MonthlyRequirement
    ) -> MonthlyPlan {
        MonthlyPlan(
            goalId: goal.id,
            monthLabel: monthLabel,
            requiredMonthly: requirement.requiredMonthly,
            remainingAmount: requirement.remainingAmount,
            monthsRemaining: requirement.monthsRemaining,
            currency: goal.currency,
            status: requirement.status,
            state: .draft
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
        let sourceFingerprint = MonthlyPlanFinancialSourceFingerprint(goals: [goal])
        let calculation = try await calculateRequirement(for: goal, in: plan.monthLabel)
        try sourceFingerprint.assertMatches(goals: [goal])
        try assertFinancialInputsAreCurrent([
            (goal, calculation.financialInputEvidence)
        ])
        let requirement = calculation.requirement
        let snapshot = MonthlyPlanMutationSnapshot(plan: plan)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [plan],
            restoreTouchedState: { snapshot.restore(in: modelContext) }
        ) {
            // Preserve user overrides (customAmount, flexState, isSkipped).
            plan.updateCalculation(
                requiredMonthly: requirement.requiredMonthly,
                remainingAmount: requirement.remainingAmount,
                monthsRemaining: requirement.monthsRemaining,
                status: requirement.status
            )
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId])
    }

    /// Update custom amount for a plan
    func setCustomAmount(_ amount: Double?, for plan: MonthlyPlan) throws {
        try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
            in: modelContext,
            allowing: [plan]
        )
        let snapshot = MonthlyPlanMutationSnapshot(plan: plan)
        plan.setCustomAmount(amount)
        if amount != nil {
            plan.isProtected = true
            plan.isSkipped = false
            plan.flexStateRawValue = MonthlyPlan.FlexState.protected.rawValue
            plan.lastModifiedDate = Date()
        } else if plan.isProtected || plan.flexState == .protected {
            plan.isProtected = false
            plan.flexStateRawValue = plan.isSkipped
                ? MonthlyPlan.FlexState.skipped.rawValue
                : MonthlyPlan.FlexState.flexible.rawValue
            plan.lastModifiedDate = Date()
        }

        do {
            try saveChanges()
        } catch {
            snapshot.restore()
            throw error
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId])
    }

    /// Toggle protection status
    func toggleProtection(for plan: MonthlyPlan) throws {
        let snapshot = MonthlyPlanMutationSnapshot(plan: plan)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [plan],
            restoreTouchedState: { snapshot.restore() }
        ) {
            plan.toggleProtection()
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId])
    }

    /// Skip or unskip a plan
    func skipPlan(_ plan: MonthlyPlan, skip: Bool = true) throws {
        let snapshot = MonthlyPlanMutationSnapshot(plan: plan)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [plan],
            restoreTouchedState: { snapshot.restore() }
        ) {
            plan.skipThisMonth(skip)
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId])
    }

    // MARK: - Plan Lifecycle State Transitions

    /// Transition plans from draft to executing
    func startExecution(for plans: [MonthlyPlan]) throws {
        let activeGoalIDs = try fetchActiveGoalIDs()
        let plansToChange = plans.filter {
            $0.state == .draft && activeGoalIDs.contains($0.goalId)
        }
        guard !plansToChange.isEmpty else { return }
        let snapshots = plansToChange.map(MonthlyPlanMutationSnapshot.init)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: plansToChange,
            restoreTouchedState: { snapshots.forEach { $0.restore() } }
        ) {
            for plan in plansToChange {
                plan.state = .executing
            }
        }
        postSharedGoalDataDidChange(goalIDs: Set(plansToChange.map(\.goalId)))
        AppLog.info("Started execution for \(plansToChange.count) plans", category: .monthlyPlanning)
    }

    /// Transition plans from executing to completed
    func completePlans(for plans: [MonthlyPlan]) throws {
        let plansToChange = plans.filter { $0.state == .executing }
        guard !plansToChange.isEmpty else { return }
        let snapshots = plansToChange.map(MonthlyPlanMutationSnapshot.init)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: plansToChange,
            restoreTouchedState: { snapshots.forEach { $0.restore() } }
        ) {
            for plan in plansToChange {
                plan.state = .completed
            }
        }
        postSharedGoalDataDidChange(goalIDs: Set(plansToChange.map(\.goalId)))
        AppLog.info("Completed \(plans.count) plans", category: .monthlyPlanning)
    }

    // MARK: - Helper Methods

    /// Get current month label (yyyy-MM format)
    func currentMonthLabel() -> String {
        PlanningMonthContract.storageLabel(for: now())
    }

    /// Calculate how many payment periods remain until the deadline
    /// Uses the payment day from MonthlyPlanningSettings
    ///
    /// Example: Today Dec 18, payment day 25th, deadline March 1
    /// Payment dates: Dec 25, Jan 25, Feb 25 = 3 periods
    private func calculatePaymentPeriodsRemaining(
        in monthLabel: String,
        until deadline: Date
    ) throws -> Int {
        let settings = MonthlyPlanningSettings.shared
        return try PlanningMonthContract.paymentPeriodsRemaining(
            in: monthLabel,
            paymentDay: settings.paymentDay,
            deadline: deadline,
            now: now()
        )
    }

    /// Delete a plan (use with caution)
    func deletePlan(_ plan: MonthlyPlan) throws {
        let goalID = plan.goalId
        let candidateSnapshot = MonthlyPlanMutationSnapshot(plan: plan)
        let plansToDelete: [MonthlyPlan]
        do {
            plansToDelete = try resolvePlansForDeletion([plan])
        } catch {
            candidateSnapshot.restore(in: modelContext)
            throw error
        }
        guard let planToDelete = plansToDelete.first else {
            postSharedGoalDataDidChange(goalIDs: [goalID])
            return
        }
        let durableSnapshot = MonthlyPlanMutationSnapshot(plan: planToDelete)
        let allowedModels = (durableSnapshot.models + candidateSnapshot.models).reduce(
            into: [any PersistentModel]()
        ) { uniqueModels, model in
            guard uniqueModels.contains(where: {
                $0.persistentModelID == model.persistentModelID
            }) == false else { return }
            uniqueModels.append(model)
        }
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            restoreTouchedState: {
                durableSnapshot.restore(in: modelContext)
                if planToDelete !== plan {
                    candidateSnapshot.restore(in: modelContext)
                }
            }
        ) {
            modelContext.delete(planToDelete)
        }
        postSharedGoalDataDidChange(goalIDs: [goalID])
    }


    // MARK: - Bulk Flex Adjustment

    /// Apply flex adjustment to multiple plans with proper state management
    /// This is the single source of truth for flex application
    func applyBulkFlexAdjustment(
        plans: [MonthlyPlan],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        clearFlexibleOverrides: Bool = false
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

            try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
                in: self.modelContext,
                allowing: plans
            )
            let mutationSnapshots = plans.map(MonthlyPlanMutationSnapshot.init)

            do {
                // Categorize and update plans using one canonical persisted state.
                for plan in plans {
                    if skippedGoalIds.contains(plan.goalId) {
                        plan.isSkipped = true
                        plan.isProtected = false
                        plan.flexStateRawValue = MonthlyPlan.FlexState.skipped.rawValue
                        plan.lastModifiedDate = Date()
                    } else if protectedGoalIds.contains(plan.goalId) {
                        plan.isSkipped = false
                        plan.isProtected = true
                        plan.flexStateRawValue = MonthlyPlan.FlexState.protected.rawValue
                        plan.lastModifiedDate = Date()
                    } else {
                        plan.isSkipped = false
                        plan.isProtected = false
                        plan.flexStateRawValue = MonthlyPlan.FlexState.flexible.rawValue
                        if clearFlexibleOverrides {
                            plan.setCustomAmount(nil)
                        } else {
                            // Always use requiredMonthly as the base so slider moves do not compound.
                            plan.setCustomAmount(max(0, plan.requiredMonthly * adjustment))
                        }
                    }
                }

                try self.saveChanges()
            } catch {
                mutationSnapshots.forEach { $0.restore() }
                throw error
            }

            self.postSharedGoalDataDidChange(goalIDs: Set(plans.map(\.goalId)))

            let flexibleCount = plans.filter { !protectedGoalIds.contains($0.goalId) && !skippedGoalIds.contains($0.goalId) }.count
            AppLog.info("Applied flex adjustment (\(Int(adjustment * 100))%) to \(flexibleCount) flexible plans",
                        category: .monthlyPlanning)
        }
    }

    /// Validate plans before state transition to execution
    func validatePlansForExecution(_ plans: [MonthlyPlan]) throws {
        var errors: [String] = []
        let activeGoalIDs = try fetchActiveGoalIDs()

        for plan in plans {
            if !activeGoalIDs.contains(plan.goalId) {
                errors.append("Plan for goal \(plan.goalId) does not belong to an active goal")
                continue
            }

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

    private func postSharedGoalDataDidChange(goalIDs: Set<UUID>) {
        guard !goalIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": Array(goalIDs),
                "reason": "goalMutation"
            ]
        )
    }

    private func assertFinancialInputsAreCurrent(
        _ validations: [(goal: Goal, evidence: GoalFinancialInputEvidence?)]
    ) throws {
        for validation in validations {
            guard let evidence = validation.evidence else { continue }
            guard goalCalculationService.financialInputEvidenceIsCurrent(
                evidence,
                for: validation.goal
            ) else {
                throw PlanError.sourceDataChanged(
                    "A balance-cache or exchange-rate input changed while plans were being calculated. Retry with current data."
                )
            }
        }
    }

    private func resolvePlansForDeletion(
        _ plans: [MonthlyPlan]
    ) throws -> [MonthlyPlan] {
        try PersistenceOperationTransaction.resolvePendingInsertDeletions(
            plans,
            in: modelContext,
            stableID: \.id,
            fetchByIDs: planDeletionFetchByIDs
        )
    }

    private func fetchActiveGoalIDs() throws -> Set<UUID> {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.lifecycleStatusRawValue == "active"
            }
        )
        return Set(try modelContext.fetch(descriptor).map(\.id))
    }
}

private struct MonthlyPlanFinancialSourceFingerprint: Equatable {
    private let paymentDay: Int
    private let goals: [GoalInput]

    init(goals: [Goal]) {
        paymentDay = MonthlyPlanningSettings.shared.paymentDay
        self.goals = goals
            .map(GoalInput.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func assertMatches(goals: [Goal]) throws {
        guard self == Self(goals: goals) else {
            throw PlanError.sourceDataChanged(
                "A goal, allocation, or transaction changed while plans were being calculated. Retry with current data."
            )
        }
    }

    private struct GoalInput: Equatable {
        let id: UUID
        let name: String
        let currency: String
        let targetAmount: UInt64
        let deadline: UInt64
        let startDate: UInt64
        let lifecycleStatusRawValue: String
        let allocations: [AllocationInput]

        init(goal: Goal) {
            id = goal.id
            name = goal.name
            currency = goal.currency
            targetAmount = goal.targetAmount.bitPattern
            deadline = goal.deadline.timeIntervalSinceReferenceDate.bitPattern
            startDate = goal.startDate.timeIntervalSinceReferenceDate.bitPattern
            lifecycleStatusRawValue = goal.lifecycleStatusRawValue
            allocations = (goal.allocations ?? [])
                .map(AllocationInput.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    private struct AllocationInput: Equatable {
        let id: UUID
        let amount: UInt64
        let goalID: UUID?
        let asset: AssetInput?

        init(allocation: AssetAllocation) {
            id = allocation.id
            amount = allocation.amountValue.bitPattern
            goalID = allocation.goal?.id
            asset = allocation.asset.map(AssetInput.init)
        }
    }

    private struct AssetInput: Equatable {
        let id: UUID
        let currency: String
        let address: String?
        let chainID: String?
        let transactions: [TransactionInput]

        init(asset: Asset) {
            id = asset.id
            currency = asset.currency
            address = asset.address
            chainID = asset.chainId
            transactions = (asset.transactions ?? [])
                .map(TransactionInput.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    private struct TransactionInput: Equatable {
        let id: UUID
        let amount: UInt64
        let date: UInt64
        let sourceRawValue: String
        let externalID: String?
        let counterparty: String?
        let comment: String?
        let assetID: UUID?

        init(transaction: Transaction) {
            id = transaction.id
            amount = transaction.amount.bitPattern
            date = transaction.date.timeIntervalSinceReferenceDate.bitPattern
            sourceRawValue = transaction.sourceRawValue
            externalID = transaction.externalId
            counterparty = transaction.counterparty
            comment = transaction.comment
            assetID = transaction.asset?.id
        }
    }
}

private struct MonthlyPlanMutationSnapshot {
    let plan: MonthlyPlan
    let executionRecord: MonthlyExecutionRecord?
    let executionRecordPlans: [MonthlyPlan]?
    let monthLabel: String
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let lastCalculated: Date
    let stateRawValue: String
    let customAmount: Double?
    let flexStateRawValue: String
    let isProtected: Bool
    let isSkipped: Bool
    let lastModifiedDate: Date

    var models: [any PersistentModel] {
        var models: [any PersistentModel] = [plan]
        if let executionRecord {
            models.append(executionRecord)
        }
        return models
    }

    init(plan: MonthlyPlan) {
        self.plan = plan
        let executionRecord = plan.executionRecord
        self.executionRecord = executionRecord
        self.executionRecordPlans = executionRecord?.plans
        self.monthLabel = plan.monthLabel
        self.requiredMonthly = plan.requiredMonthly
        self.remainingAmount = plan.remainingAmount
        self.monthsRemaining = plan.monthsRemaining
        self.currency = plan.currency
        self.statusRawValue = plan.statusRawValue
        self.lastCalculated = plan.lastCalculated
        self.stateRawValue = plan.stateRawValue
        self.customAmount = plan.customAmount
        self.flexStateRawValue = plan.flexStateRawValue
        self.isProtected = plan.isProtected
        self.isSkipped = plan.isSkipped
        self.lastModifiedDate = plan.lastModifiedDate
    }

    func restore() {
        plan.monthLabel = monthLabel
        plan.requiredMonthly = requiredMonthly
        plan.remainingAmount = remainingAmount
        plan.monthsRemaining = monthsRemaining
        plan.currency = currency
        plan.statusRawValue = statusRawValue
        plan.lastCalculated = lastCalculated
        plan.stateRawValue = stateRawValue
        plan.customAmount = customAmount
        plan.flexStateRawValue = flexStateRawValue
        plan.isProtected = isProtected
        plan.isSkipped = isSkipped
        plan.lastModifiedDate = lastModifiedDate
    }

    func restore(in modelContext: ModelContext) {
        let previousUndoManager = modelContext.undoManager
        modelContext.undoManager = nil
        defer {
            modelContext.undoManager = previousUndoManager
        }

        let wasDeleted = modelContext.deletedModelsArray.contains {
            $0.persistentModelID == plan.persistentModelID
        }
        if plan.modelContext == nil || wasDeleted {
            modelContext.insert(plan)
            modelContext.processPendingChanges()
        }
        restore()
        plan.executionRecord = executionRecord
        executionRecord?.plans = executionRecordPlans
        modelContext.processPendingChanges()
    }
}

// MARK: - Supporting Types

enum PlanError: LocalizedError {
    case invalidState(String)
    case invalidAmount(String)
    case validationFailed(String)
    case dataUnavailable(String)
    case sourceDataChanged(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid plan state: \(message)"
        case .invalidAmount(let message):
            return "Invalid amount: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .dataUnavailable(let message):
            return "Planning data unavailable: \(message)"
        case .sourceDataChanged(let message):
            return "Planning data changed: \(message)"
        }
    }
}
