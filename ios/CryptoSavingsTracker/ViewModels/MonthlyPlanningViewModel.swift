//
//  MonthlyPlanningViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// ViewModel for managing monthly planning calculations and UI state
@MainActor
final class MonthlyPlanningViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// All monthly requirements for active goals
    @Published var monthlyRequirements: [MonthlyRequirement] = []
    
    /// All active goals
    @Published var goals: [Goal] = []
    
    /// Total required amount in display currency
    @Published var totalRequired: Double = 0
    
    /// Settings for monthly planning configuration
    private let settings = MonthlyPlanningSettings.shared
    
    /// Display currency for total calculations (derived from settings)
    @Published var displayCurrency: String = "USD"

    /// Month label the planning UI is currently targeting
    @Published var planningMonthLabel: String = ""
    
    /// Access to settings for UI components
    var planningSettings: MonthlyPlanningSettings {
        settings
    }
    
    /// Flex adjustment percentage (0.0 to 1.5, where 1.0 = 100%)
    @Published var flexAdjustment: Double = 1.0
    
    /// Loading state
    @Published var isLoading = false
    
    /// Error state
    @Published var error: Error?
    
    /// Whether flex controls are visible
    @Published var showFlexControls = false
    
    /// Protected goal IDs (won't be reduced in flex adjustments)
    @Published var protectedGoalIds: Set<UUID> = []
    
    /// Skipped goal IDs (temporarily excluded from payments)
    @Published var skippedGoalIds: Set<UUID> = []

    // MARK: - Budget Calculator State

    /// Latest budget calculator preview plan (ephemeral).
    @Published var budgetPreviewPlan: BudgetCalculatorPlan?

    /// Feasibility status for the current budget input.
    @Published var budgetFeasibility: FeasibilityResult = .empty

    /// Timeline blocks for the preview schedule.
    @Published var budgetPreviewTimeline: [ScheduledGoalBlock] = []

    /// Loading state for budget preview.
    @Published var isBudgetPreviewLoading = false

    /// Budget preview error message.
    @Published var budgetPreviewError: String?

    /// One-time migration notice flag (view-level).
    @Published var showBudgetMigrationNotice = false

    /// Prompt for recalculation when goals or month change.
    @Published var showBudgetRecalculationPrompt = false
    
    // MARK: - Computed Properties
    
    /// Whether there are any flexible goals that can be adjusted
    var hasFlexibleGoals: Bool {
        monthlyRequirements.contains { requirement in
            !protectedGoalIds.contains(requirement.goalId) && 
            !skippedGoalIds.contains(requirement.goalId)
        }
    }
    
    /// Total after flex adjustment
    var adjustedTotal: Double {
        if flexAdjustment == 1.0 {
            return totalRequired
        }

        var total: Double = 0
        for requirement in monthlyRequirements {
            if skippedGoalIds.contains(requirement.goalId) {
                continue
            }

            if protectedGoalIds.contains(requirement.goalId) {
                total += requirement.requiredMonthly
            } else {
                total += requirement.requiredMonthly * flexAdjustment
            }
        }
        return total
    }

    /// Number of goals affected by flex adjustment (flexible, non-skipped goals)
    var affectedGoalsCount: Int {
        monthlyRequirements.filter { requirement in
            !protectedGoalIds.contains(requirement.goalId) &&
            !skippedGoalIds.contains(requirement.goalId)
        }.count
    }
    
    /// Summary statistics
    var statistics: PlanningStatistics {
        PlanningStatistics(
            totalGoals: monthlyRequirements.count,
            onTrackCount: monthlyRequirements.filter { $0.status == .onTrack }.count,
            attentionCount: monthlyRequirements.filter { $0.status == .attention }.count,
            criticalCount: monthlyRequirements.filter { $0.status == .critical }.count,
            completedCount: monthlyRequirements.filter { $0.status == .completed }.count,
            averageMonthlyRequired: monthlyRequirements.isEmpty ? 0 : 
                monthlyRequirements.map { $0.requiredMonthly }.reduce(0, +) / Double(monthlyRequirements.count),
            shortestDeadline: monthlyRequirements.map { $0.deadline }.min()
        )
    }

    /// Whether a monthly budget is configured.
    var hasBudget: Bool {
        (settings.monthlyBudget ?? 0) > 0
    }

    /// Current budget amount (0 when not set).
    var budgetAmount: Double {
        settings.monthlyBudget ?? 0
    }

    /// Budget currency (defaults to settings).
    var budgetCurrency: String {
        settings.budgetCurrency
    }

    /// Whether the budget has been applied to the current planning month.
    var isBudgetAppliedForCurrentMonth: Bool {
        settings.budgetAppliedMonthLabel == planningMonthLabel && hasBudget
    }

    /// Current focus goal for budget summary (earliest deadline with remaining amount).
    private var budgetFocusGoal: Goal? {
        guard hasBudget else { return nil }
        let candidates = currentPlans
            .filter { !$0.isSkipped && ($0.customAmount ?? 0) > 0.01 }
            .compactMap { plan in
                goals.first { $0.id == plan.goalId }
            }
        return candidates.min(by: { $0.deadline < $1.deadline })
    }

    /// Current focus goal name for budget summary.
    var budgetFocusGoalName: String? {
        budgetFocusGoal?.name
    }

    /// Current focus goal deadline for budget summary.
    var budgetFocusGoalDeadline: Date? {
        budgetFocusGoal?.deadline
    }
    
    // MARK: - Dependencies
    
    private let planService: MonthlyPlanService
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let budgetCalculatorService: BudgetCalculatorService
    private let modelContext: ModelContext
    private var flexService: FlexAdjustmentService?
    private var cancellables = Set<AnyCancellable>()
    private var currentPlans: [MonthlyPlan] = []
    private var isApplyingBudgetMigration = false
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        self.exchangeRateService = DIContainer.shared.exchangeRateService
        self.budgetCalculatorService = DIContainer.shared.budgetCalculatorService(modelContext: modelContext)
        self.flexService = DIContainer.shared.makeFlexAdjustmentService(modelContext: modelContext)
        self.planningMonthLabel = planService.currentMonthLabel()
        
        // Initialize display currency from settings
        self.displayCurrency = settings.displayCurrency
        
        setupObservers()
        loadUserPreferences()
        setupSettingsObservation()
    }
    
    // MARK: - Public Methods
    
    /// Load monthly requirements for all active goals in the selected planning month
    func loadMonthlyRequirements(for monthLabel: String? = nil) async {
        isLoading = true
        error = nil
        let targetMonthLabel = resolvePlanningMonthLabel(preferred: monthLabel)
        planningMonthLabel = targetMonthLabel
        
        do {
            // Fetch all active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.lifecycleStatusRawValue == "active"
                },
                sortBy: [SortDescriptor(\.deadline, order: .forward)]
            )
            
            let goals = try modelContext.fetch(descriptor)
            for _ in goals {
            }

            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let hasActiveExecution = (try? executionService.getActiveRecord()) != nil
            if !hasActiveExecution {
                _ = try await planService.rollForwardDraftPlans(to: targetMonthLabel)
            }

            // Get or create persisted plans for the selected month
            let plans = try await planService.getOrCreatePlans(for: targetMonthLabel, goals: goals)

            await refreshDraftPlans(plans, goals: goals)

            self.currentPlans = plans

            // Map plans to MonthlyRequirement adapters for UI compatibility
            let requirements = goals.compactMap { goal -> MonthlyRequirement? in
                guard let plan = plans.first(where: { $0.goalId == goal.id }) else { return nil }
                return requirement(from: plan, goal: goal)
            }

            let total = await calculateTotalRequired(from: plans, displayCurrency: displayCurrency)
            
            // Update UI on main thread
            await MainActor.run {
                self.goals = goals
                self.monthlyRequirements = requirements
                self.totalRequired = total
                self.isLoading = false
                // Refresh flex state sets from plan data
                self.protectedGoalIds = Set(plans.filter { $0.flexState == .protected || $0.isProtected }.map { $0.goalId })
                self.skippedGoalIds = Set(plans.filter { $0.flexState == .skipped || $0.isSkipped }.map { $0.goalId })
            }

            await refreshBudgetStatus()
            await handleBudgetMigrationIfNeeded(goals: goals)
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            AppLog.error("Failed to load monthly requirements: \(error)", category: .monthlyPlanning)
        }
    }
    
    /// Refresh calculations (force cache clear)
    func refreshCalculations() async {
        await loadMonthlyRequirements()
    }

    // MARK: - Budget Calculator

    /// Prepare preview data for the budget calculator sheet.
    func previewBudget(amount: Double, currency: String) async {
        let normalizedAmount = max(0, amount)
        let eligibleGoals = budgetEligibleGoals()

        guard normalizedAmount > 0, !eligibleGoals.isEmpty else {
            budgetPreviewPlan = nil
            budgetPreviewTimeline = []
            budgetFeasibility = .empty
            return
        }

        isBudgetPreviewLoading = true
        budgetPreviewError = nil

        let feasibility = await budgetCalculatorService.checkFeasibility(
            goals: eligibleGoals,
            budget: normalizedAmount,
            currency: currency
        )
        let plan = await budgetCalculatorService.generateSchedule(
            goals: eligibleGoals,
            budget: normalizedAmount,
            currency: currency
        )
        let timeline = budgetCalculatorService.buildTimelineBlocks(from: plan, goals: eligibleGoals)

        budgetFeasibility = feasibility
        budgetPreviewPlan = plan
        budgetPreviewTimeline = timeline
        isBudgetPreviewLoading = false
    }

    /// Apply a feasibility suggestion that modifies goals and refreshes the preview.
    func applyFeasibilitySuggestion(
        _ suggestion: FeasibilitySuggestion,
        currentBudget: Double,
        currency: String
    ) async -> Bool {
        switch suggestion {
        case .increaseBudget:
            return false
        case .editGoal:
            return false
        case .extendDeadline(let goalId, _, let months):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            if let updated = Calendar.current.date(byAdding: .month, value: months, to: goal.deadline) {
                goal.deadline = updated
            } else {
                return false
            }
        case .reduceTarget(let goalId, _, let to, _):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            goal.targetAmount = to
        }

        do {
            try modelContext.save()
        } catch {
            self.error = error
            return false
        }

        await loadMonthlyRequirements(for: planningMonthLabel)
        if currentBudget > 0 {
            await previewBudget(amount: currentBudget, currency: currency)
        }
        return true
    }

    func hasCustomAmount(for goalId: UUID) -> Bool {
        currentPlans.first(where: { $0.goalId == goalId })?.customAmount != nil
    }

    /// Apply the budget calculator results to the current month's plans.
    func applyBudgetPlan(
        plan: BudgetCalculatorPlan,
        amount: Double,
        currency: String
    ) async -> Bool {
        guard !currentPlans.isEmpty else { return false }

        let contributionMap = Dictionary(
            uniqueKeysWithValues: (plan.schedule.first?.contributions ?? []).map { ($0.goalId, $0.amount) }
        )

        var conversionFailed = false
        for plan in currentPlans {
            guard !plan.isSkipped else { continue }
            let plannedAmount = contributionMap[plan.goalId] ?? 0
            var converted = plannedAmount

            if plannedAmount > 0, plan.currency != currency {
                if let rate = try? await exchangeRateService.fetchRate(from: currency, to: plan.currency) {
                    converted = plannedAmount * rate
                } else {
                    conversionFailed = true
                    continue
                }
            }

            plan.setCustomAmount(plannedAmount > 0 ? converted : 0)
        }

        if conversionFailed {
            budgetPreviewError = "Missing exchange rates for some goals."
            return false
        }

        do {
            try modelContext.save()
        } catch {
            budgetPreviewError = "Failed to apply budget to plans."
            return false
        }

        settings.monthlyBudget = amount
        settings.budgetCurrency = currency
        settings.budgetAppliedMonthLabel = planningMonthLabel
        settings.budgetAppliedSignature = budgetSignature(for: budgetEligibleGoals())

        flexAdjustment = 1.0
        saveUserPreferences()

        await loadMonthlyRequirements()
        return true
    }

    /// Dismiss the one-time migration notice.
    func dismissBudgetMigrationNotice() {
        settings.hasSeenBudgetMigrationNotice = true
        showBudgetMigrationNotice = false
    }

    /// Mark the recalculation prompt as acknowledged for the current inputs.
    func acknowledgeBudgetRecalculationPrompt() {
        settings.budgetAppliedMonthLabel = planningMonthLabel
        settings.budgetAppliedSignature = budgetSignature(for: budgetEligibleGoals())
        showBudgetRecalculationPrompt = false
    }

    /// Apply flex adjustment to persisted plans and refresh UI
    func applyFlexAdjustment(_ percentage: Double) async {
        let clamped = max(0.0, min(1.5, percentage))
        flexAdjustment = clamped

        guard !currentPlans.isEmpty else {
            await loadMonthlyRequirements()
            return
        }

        do {
            try await planService.applyBulkFlexAdjustment(
                plans: currentPlans,
                adjustment: clamped,
                protectedGoalIds: protectedGoalIds,
                skippedGoalIds: skippedGoalIds
            )

            // Refresh UI using mutated plans
            let requirements = goals.compactMap { goal -> MonthlyRequirement? in
                guard let plan = currentPlans.first(where: { $0.goalId == goal.id }) else { return nil }
                return requirement(from: plan, goal: goal)
            }
            let total = await calculateTotalRequired(from: currentPlans, displayCurrency: displayCurrency)

            await MainActor.run {
                self.monthlyRequirements = requirements
                self.totalRequired = total
            }
            await refreshBudgetStatus()
        } catch {
            await MainActor.run {
                self.error = error
            }
            AppLog.error("Failed to apply flex adjustment: \(error)", category: .monthlyPlanning)
        }
    }
    
    /// Toggle protection status for a goal
    func toggleProtection(for goalId: UUID) {
        if protectedGoalIds.contains(goalId) {
            protectedGoalIds.remove(goalId)
        } else {
            protectedGoalIds.insert(goalId)
            skippedGoalIds.remove(goalId) // Can't be both protected and skipped
        }
        saveUserPreferences()
        Task {
            await applyFlexAdjustment(flexAdjustment)
            await refreshBudgetStatus()
        }
    }
    
    /// Toggle skip status for a goal
    func toggleSkip(for goalId: UUID) {
        if skippedGoalIds.contains(goalId) {
            skippedGoalIds.remove(goalId)
        } else {
            skippedGoalIds.insert(goalId)
            protectedGoalIds.remove(goalId) // Can't be both skipped and protected
        }
        saveUserPreferences()
        Task {
            await applyFlexAdjustment(flexAdjustment)
            await refreshBudgetStatus()
        }
    }

    /// Set a custom amount for a specific goal
    /// - Parameters:
    ///   - goalId: The goal to set custom amount for
    ///   - amount: The custom amount (nil to clear)
    func setCustomAmount(for goalId: UUID, amount: Double?) {
        guard let plan = currentPlans.first(where: { $0.goalId == goalId }) else {
            AppLog.warning("No plan found for goal \(goalId)", category: .monthlyPlanning)
            return
        }

        // Set the custom amount directly on the plan
        do {
            try planService.setCustomAmount(amount, for: plan)

            // If setting a custom amount, auto-protect this goal
            if amount != nil {
                protectedGoalIds.insert(goalId)
                skippedGoalIds.remove(goalId)
            }

            saveUserPreferences()

            // Refresh the adjusted amounts display
            Task {
                await loadMonthlyRequirements(for: planningMonthLabel)
                await refreshBudgetStatus()
            }

            AppLog.info("Set custom amount \(amount ?? 0) for goal \(goalId)", category: .monthlyPlanning)
        } catch {
            AppLog.error("Failed to set custom amount: \(error)", category: .monthlyPlanning)
        }
    }

    /// Get the current effective amount for a goal (custom amount or calculated)
    func getEffectiveAmount(for goalId: UUID) -> Double? {
        guard let plan = currentPlans.first(where: { $0.goalId == goalId }) else { return nil }
        return plan.effectiveAmount
    }

    /// Get the required monthly amount for a goal (before any adjustments)
    func getRequiredAmount(for goalId: UUID) -> Double? {
        return monthlyRequirements.first(where: { $0.goalId == goalId })?.requiredMonthly
    }

    /// Apply quick action
    func applyQuickAction(_ action: QuickAction) async {
        switch action {
        case .skipMonth:
            // Skip all flexible goals this month
            for requirement in monthlyRequirements {
                if !protectedGoalIds.contains(requirement.goalId) {
                    skippedGoalIds.insert(requirement.goalId)
                }
            }
            
        case .payHalf:
            // Pay 50% of required amounts
            skippedGoalIds.removeAll()
            
        case .payExact:
            // Pay exact calculated amounts
            skippedGoalIds.removeAll()

        case .reset:
            // Reset all adjustments
            protectedGoalIds.removeAll()
            skippedGoalIds.removeAll()
        }
        
        saveUserPreferences()
        await applyFlexAdjustment(flexAdjustment)
    }
    
    /// Get flex state for a specific goal
    func getFlexState(for goalId: UUID) -> MonthlyPlan.FlexState {
        if skippedGoalIds.contains(goalId) {
            return .skipped
        } else if protectedGoalIds.contains(goalId) {
            return .protected
        } else {
            return .flexible
        }
    }
    
    /// Update display currency
    func updateDisplayCurrency(_ currency: String) async {
        settings.displayCurrency = currency
        await loadMonthlyRequirements()
    }
    
    // MARK: - Private Methods
    
    /// Setup Combine observers for reactive updates
    private func setupObservers() {
        // Observe goal changes
        NotificationCenter.default.publisher(for: .monthlyPlanningGoalUpdated)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .monthlyPlanningGoalDeleted)
            .sink { [weak self] notification in
                guard let goal = notification.object as? Goal else { return }
                self?.protectedGoalIds.remove(goal.id)
                self?.skippedGoalIds.remove(goal.id)
                self?.saveUserPreferences()
                
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        // Observe asset changes
        NotificationCenter.default.publisher(for: .monthlyPlanningAssetUpdated)
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                    await self?.persistUpdatedPlans()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .monthlyExecutionCompleted)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Setup observation of settings changes
    private func setupSettingsObservation() {
        // Observe currency changes
        settings.$displayCurrency
            .receive(on: RunLoop.main)
            .sink { [weak self] newCurrency in
                self?.displayCurrency = newCurrency
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        // Observe payment day changes
        settings.$paymentDay
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)

        // Observe budget changes
        settings.$monthlyBudget
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshBudgetStatus()
                }
            }
            .store(in: &cancellables)

        settings.$budgetCurrency
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshBudgetStatus()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshBudgetStatus() async {
        guard hasBudget else {
            budgetFeasibility = .empty
            showBudgetRecalculationPrompt = false
            return
        }

        let eligibleGoals = budgetEligibleGoals()
        guard !eligibleGoals.isEmpty else {
            budgetFeasibility = .empty
            return
        }

        let budget = settings.monthlyBudget ?? 0
        let currency = settings.budgetCurrency
        let feasibility = await budgetCalculatorService.checkFeasibility(
            goals: eligibleGoals,
            budget: budget,
            currency: currency
        )
        budgetFeasibility = feasibility

        guard settings.budgetAppliedMonthLabel != nil else {
            showBudgetRecalculationPrompt = false
            return
        }

        let signature = budgetSignature(for: eligibleGoals)
        if settings.budgetAppliedMonthLabel != planningMonthLabel {
            showBudgetRecalculationPrompt = true
        } else {
            showBudgetRecalculationPrompt = settings.budgetAppliedSignature != signature
        }
    }

    private func handleBudgetMigrationIfNeeded(goals: [Goal]) async {
        guard hasBudget, settings.budgetAppliedMonthLabel == nil else { return }
        guard !isApplyingBudgetMigration else { return }
        let eligibleGoals = budgetEligibleGoals(from: goals)
        guard !eligibleGoals.isEmpty else { return }

        isApplyingBudgetMigration = true
        defer { isApplyingBudgetMigration = false }

        let budget = settings.monthlyBudget ?? 0
        let currency = settings.budgetCurrency
        let plan = await budgetCalculatorService.generateSchedule(
            goals: eligibleGoals,
            budget: budget,
            currency: currency
        )

        let applied = await applyBudgetPlan(plan: plan, amount: budget, currency: currency)
        if applied, !settings.hasSeenBudgetMigrationNotice {
            showBudgetMigrationNotice = true
        }
    }

    private func budgetEligibleGoals(from goals: [Goal]? = nil) -> [Goal] {
        let source = goals ?? self.goals
        let skipped = skippedGoalIds
        return source.filter { goal in
            goal.lifecycleStatus == .active && !skipped.contains(goal.id)
        }
    }

    private func budgetSignature(for goals: [Goal]) -> String {
        let formatter = ISO8601DateFormatter()
        return goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { goal in
                let deadline = formatter.string(from: goal.deadline)
                return "\(goal.id.uuidString)|\(goal.currency)|\(goal.targetAmount)|\(deadline)"
            }
            .joined(separator: ";")
    }
    
    /// Load saved flex states from SwiftData
    private func loadFlexStates() async {
        do {
            let descriptor = FetchDescriptor<MonthlyPlan>()
            let plans = try modelContext.fetch(descriptor)
            
            for plan in plans {
                switch plan.flexState {
                case .protected:
                    protectedGoalIds.insert(plan.goalId)
                case .skipped:
                    skippedGoalIds.insert(plan.goalId)
                case .flexible:
                    break
                }
            }
        } catch {
            AppLog.warning("Failed to load flex states: \(error)", category: .monthlyPlanning)
        }
    }

    /// Persist recalculated MonthlyPlans to SwiftData so execution can read live amounts
    private func persistUpdatedPlans() async {
        do {
            // Use current month label and persisted plans as the source of truth
            let plans = try planService.fetchPlans(for: planningMonthLabel, state: nil)

            // Recalculate and update each plan using the latest goal data
            for plan in plans {
                guard let goal = goals.first(where: { $0.id == plan.goalId }) else { continue }
                try await planService.updatePlan(plan, withGoal: goal)
            }
        } catch {
            AppLog.error("Failed to persist updated plans: \(error)", category: .monthlyPlanning)
        }
    }
    
    /// Save user preferences to UserDefaults
    private func saveUserPreferences() {
        // Display currency is now managed by settings
        UserDefaults.standard.set(Array(protectedGoalIds.map { $0.uuidString }), forKey: "MonthlyPlanning.ProtectedGoals")
        UserDefaults.standard.set(Array(skippedGoalIds.map { $0.uuidString }), forKey: "MonthlyPlanning.SkippedGoals")
        UserDefaults.standard.set(flexAdjustment, forKey: "MonthlyPlanning.FlexAdjustment")
    }
    
    /// Load user preferences from UserDefaults
    private func loadUserPreferences() {
        // Display currency is now managed by settings
        
        if let protectedStrings = UserDefaults.standard.stringArray(forKey: "MonthlyPlanning.ProtectedGoals") {
            protectedGoalIds = Set(protectedStrings.compactMap { UUID(uuidString: $0) })
        }
        
        if let skippedStrings = UserDefaults.standard.stringArray(forKey: "MonthlyPlanning.SkippedGoals") {
            skippedGoalIds = Set(skippedStrings.compactMap { UUID(uuidString: $0) })
        }
        
        let savedAdjustment = UserDefaults.standard.double(forKey: "MonthlyPlanning.FlexAdjustment")
        if savedAdjustment > 0 {
            flexAdjustment = savedAdjustment
        }
    }

    /// Adapter: convert a persisted MonthlyPlan into a MonthlyRequirement for UI reuse
    private func requirement(from plan: MonthlyPlan, goal: Goal) -> MonthlyRequirement {
        let required = plan.effectiveAmount
        let remaining = plan.remainingAmount
        let currentTotal = max(goal.targetAmount - remaining, 0)
        let progress = goal.targetAmount > 0 ? min(currentTotal / goal.targetAmount, 1.0) : 0.0

        return MonthlyRequirement(
            goalId: plan.goalId,
            goalName: goal.name,
            currency: plan.currency,
            targetAmount: goal.targetAmount,
            currentTotal: currentTotal,
            remainingAmount: remaining,
            monthsRemaining: plan.monthsRemaining,
            requiredMonthly: required,
            progress: progress,
            deadline: goal.deadline,
            status: plan.status
        )
    }

    private func resolvePlanningMonthLabel(preferred: String?) -> String {
        if let preferred, !preferred.isEmpty {
            return preferred
        }

        let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        if let record = try? executionService.getCurrentMonthRecord(), record.status == .closed {
            if let nextMonth = nextMonthLabel(from: record.monthLabel) {
                return nextMonth
            }
        }

        let currentMonth = planService.currentMonthLabel()
        if planningMonthLabel.isEmpty {
            return currentMonth
        }
        if planningMonthLabel < currentMonth {
            return currentMonth
        }
        return planningMonthLabel
    }

    private func nextMonthLabel(from monthLabel: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthLabel),
              let nextDate = Calendar.current.date(byAdding: .month, value: 1, to: date) else {
            return nil
        }
        return formatter.string(from: nextDate)
    }

    private func refreshDraftPlans(_ plans: [MonthlyPlan], goals: [Goal]) async {
        do {
            for plan in plans where plan.state == .draft {
                guard let goal = goals.first(where: { $0.id == plan.goalId }) else { continue }
                try await planService.updatePlan(plan, withGoal: goal)
            }
        } catch {
            AppLog.error("Failed to refresh draft plans: \(error)", category: .monthlyPlanning)
        }
    }

    /// Calculate total required using plan effective amounts with currency conversion
    private func calculateTotalRequired(from plans: [MonthlyPlan], displayCurrency: String) async -> Double {
        var total = 0.0

        for plan in plans {
            if plan.currency == displayCurrency {
                total += plan.effectiveAmount
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: plan.currency, to: displayCurrency)
                    total += plan.effectiveAmount * rate
                } catch {
                    // Ignore cancelled requests (e.g., superseded by newer refresh); only log real failures.
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        continue
                    }
                    AppLog.warning("Failed to convert \(plan.currency) to \(displayCurrency): \(error)", category: .monthlyPlanning)
                }
            }
        }

        return total
    }
}

// MARK: - Supporting Types

// QuickAction is now defined in Models/QuickAction.swift

/// Planning statistics
struct PlanningStatistics {
    let totalGoals: Int
    let onTrackCount: Int
    let attentionCount: Int
    let criticalCount: Int
    let completedCount: Int
    let averageMonthlyRequired: Double
    let shortestDeadline: Date?
    
    var statusSummary: String {
        if criticalCount > 0 {
            return "\(criticalCount) critical goal\(criticalCount == 1 ? "" : "s") need immediate attention"
        } else if attentionCount > 0 {
            return "\(attentionCount) goal\(attentionCount == 1 ? "" : "s") need attention"
        } else if onTrackCount == totalGoals {
            return "All goals on track"
        } else {
            return "\(onTrackCount) of \(totalGoals) goals on track"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let monthlyPlanningGoalUpdated = Notification.Name("monthlyPlanningGoalUpdated")
    static let monthlyPlanningGoalDeleted = Notification.Name("monthlyPlanningGoalDeleted")
    static let monthlyPlanningAssetUpdated = Notification.Name("monthlyPlanningAssetUpdated")
}
