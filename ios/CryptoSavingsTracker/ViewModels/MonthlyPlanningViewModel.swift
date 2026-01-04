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
    
    // MARK: - Dependencies
    
    private let planService: MonthlyPlanService
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let modelContext: ModelContext
    private var flexService: FlexAdjustmentService?
    private var cancellables = Set<AnyCancellable>()
    private var currentPlans: [MonthlyPlan] = []
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        self.exchangeRateService = DIContainer.shared.exchangeRateService
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
        }
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
