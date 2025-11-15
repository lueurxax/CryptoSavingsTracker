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

    /// Contributions for this month
    @Published var contributions: [Contribution] = []

    /// Contributions grouped by goal
    @Published var contributionsByGoal: [UUID: [Contribution]] = [:]

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

    // MARK: - Computed Properties

    /// Whether we can undo the last state change
    var canUndo: Bool {
        executionRecord?.canUndo ?? false
    }

    /// Active (unfulfilled) goals
    var activeGoals: [ExecutionGoalSnapshot] {
        snapshot?.goalSnapshots.filter { snapshot in
            !(fulfillmentStatus[snapshot.goalId] ?? false) && !snapshot.isSkipped
        } ?? []
    }

    /// Completed (fulfilled) goals
    var completedGoals: [ExecutionGoalSnapshot] {
        snapshot?.goalSnapshots.filter { snapshot in
            fulfillmentStatus[snapshot.goalId] ?? false
        } ?? []
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
    private let contributionService: ContributionService
    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        self.contributionService = DIContainer.shared.makeContributionService(modelContext: modelContext)

        setupObservers()
    }

    // MARK: - Public Methods

    /// Load execution record for current month
    func loadCurrentMonth() async {
        isLoading = true
        error = nil

        do {
            let record = try executionService.getCurrentMonthRecord()
            executionRecord = record

            if let record = record {
                snapshot = record.snapshot
                await loadContributions(for: record)
                await calculateProgress(for: record)

                // Check undo state
                if record.canUndo {
                    showUndoBanner = true
                    undoExpiresAt = record.canUndoUntil
                } else {
                    showUndoBanner = false
                    undoExpiresAt = nil
                }
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

            await loadContributions(for: record)
            await calculateProgress(for: record)

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
            try executionService.markComplete(record)

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
                Task { @MainActor in
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    private func loadContributions(for record: MonthlyExecutionRecord) async {
        do {
            let allContributions = try executionService.getContributions(for: record)
            contributions = allContributions

            contributionsByGoal = try executionService.getContributionsByGoal(for: record)
            contributedTotals = try executionService.getContributionTotals(for: record)
        } catch {
            self.error = error
        }
    }

    private func calculateProgress(for record: MonthlyExecutionRecord) async {
        do {
            overallProgress = try executionService.calculateProgress(for: record)

            // Calculate fulfillment status
            guard let snapshot = record.snapshot else { return }
            let totals = contributedTotals

            var status: [UUID: Bool] = [:]
            for goalSnapshot in snapshot.goalSnapshots {
                let contributed = totals[goalSnapshot.goalId] ?? 0
                status[goalSnapshot.goalId] = contributed >= goalSnapshot.plannedAmount
            }
            fulfillmentStatus = status
        } catch {
            self.error = error
        }
    }
}

// MARK: - Helper Types

struct MonthlyExecutionStatistics {
    let totalPlanned: Double
    let totalContributed: Double
    let percentageComplete: Double
    let goalsCount: Int
    let fulfilledCount: Int
    let remainingAmount: Double

    init(snapshot: ExecutionSnapshot?, totals: [UUID: Double], fulfillment: [UUID: Bool]) {
        self.totalPlanned = snapshot?.totalPlanned ?? 0
        self.totalContributed = totals.values.reduce(0, +)
        self.percentageComplete = totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
        self.goalsCount = snapshot?.goalCount ?? 0
        self.fulfilledCount = fulfillment.values.filter { $0 }.count
        self.remainingAmount = max(0, totalPlanned - totalContributed)
    }
}

// MARK: - Goal Progress Helper

extension MonthlyExecutionViewModel {

    /// Get progress for a specific goal
    func progress(for goalId: UUID) -> Double {
        guard let snapshot = snapshot?.snapshot(for: goalId) else { return 0 }
        let contributed = contributedTotals[goalId] ?? 0
        return snapshot.plannedAmount > 0 ? (contributed / snapshot.plannedAmount) * 100 : 0
    }

    /// Get remaining amount for a specific goal
    func remaining(for goalId: UUID) -> Double {
        guard let snapshot = snapshot?.snapshot(for: goalId) else { return 0 }
        let contributed = contributedTotals[goalId] ?? 0
        return max(0, snapshot.plannedAmount - contributed)
    }

    /// Check if goal is fulfilled
    func isFulfilled(_ goalId: UUID) -> Bool {
        fulfillmentStatus[goalId] ?? false
    }
}
