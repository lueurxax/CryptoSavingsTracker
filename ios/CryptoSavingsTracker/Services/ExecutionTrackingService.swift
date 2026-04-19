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

    /// Fetch completion events across all records (append-only history).
    func getCompletionEvents(limit: Int = 200, offset: Int = 0) throws -> [CompletionEvent] {
        var descriptor = FetchDescriptor<CompletionEvent>(
            sortBy: [
                SortDescriptor(\.monthLabel, order: .reverse),
                SortDescriptor(\.sequence, order: .reverse),
                SortDescriptor(\.completedAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try modelContext.fetch(descriptor)
    }

    /// One-time deterministic backfill:
    /// create a completion event for closed records that have immutable completion snapshots
    /// but no event history yet.
    @discardableResult
    func backfillCompletionEventsIfNeeded() throws -> Int {
        let records = try getAllRecords()
        var inserted = 0

        for record in records {
            guard record.status == .closed else { continue }
            if !(record.completionEvents ?? []).isEmpty { continue }
            guard let snapshot = record.completedExecution else {
                AppLog.warning(
                    "Skipping CompletionEvent backfill for \(record.monthLabel): missing completedExecution snapshot.",
                    category: .executionTracking
                )
                continue
            }

            let event = CompletionEvent(
                executionRecord: record,
                sequence: 1,
                sourceDiscriminator: snapshot.id.uuidString,
                completedAt: snapshot.completedAt,
                completionSnapshot: snapshot
            )
            modelContext.insert(event)
            inserted += 1
        }

        if inserted > 0 {
            try modelContext.save()
        }
        return inserted
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

    func ensureRuntimeMetadata(for record: MonthlyExecutionRecord) throws {
        guard record.status == .executing else { return }

        var didChange = false
        if record.startedAt == nil {
            record.startedAt = Date()
            record.canUndoUntil = Date().addingTimeInterval(24 * 3600)
            didChange = true
        }
        if record.goalIds.isEmpty,
           let snapshot = record.snapshot,
           let encoded = try? JSONEncoder().encode(snapshot.goalSnapshots.map { $0.goalId }) {
            record.trackedGoalIds = encoded
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
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
                    existing.startTracking(undoWindowHours: undoWindowHours())
                } else if existing.status == .executing && existing.startedAt == nil {
                    // Older records may not have start time/undo window populated
                    existing.startedAt = Date()
                    existing.canUndoUntil = Date().addingTimeInterval(TimeInterval(undoWindowHours() * 3600))
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
        record.startTracking(undoWindowHours: undoWindowHours())

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
                for allocation in (asset.allocations ?? []) {
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
        #if DEBUG
        if UITestFlags.isEnabled {
            record.markComplete(undoWindowHours: undoWindowHours())
            try modelContext.save()
            // Post notification synchronously (we're already on MainActor)
            NotificationCenter.default.post(name: .monthlyExecutionCompleted, object: record)
            return
        }
        #endif

        record.markComplete(undoWindowHours: undoWindowHours())
        let completedAt = record.completedAt ?? Date()

        // Snapshot derived contributions for immutability in history views.
        let (exchangeRatesSnapshot, contributionSnapshots) = try await buildCompletedExecutionSnapshot(for: record, end: completedAt)
        let completionSnapshot = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: completedAt,
            exchangeRatesSnapshot: exchangeRatesSnapshot,
            goalSnapshots: record.snapshot?.goalSnapshots ?? [],
            contributionSnapshots: contributionSnapshots
        )
        record.completedExecution = completionSnapshot

        let completionEvent = CompletionEvent(
            executionRecord: record,
            sequence: nextCompletionSequence(for: record),
            sourceDiscriminator: completionSnapshot.id.uuidString,
            completedAt: completedAt,
            completionSnapshot: completionSnapshot
        )
        modelContext.insert(completionSnapshot)
        modelContext.insert(completionEvent)

        try modelContext.save()
        // Post notification on main actor for SwiftUI state updates
        await MainActor.run {
            NotificationCenter.default.post(name: .monthlyExecutionCompleted, object: record)
        }
    }

    /// Undo completion (within grace period)
    func undoCompletion(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        guard record.status == .closed else {
            throw ExecutionError.invalidState
        }
        record.undoCompletion()
        if let latest = latestOpenCompletionEvent(for: record) {
            latest.undoneAt = Date()
            latest.undoReason = "manualUndo"
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

    func getAllRecords() throws -> [MonthlyExecutionRecord] {
        let descriptor = FetchDescriptor<MonthlyExecutionRecord>(
            sortBy: [SortDescriptor(\.monthLabel, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
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

    private func undoWindowHours() -> Int {
        max(0, MonthlyPlanningSettings.shared.undoGracePeriodHours)
    }

    private func nextCompletionSequence(for record: MonthlyExecutionRecord) -> Int {
        ((record.completionEvents ?? []).map(\.sequence).max() ?? 0) + 1
    }

    private func latestOpenCompletionEvent(for record: MonthlyExecutionRecord) -> CompletionEvent? {
        (record.completionEvents ?? [])
            .filter { $0.undoneAt == nil }
            .sorted { lhs, rhs in
                if lhs.sequence == rhs.sequence {
                    return lhs.completedAt > rhs.completedAt
                }
                return lhs.sequence > rhs.sequence
            }
            .first
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
