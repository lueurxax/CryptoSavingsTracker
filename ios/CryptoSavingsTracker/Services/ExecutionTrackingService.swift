//
//  ExecutionTrackingService.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Manages monthly execution lifecycle and contribution tracking
//

import SwiftData
import Foundation

@MainActor
final class ExecutionTrackingService {
    let modelContext: ModelContext
    private let exchangeRateService: ExchangeRateServiceProtocol

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.exchangeRateService = DIContainer.shared.exchangeRateService
    }

    // MARK: - Execution Record Management

    /// Get or create execution record for current month
    func getCurrentMonthRecord() throws -> MonthlyExecutionRecord? {
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        return try getRecord(for: monthLabel)
    }

    /// Get execution record for specific month
    func getRecord(for monthLabel: String) throws -> MonthlyExecutionRecord? {
        let predicate = #Predicate<MonthlyExecutionRecord> { record in
            record.monthLabel == monthLabel
        }

        let descriptor = FetchDescriptor<MonthlyExecutionRecord>(predicate: predicate)
        let records = try modelContext.fetch(descriptor)
        return records.first
    }

    /// Get all completed execution records (for history)
    func getCompletedRecords(limit: Int = 10, offset: Int = 0) throws -> [MonthlyExecutionRecord] {
        let predicate = #Predicate<MonthlyExecutionRecord> { record in
            record.statusRawValue == "closed"
        }

        var descriptor = FetchDescriptor<MonthlyExecutionRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.monthLabel, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        return try modelContext.fetch(descriptor)
    }

    /// Get active (executing) record
    func getActiveRecord() throws -> MonthlyExecutionRecord? {
        let predicate = #Predicate<MonthlyExecutionRecord> { record in
            record.statusRawValue == "executing"
        }

        let descriptor = FetchDescriptor<MonthlyExecutionRecord>(predicate: predicate)
        let records = try modelContext.fetch(descriptor)
        return records.first
    }

    // MARK: - Lifecycle Operations

    /// Create execution record from current monthly plans
    func startTracking(
        for monthLabel: String,
        from plans: [MonthlyPlan],
        goals: [Goal]
    ) throws -> MonthlyExecutionRecord {
        AppLog.info("Starting execution tracking for month: \(monthLabel)", category: .executionTracking)

        // Check if record already exists
        if let existing = try getRecord(for: monthLabel) {
            if existing.status == .draft || existing.status == .executing {
                if let completed = existing.completedExecution {
                    modelContext.delete(completed)
                    existing.completedExecution = nil
                }

                // Always refresh snapshot from current plans to reflect latest adjustments
                let goalIds = plans.map { $0.goalId }
                if let encoded = try? JSONEncoder().encode(goalIds) {
                    existing.trackedGoalIds = encoded
                }

                let validPlans = plans.filter { plan in
                    let hasValidAmount = plan.effectiveAmount > 0 || plan.requiredMonthly > 0
                    return hasValidAmount
                }

                let snapshot = ExecutionSnapshot.create(from: validPlans, goals: goals)
                existing.snapshot = snapshot

                // Verify the snapshot
                if let decodedSnapshots = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshot.snapshotData) {
                    for _ in decodedSnapshots {
                    }
                }

                // Transition to executing if needed
                if existing.status == .draft {
                    existing.startTracking()
                } else if existing.status == .executing && existing.startedAt == nil {
                    // Older records may not have start time/undo window populated
                    existing.startedAt = Date()
                    existing.canUndoUntil = Date().addingTimeInterval(24 * 3600)
                }

                if let startedAt = existing.startedAt {
                    seedAllocationHistoryBaseline(goals: goals, at: startedAt)
                }

                try modelContext.save()
                return existing
            } else {
                throw ExecutionError.recordAlreadyExists
            }
        }

        // Create new record
        let goalIds = plans.map { $0.goalId }
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: goalIds)

        // Create snapshot using factory method (ensures proper SwiftData initialization)

        // Ensure we have valid plans with data
        let validPlans = plans.filter { plan in
            let hasValidAmount = plan.effectiveAmount > 0 || plan.requiredMonthly > 0
            return hasValidAmount
        }


        let snapshot = ExecutionSnapshot.create(from: validPlans, goals: goals)

        // Verify snapshot data
        if let decodedSnapshots = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshot.snapshotData) {
            for _ in decodedSnapshots {
            }
        } else {
            AppLog.error("Failed to decode snapshot data for verification!", category: .executionTracking)
        }

        record.snapshot = snapshot

        // Start tracking
        record.startTracking()

        modelContext.insert(record)
        if let startedAt = record.startedAt {
            seedAllocationHistoryBaseline(goals: goals, at: startedAt)
        }
        try modelContext.save()

        AppLog.info("Execution tracking started successfully for \(monthLabel)", category: .executionTracking)
        return record
    }

    private func seedAllocationHistoryBaseline(goals: [Goal], at timestamp: Date) {
        let goalIds = Set(goals.map(\.id))

        // Best-effort: don't fail start tracking if seeding fails.
        do {
            let allAssets = try modelContext.fetch(FetchDescriptor<Asset>())
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: timestamp)

            let existingBaselinePredicate = #Predicate<AllocationHistory> { history in
                history.monthLabel == monthLabel && history.timestamp == timestamp
            }
            let existingBaseline = (try? modelContext.fetch(FetchDescriptor<AllocationHistory>(predicate: existingBaselinePredicate))) ?? []

            var baselineEntries: [(asset: Asset, goal: Goal, amount: Double)] = []
            baselineEntries.reserveCapacity(allAssets.count)

            for asset in allAssets {
                for allocation in asset.allocations {
                    guard let goal = allocation.goal, goalIds.contains(goal.id) else { continue }
                    let amount = allocation.amountValue
                    baselineEntries.append((asset: asset, goal: goal, amount: amount))
                }
            }

            let existingBaselineHasMissingIds = existingBaseline.contains { $0.assetId == nil || $0.goalId == nil }
            if !baselineEntries.isEmpty, existingBaseline.count == baselineEntries.count, !existingBaselineHasMissingIds {
                return
            }

            for history in existingBaseline {
                modelContext.delete(history)
            }

            for entry in baselineEntries {
                modelContext.insert(AllocationHistory(asset: entry.asset, goal: entry.goal, amount: entry.amount, timestamp: timestamp))
            }
        } catch {
            AppLog.warning("AllocationHistory baseline seeding failed: \(error)", category: .executionTracking)
        }
    }

    /// Mark month as complete
    func markComplete(_ record: MonthlyExecutionRecord) async throws {
        record.markComplete()
        let completedAt = record.completedAt ?? Date()

        // Snapshot derived contributions for immutability in history views.
        let (exchangeRatesSnapshot, contributionSnapshots) = try await buildCompletedExecutionSnapshot(for: record, end: completedAt)
        if let existing = record.completedExecution {
            modelContext.delete(existing)
            record.completedExecution = nil
        }
        record.completedExecution = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: completedAt,
            exchangeRatesSnapshot: exchangeRatesSnapshot,
            goalSnapshots: record.snapshot?.goalSnapshots ?? [],
            contributionSnapshots: contributionSnapshots
        )

        try modelContext.save()
        NotificationCenter.default.post(name: .monthlyExecutionCompleted, object: record)
    }

    /// Undo completion (within grace period)
    func undoCompletion(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        record.undoCompletion()
        if let completed = record.completedExecution {
            modelContext.delete(completed)
            record.completedExecution = nil
        }
        try modelContext.save()
    }

    /// Undo start tracking (within grace period)
    func undoStartTracking(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        record.undoStartTracking()
        try modelContext.save()
    }

    // MARK: - Contribution Totals (Timestamp-Based)

    /// Total contributed per goal in goal currency.
    /// - For active months: derived from transactions + allocation history timestamps using current rates.
    /// - For closed months: uses the immutable completion snapshot.
    func getContributionTotals(for record: MonthlyExecutionRecord) async throws -> [UUID: Double] {
        if record.status == .closed, let completed = record.completedExecution {
            return completed.contributedTotalsByGoalId
        }
        guard record.status == .executing else { return [:] }
        let calculator = ExecutionProgressCalculator(modelContext: modelContext, exchangeRateService: exchangeRateService)
        return try await calculator.contributionTotalsInGoalCurrency(for: record, end: Date())
    }

    /// Calculate overall progress percentage for a record.
    func calculateProgress(for record: MonthlyExecutionRecord) async throws -> Double {
        let totals = try await getContributionTotals(for: record)
        let totalContributed = totals.values.reduce(0, +)

        if record.status == .closed {
            guard let snapshot = record.snapshot else { return 0 }
            return snapshot.totalPlanned > 0
                ? (totalContributed / snapshot.totalPlanned) * 100
                : 0
        }

        guard record.status == .executing else { return 0 }

        // Active months: compute planned total from persisted MonthlyPlans
        let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        let plans = try planService.fetchPlans(for: record.monthLabel)
        let totalPlanned = plans
            .filter { record.goalIds.contains($0.goalId) }
            .reduce(0) { $0 + $1.effectiveAmount }

        return totalPlanned > 0
            ? (totalContributed / totalPlanned) * 100
            : 0
    }

    /// Fetch goals matching a record's tracked goal IDs
    private func fetchTrackedGoals(for record: MonthlyExecutionRecord) throws -> [Goal] {
        let trackedIds = record.goalIds
        guard !trackedIds.isEmpty else { return [] }

        let predicate = #Predicate<Goal> { goal in
            trackedIds.contains(goal.id)
        }
        let descriptor = FetchDescriptor<Goal>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Helper Methods

    /// Delete execution record (use with caution)
    func deleteRecord(_ record: MonthlyExecutionRecord) throws {
        modelContext.delete(record)
        try modelContext.save()
    }

    /// Count total execution records
    func countRecords() throws -> Int {
        let descriptor = FetchDescriptor<MonthlyExecutionRecord>()
        return try modelContext.fetchCount(descriptor)
    }

    private func buildCompletedExecutionSnapshot(
        for record: MonthlyExecutionRecord,
        end: Date
    ) async throws -> ([String: Double], [CompletedExecutionContributionSnapshot]) {
        guard let startedAt = record.startedAt else { return ([:], []) }
        guard end >= startedAt else { return ([:], []) }

        let calculator = ExecutionProgressCalculator(modelContext: modelContext, exchangeRateService: exchangeRateService)
        let events = try calculator.derivedEvents(for: record, end: end)
        guard !events.isEmpty else { return ([:], []) }

        var rateCache: [String: Double] = [:]
        var snapshots: [CompletedExecutionContributionSnapshot] = []
        snapshots.reserveCapacity(events.count)
        let epsilon = 0.0000001

        for event in events where abs(event.assetDelta) > epsilon {
            let amountInGoalCurrency: Double
            let rateUsed: Double

            if event.assetCurrency.uppercased() == event.goalCurrency.uppercased() {
                amountInGoalCurrency = event.assetDelta
                rateUsed = 1
            } else {
                let key = "\(event.assetCurrency.uppercased())->\(event.goalCurrency.uppercased())"
                if let cached = rateCache[key] {
                    rateUsed = cached
                } else {
                    // Best-effort: if rate fails, skip this event to avoid incorrect accounting.
                    rateUsed = (try? await exchangeRateService.fetchRate(from: event.assetCurrency, to: event.goalCurrency)) ?? 0
                    if rateUsed <= 0 {
                        AppLog.warning("Exchange rate missing for \(key) during completion snapshot; skipping contribution event.", category: .exchangeRate)
                        continue
                    }
                    rateCache[key] = rateUsed
                }
                amountInGoalCurrency = event.assetDelta * rateUsed
            }

            snapshots.append(
                CompletedExecutionContributionSnapshot(
                    timestamp: event.timestamp,
                    source: event.source,
                    assetId: event.assetId,
                    assetCurrency: event.assetCurrency,
                    goalId: event.goalId,
                    goalCurrency: event.goalCurrency,
                    assetAmount: event.assetDelta,
                    amountInGoalCurrency: amountInGoalCurrency,
                    exchangeRateUsed: rateUsed
                )
            )
        }

        return (rateCache, snapshots.sorted(by: { $0.timestamp < $1.timestamp }))
    }

    private func fetchAsset(id: UUID) throws -> Asset {
        let predicate = #Predicate<Asset> { asset in asset.id == id }
        let descriptor = FetchDescriptor<Asset>(predicate: predicate)
        guard let asset = try modelContext.fetch(descriptor).first else {
            throw ExecutionError.recordNotFound
        }
        return asset
    }

    private func fetchGoal(id: UUID) throws -> Goal {
        let predicate = #Predicate<Goal> { goal in goal.id == id }
        let descriptor = FetchDescriptor<Goal>(predicate: predicate)
        guard let goal = try modelContext.fetch(descriptor).first else {
            throw ExecutionError.recordNotFound
        }
        return goal
    }
}

// MARK: - Errors

extension ExecutionTrackingService {
    enum ExecutionError: LocalizedError {
        case recordAlreadyExists
        case recordNotFound
        case undoPeriodExpired
        case invalidState

        var errorDescription: String? {
            switch self {
            case .recordAlreadyExists:
                return "An execution record for this month already exists"
            case .recordNotFound:
                return "Execution record not found"
            case .undoPeriodExpired:
                return "The undo grace period has expired"
            case .invalidState:
                return "Invalid state for this operation"
            }
        }
    }
}
