//
//  MonthlyExecutionViewModel.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Manages UI state for monthly execution tracking
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// ViewModel for monthly execution tracking UI
@MainActor
final class MonthlyExecutionViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Current execution record
    @Published var executionRecord: MonthlyExecutionRecord?

    /// Snapshot of the plan when tracking started
    @Published var snapshot: ExecutionSnapshot?

    /// Total contributed per goal
    @Published var contributedTotals: [UUID: Double] = [:]

    /// Fulfillment status per goal
    @Published var fulfillmentStatus: [UUID: Bool] = [:]

    /// Overall progress percentage
    @Published var overallProgress: Double = 0

    /// Loading state
    @Published var isLoading = false

    /// Error state
    @Published var error: Error?

    /// Show undo banner
    @Published var showUndoBanner = false

    /// Undo expiration time
    @Published var undoExpiresAt: Date?

    /// Display currency for execution remaining amounts
    @Published var displayCurrency: String {
        didSet {
            UserDefaults.standard.set(displayCurrency, forKey: DisplayCurrencyKeys.executionDisplayCurrency)
            Task { await refreshRemainingDisplayAmounts() }
        }
    }

    /// Remaining-to-close amounts per goal in the selected display currency
    @Published var remainingByGoalInDisplayCurrency: [UUID: Double] = [:]

    /// Display currency per goal (falls back to goal currency when rates are unavailable)
    @Published var remainingDisplayCurrencyByGoal: [UUID: String] = [:]

    /// Timestamp of last rate refresh for display conversions
    @Published var displayRateUpdatedAt: Date?

    /// Indicates if any conversion failed and fallback currency is in use
    @Published var hasRateConversionWarning = false

    /// Current focus goal for execution (earliest deadline with remaining amount)
    @Published var currentFocusGoal: ExecutionFocusGoal?

    // MARK: - Computed Properties

    /// Whether we can undo the last state change
    var canUndo: Bool {
        executionRecord?.canUndo ?? false
    }

    /// Goal snapshots shown in the UI (live for active months, frozen for closed months)
    var displayGoalSnapshots: [ExecutionGoalSnapshot] {
        guard let record = executionRecord else { return [] }

        if isClosed {
            return snapshot?.goalSnapshots ?? []
        }

        // Active months: build from live MonthlyPlans but preserve goal names/flex state from the baseline snapshot when available.
        let goalIds = goalIds(for: record)
        let baseline = Dictionary(uniqueKeysWithValues: (snapshot?.goalSnapshots ?? []).map { ($0.goalId, $0) })

        return goalIds.compactMap { goalId in
            if let plan = livePlansByGoal[goalId] {
                let base = baseline[goalId]
                return ExecutionGoalSnapshot(
                    goalId: goalId,
                    goalName: base?.goalName ?? "Goal",
                    plannedAmount: plan.effectiveAmount,
                    currency: plan.currency,
                    flexState: plan.flexStateRawValue,
                    isSkipped: plan.isSkipped,
                    isProtected: plan.isProtected
                )
            } else if let base = baseline[goalId] {
                // Fallback to baseline if plan not found (should not happen)
                return base
            }
            return nil
        }
    }

    /// Active (unfulfilled) goals
    var activeGoals: [ExecutionGoalSnapshot] {
        displayGoalSnapshots.filter { snapshot in
            !(fulfillmentStatus[snapshot.goalId] ?? false) && !snapshot.isSkipped
        }
    }

    /// Completed (fulfilled) goals
    var completedGoals: [ExecutionGoalSnapshot] {
        displayGoalSnapshots.filter { snapshot in
            fulfillmentStatus[snapshot.goalId] ?? false
        }
    }

    /// User-friendly status display
    var statusDisplay: String {
        switch executionRecord?.status {
        case .draft:
            return "Planning"
        case .executing:
            return "Active This Month"
        case .closed:
            return "Completed"
        case .none:
            return "Not Started"
        }
    }

    /// Status icon
    var statusIcon: String {
        executionRecord?.status.icon ?? "circle"
    }

    /// Whether the record is active
    var isActive: Bool {
        executionRecord?.status == .executing
    }

    /// Whether the record is closed
    var isClosed: Bool {
        executionRecord?.status == .closed
    }

    // MARK: - Dependencies

    private let executionService: ExecutionTrackingService
    private let modelContext: ModelContext
    private let progressCache = ExecutionProgressCache()
    private let contributionCalculator: ExecutionContributionCalculator
    @Published private(set) var livePlansByGoal: [UUID: MonthlyPlan] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        self.contributionCalculator = ExecutionContributionCalculator(exchangeRateService: DIContainer.shared.exchangeRateService)
        let savedCurrency = UserDefaults.standard.string(forKey: DisplayCurrencyKeys.executionDisplayCurrency)
        self.displayCurrency = savedCurrency ?? MonthlyPlanningSettings.shared.displayCurrency

        setupObservers()
    }

    // MARK: - Public Methods

    /// Load execution record for the active month (fallback to current month)
    func loadCurrentMonth() async {
        isLoading = true
        error = nil

        do {
            let record = try executionService.getActiveRecord() ?? executionService.getCurrentMonthRecord()
            executionRecord = record
            if let record = record {
                // Backfill missing metadata on older records so undo + goal tracking work
                if record.status == .executing {
                    if record.startedAt == nil {
                        record.startedAt = Date()
                        record.canUndoUntil = Date().addingTimeInterval(24 * 3600)
                        try? modelContext.save()
                    }
                    if record.goalIds.isEmpty, let snap = record.snapshot {
                        if let encoded = try? JSONEncoder().encode(snap.goalSnapshots.map { $0.goalId }) {
                            record.trackedGoalIds = encoded
                            try? modelContext.save()
                        }
                    }
                }

                snapshot = record.snapshot
                await loadContributedTotals(for: record)
                await calculateProgress(for: record)
                await refreshRemainingDisplayAmounts()
                await refreshCurrentFocusGoal()

                // Check undo state
                let (shouldShowUndo, deadline) = undoState(for: record)
                showUndoBanner = shouldShowUndo
                undoExpiresAt = deadline
            }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Start tracking for current month
    /// - Parameters:
    ///   - plans: Monthly plans to track
    ///   - goals: Goals corresponding to the plans
    func startTracking(plans: [MonthlyPlan], goals: [Goal]) async {
        isLoading = true
        error = nil

        do {
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            let record = try executionService.startTracking(for: monthLabel, from: plans, goals: goals)

            executionRecord = record
            snapshot = record.snapshot

            // Show undo banner
            showUndoBanner = true
            undoExpiresAt = record.canUndoUntil

            await loadContributedTotals(for: record)
            await calculateProgress(for: record)
            await refreshCurrentFocusGoal()

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Mark month as complete
    func markComplete() async {
        guard let record = executionRecord else { return }

        isLoading = true
        error = nil

        do {
            try await executionService.markComplete(record)

            // Refresh data
            await loadCurrentMonth()

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Undo last state change
    func undoStateChange() async {
        guard let record = executionRecord else { return }

        isLoading = true
        error = nil

        do {
            if record.status == .closed {
                try executionService.undoCompletion(record)
            } else if record.status == .executing {
                try executionService.undoStartTracking(record)
            }

            // Hide undo banner
            showUndoBanner = false
            undoExpiresAt = nil

            // Refresh data
            await loadCurrentMonth()

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Refresh all data
    func refresh() async {
        await loadCurrentMonth()
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Listen for goal updates
        NotificationCenter.default.publisher(for: .goalUpdated)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.progressCache.invalidate()
                    await self.refresh()
                }
            }
            .store(in: &cancellables)

        // Listen for plan recalculations triggered by planning pipeline (e.g., asset changes)
        NotificationCenter.default.publisher(for: .monthlyPlanningGoalUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                if let record = self.executionRecord,
                   let ids = notification.userInfo?["goalIds"] as? [UUID] {
                    let relevant = Set(ids).intersection(Set(record.goalIds))
                    if relevant.isEmpty { return }
                }
                Task { @MainActor in
                    self.progressCache.invalidate()
                    await self.refresh()
                }
            }
            .store(in: &cancellables)

        // Listen for planning updates that should flow into execution for active months
        NotificationCenter.default.publisher(for: .monthlyPlanningAssetUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                // If payload includes goalIds and none intersect this execution, skip refresh
                if let record = self.executionRecord,
                   let ids = notification.userInfo?["goalIds"] as? [UUID] {
                    let relevant = Set(ids).intersection(Set(record.goalIds))
                    if relevant.isEmpty { return }
                }
                Task { @MainActor in
                    self.progressCache.invalidate()
                    await self.refresh()
                }
            }
            .store(in: &cancellables)
    }

    private func loadContributedTotals(for record: MonthlyExecutionRecord) async {
        do {
            contributedTotals = try await progressCache.totals(for: record.id) {
                try await self.executionService.getContributionTotals(for: record)
            }
        } catch {
            self.error = error
        }
    }

    private func calculateProgress(for record: MonthlyExecutionRecord) async {
        do {
            let totals = contributedTotals

            if record.status == .closed {
                // Closed months: rely on the frozen baseline snapshot
                guard let snapshot = record.snapshot else { return }
                livePlansByGoal = [:]

                var status: [UUID: Bool] = [:]
                for goalSnapshot in snapshot.goalSnapshots {
                    let contributed = totals[goalSnapshot.goalId] ?? 0
                    status[goalSnapshot.goalId] = contributed >= goalSnapshot.plannedAmount
                }
                fulfillmentStatus = status

                overallProgress = snapshot.totalPlanned > 0
                    ? (totals.values.reduce(0, +) / snapshot.totalPlanned) * 100
                    : 0
            } else {
                // Active months: compute live from persisted MonthlyPlans
                let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
                let plans = try planService.fetchPlans(for: record.monthLabel)
                livePlansByGoal = Dictionary(uniqueKeysWithValues: plans.map { ($0.goalId, $0) })
                let goalIds = goalIds(for: record, baseline: snapshot)

                var status: [UUID: Bool] = [:]
                var totalPlanned: Double = 0

                for plan in plans where goalIds.contains(plan.goalId) {
                    let plannedAmount = plan.effectiveAmount
                    if plannedAmount <= 0 {
                        status[plan.goalId] = false
                        continue
                    }

                    totalPlanned += plannedAmount
                    let contributed = totals[plan.goalId] ?? 0
                    status[plan.goalId] = contributed >= plannedAmount
                }

                fulfillmentStatus = status
                overallProgress = totalPlanned > 0
                    ? (totals.values.reduce(0, +) / totalPlanned) * 100
                    : 0
            }
        } catch {
            self.error = error
        }
    }

    func remainingToClose(for snapshot: ExecutionGoalSnapshot) -> Double {
        let contributed = contributedTotals[snapshot.goalId] ?? 0
        return contributionCalculator.remainingToClose(goalSnapshot: snapshot, contributed: contributed)
    }

    func remainingDisplayAmount(for snapshot: ExecutionGoalSnapshot) -> Double? {
        remainingByGoalInDisplayCurrency[snapshot.goalId]
    }

    func remainingDisplayCurrency(for snapshot: ExecutionGoalSnapshot) -> String {
        remainingDisplayCurrencyByGoal[snapshot.goalId] ?? displayCurrency
    }

    func suggestedDepositAmount(
        for assetCurrency: String,
        goalSnapshot: ExecutionGoalSnapshot
    ) async -> Double? {
        let remaining = remainingToClose(for: goalSnapshot)
        guard remaining > 0 else { return nil }
        return await contributionCalculator.convertAmount(
            remaining,
            from: goalSnapshot.currency,
            to: assetCurrency
        )
    }

    func assetsForContribution(goalId: UUID) -> [Asset] {
        let assets = (try? modelContext.fetch(FetchDescriptor<Asset>())) ?? []
        let allocated = assets.filter { asset in
            asset.allocations.contains(where: { $0.goal?.id == goalId })
        }
        return allocated.isEmpty ? assets : allocated
    }

    private func refreshRemainingDisplayAmounts() async {
        let snapshots = displayGoalSnapshots
        guard !snapshots.isEmpty else {
            remainingByGoalInDisplayCurrency = [:]
            remainingDisplayCurrencyByGoal = [:]
            hasRateConversionWarning = false
            displayRateUpdatedAt = nil
            currentFocusGoal = nil
            return
        }

        var updated: [UUID: Double] = [:]
        var currencies: [UUID: String] = [:]
        var rateCache: [String: Double] = [:]
        var hadWarning = false

        for snapshot in snapshots {
            let remaining = remainingToClose(for: snapshot)
            if remaining <= 0 {
                updated[snapshot.goalId] = 0
                currencies[snapshot.goalId] = displayCurrency
                continue
            }

            if snapshot.currency.uppercased() == displayCurrency.uppercased() {
                updated[snapshot.goalId] = remaining
                currencies[snapshot.goalId] = displayCurrency
                continue
            }

            let key = "\(snapshot.currency.uppercased())->\(displayCurrency.uppercased())"
            let rate: Double
            if let cached = rateCache[key] {
                rate = cached
            } else {
                do {
                    rate = try await DIContainer.shared.exchangeRateService.fetchRate(
                        from: snapshot.currency,
                        to: displayCurrency
                    )
                    rateCache[key] = rate
                } catch {
                    AppLog.warning("Execution display conversion failed \(key): \(error)", category: .exchangeRate)
                    updated[snapshot.goalId] = remaining
                    currencies[snapshot.goalId] = snapshot.currency
                    hadWarning = true
                    continue
                }
            }
            updated[snapshot.goalId] = remaining * rate
            currencies[snapshot.goalId] = displayCurrency
        }

        remainingByGoalInDisplayCurrency = updated
        remainingDisplayCurrencyByGoal = currencies
        hasRateConversionWarning = hadWarning
        displayRateUpdatedAt = Date()
    }

    private func refreshCurrentFocusGoal() async {
        guard executionRecord?.status == .executing else {
            currentFocusGoal = nil
            return
        }

        let snapshots = displayGoalSnapshots.filter { snapshot in
            !snapshot.isSkipped && remainingToClose(for: snapshot) > 0.01
        }
        guard !snapshots.isEmpty else {
            currentFocusGoal = nil
            return
        }

        let allGoals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        let goalsById = Dictionary(uniqueKeysWithValues: allGoals.map { ($0.id, $0) })

        let candidates = snapshots.compactMap { snapshot -> ExecutionFocusGoal? in
            guard let goal = goalsById[snapshot.goalId] else { return nil }
            return ExecutionFocusGoal(goalName: snapshot.goalName, deadline: goal.deadline)
        }

        currentFocusGoal = candidates.min(by: { $0.deadline < $1.deadline })
    }
}

private enum DisplayCurrencyKeys {
    static let executionDisplayCurrency = "Execution.DisplayCurrency"
}

// MARK: - Helper Types

struct MonthlyExecutionStatistics {
    let totalPlanned: Double
    let totalContributed: Double
    let percentageComplete: Double
    let goalsCount: Int
    let fulfilledCount: Int
    let remainingAmount: Double

    init(totalPlanned: Double, totals: [UUID: Double], fulfillment: [UUID: Bool], goalsCount: Int) {
        self.totalPlanned = totalPlanned
        self.totalContributed = totals.values.reduce(0, +)
        self.percentageComplete = totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
        self.goalsCount = goalsCount
        self.fulfilledCount = fulfillment.values.filter { $0 }.count
        self.remainingAmount = max(0, totalPlanned - totalContributed)
    }
}

struct ExecutionFocusGoal: Equatable {
    let goalName: String
    let deadline: Date
}

// MARK: - Goal Progress Helper

extension MonthlyExecutionViewModel {

    /// Get progress for a specific goal
    func progress(for goalId: UUID) -> Double {
        let planned = plannedAmount(for: goalId)
        if planned == 0 { return 0 }
        let contributed = contributedTotals[goalId] ?? 0
        return (contributed / planned) * 100
    }

    /// Get remaining amount for a specific goal
    func remaining(for goalId: UUID) -> Double {
        let planned = plannedAmount(for: goalId)
        let contributed = contributedTotals[goalId] ?? 0
        return max(0, planned - contributed)
    }

    /// Check if goal is fulfilled
    func isFulfilled(_ goalId: UUID) -> Bool {
        fulfillmentStatus[goalId] ?? false
    }

    /// Planned amount source based on execution state
    private func plannedAmount(for goalId: UUID) -> Double {
        if isClosed {
            return snapshot?.snapshot(for: goalId)?.plannedAmount ?? 0
        }
        return livePlansByGoal[goalId]?.effectiveAmount ?? snapshot?.snapshot(for: goalId)?.plannedAmount ?? 0
    }

    /// Total planned for display (live for active, snapshot for closed)
    var displayTotalPlanned: Double {
        if isClosed {
            return snapshot?.totalPlanned ?? 0
        }
        guard let record = executionRecord else { return snapshot?.totalPlanned ?? 0 }
        let trackedGoalIds = Set(goalIds(for: record, baseline: snapshot))
        let liveTotal = livePlansByGoal
            .filter { trackedGoalIds.contains($0.key) && !$0.value.isSkipped }
            .values
            .reduce(0) { $0 + $1.effectiveAmount }
        return liveTotal > 0 ? liveTotal : (snapshot?.totalPlanned ?? 0)
    }

    /// Count of goals for display (live for active, snapshot for closed)
    var displayGoalCount: Int {
        if isClosed {
            return snapshot?.activeGoalCount ?? 0
        }
        guard let record = executionRecord else { return snapshot?.activeGoalCount ?? 0 }
        let trackedGoalIds = Set(goalIds(for: record, baseline: snapshot))
        let liveCount = livePlansByGoal.values.filter { plan in
            trackedGoalIds.contains(plan.goalId) && !plan.isSkipped
        }.count
        return liveCount > 0 ? liveCount : (snapshot?.activeGoalCount ?? 0)
    }

    /// Total remaining for display currency (nil if any goal falls back to its own currency)
    var displayTotalRemaining: Double? {
        let snapshots = displayGoalSnapshots
        guard !snapshots.isEmpty else { return nil }
        var total: Double = 0
        for snapshot in snapshots {
            guard let amount = remainingByGoalInDisplayCurrency[snapshot.goalId] else { return nil }
            let currency = remainingDisplayCurrencyByGoal[snapshot.goalId] ?? displayCurrency
            guard currency.uppercased() == displayCurrency.uppercased() else { return nil }
            total += amount
        }
        return total
    }

    /// Total contributed across all goals
    var totalContributed: Double {
        contributedTotals.values.reduce(0, +)
    }

    /// Determine undo state (keeps banner alive even if older records lacked canUndoUntil)
    private func undoState(for record: MonthlyExecutionRecord) -> (Bool, Date?) {
        if record.canUndo {
            return (true, record.canUndoUntil)
        }

        // Grace: if executing and started within 24h but canUndoUntil missing, infer deadline
        if record.status == .executing,
           let startedAt = record.startedAt {
            let inferredDeadline = startedAt.addingTimeInterval(24 * 3600)
            if Date() < inferredDeadline {
                return (true, inferredDeadline)
            }
        }

        // Grace: if closed and completedAt within 24h but canUndoUntil missing, infer deadline
        if record.status == .closed,
           let completedAt = record.completedAt {
            let inferredDeadline = completedAt.addingTimeInterval(24 * 3600)
            if Date() < inferredDeadline {
                return (true, inferredDeadline)
            }
        }

        return (false, nil)
    }

    /// Derive goal IDs for the record, falling back to the snapshot if trackedGoalIds was empty
    private func goalIds(for record: MonthlyExecutionRecord, baseline: ExecutionSnapshot? = nil) -> [UUID] {
        if !record.goalIds.isEmpty {
            return record.goalIds
        }
        return baseline?.goalSnapshots.map { $0.goalId } ?? []
    }

}
