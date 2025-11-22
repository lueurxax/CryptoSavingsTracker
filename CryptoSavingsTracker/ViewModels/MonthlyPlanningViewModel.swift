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
    
    /// Access to settings for UI components
    var planningSettings: MonthlyPlanningSettings {
        settings
    }
    
    /// Flex adjustment percentage (0.0 to 1.5, where 1.0 = 100%)
    @Published var flexAdjustment: Double = 1.0
    
    /// Preview of adjusted amounts based on flex adjustment
    @Published var adjustmentPreview: [UUID: Double] = [:]
    
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
    
    private let planningService: MonthlyPlanningServiceProtocol
    private let modelContext: ModelContext
    private var flexService: FlexAdjustmentService?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.planningService = DIContainer.shared.monthlyPlanningService
        self.flexService = DIContainer.shared.makeFlexAdjustmentService(modelContext: modelContext)
        
        // Initialize display currency from settings
        self.displayCurrency = settings.displayCurrency
        
        setupObservers()
        loadUserPreferences()
        setupSettingsObservation()
    }
    
    // MARK: - Public Methods
    
    /// Load monthly requirements for all active goals
    func loadMonthlyRequirements() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch all active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.archivedDate == nil
                },
                sortBy: [SortDescriptor(\.deadline, order: .forward)]
            )
            
            let goals = try modelContext.fetch(descriptor)
            
            // Calculate monthly requirements
            let requirements = await planningService.calculateMonthlyRequirements(for: goals)
            
            // Calculate total in display currency
            let total = await planningService.calculateTotalRequired(
                for: goals,
                displayCurrency: displayCurrency
            )
            
            // Update UI on main thread
            await MainActor.run {
                self.goals = goals
                self.monthlyRequirements = requirements
                self.totalRequired = total
                self.isLoading = false
            }
            
            // Load saved flex states
            await loadFlexStates()
            
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
        planningService.clearCache()
        await loadMonthlyRequirements()
    }
    
    /// Preview adjustment with specific percentage using FlexAdjustmentService
    func previewAdjustment(_ percentage: Double) async {
        flexAdjustment = max(0.0, min(2.0, percentage)) // Clamp between 0-200%
        
        guard let flexService = flexService,
              !monthlyRequirements.isEmpty else {
            // Fallback to simple calculation if service unavailable
            await previewAdjustmentSimple(percentage)
            return
        }
        
        do {
            let adjustedRequirements = await flexService.applyFlexAdjustment(
                requirements: monthlyRequirements,
                adjustment: flexAdjustment,
                protectedGoalIds: protectedGoalIds,
                skippedGoalIds: skippedGoalIds,
                strategy: .balanced
            )
            
            var preview: [UUID: Double] = [:]
            for adjusted in adjustedRequirements {
                preview[adjusted.requirement.goalId] = adjusted.adjustedAmount
            }
            
            await MainActor.run {
                self.adjustmentPreview = preview
            }
        }
    }
    
    /// Fallback simple adjustment preview
    private func previewAdjustmentSimple(_ percentage: Double) async {
        var preview: [UUID: Double] = [:]
        
        for requirement in monthlyRequirements {
            if skippedGoalIds.contains(requirement.goalId) {
                preview[requirement.goalId] = 0
            } else if protectedGoalIds.contains(requirement.goalId) {
                preview[requirement.goalId] = requirement.requiredMonthly
            } else {
                preview[requirement.goalId] = requirement.requiredMonthly * flexAdjustment
            }
        }
        
        await MainActor.run {
            self.adjustmentPreview = preview
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
            await previewAdjustment(flexAdjustment)
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
            await previewAdjustment(flexAdjustment)
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
            await previewAdjustment(0)
            
        case .payHalf:
            // Pay 50% of required amounts
            skippedGoalIds.removeAll()
            await previewAdjustment(0.5)
            
        case .payExact:
            // Pay exact calculated amounts
            skippedGoalIds.removeAll()
            await previewAdjustment(1.0)

        case .reset:
            // Reset all adjustments
            protectedGoalIds.removeAll()
            skippedGoalIds.removeAll()
            await previewAdjustment(1.0)
        }
        
        saveUserPreferences()
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