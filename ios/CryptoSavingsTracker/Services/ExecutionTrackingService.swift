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
    private let saveChanges: () throws -> Void
    private let now: () -> Date
    private let makeCompletionEvent: (
        MonthlyExecutionRecord,
        Int,
        Date,
        CompletedExecution
    ) throws -> CompletionEvent

    init(
        modelContext: ModelContext,
        exchangeRateService: ExchangeRateServiceProtocol? = nil,
        saveChanges: (() throws -> Void)? = nil,
        now: @escaping () -> Date = Date.init,
        makeCompletionEvent: ((
            MonthlyExecutionRecord,
            Int,
            Date,
            CompletedExecution
        ) throws -> CompletionEvent)? = nil
    ) {
        self.modelContext = modelContext
        self.exchangeRateService = exchangeRateService ?? DIContainer.shared.exchangeRateService
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.now = now
        self.makeCompletionEvent = makeCompletionEvent ?? {
            record,
            sequence,
            completedAt,
            snapshot in
            CompletionEvent(
                executionRecord: record,
                sequence: sequence,
                sourceDiscriminator: snapshot.id.uuidString,
                completedAt: completedAt,
                completionSnapshot: snapshot
            )
        }
    }

    // MARK: - Execution Record Management

    /// Get or create execution record for current month
    func getCurrentMonthRecord() throws -> MonthlyExecutionRecord? {
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: now())
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
            let startedAt = now()
            record.startedAt = startedAt
            record.canUndoUntil = startedAt.addingTimeInterval(24 * 3600)
            didChange = true
        }
        if record.goalIds.isEmpty,
           let snapshot = record.snapshot,
           let encoded = try? JSONEncoder().encode(
               canonicalActiveGoalIDs(
                   from: snapshot.goalSnapshots.map(\.goalId)
               )
           ) {
            record.trackedGoalIds = encoded
            didChange = true
        }

        if didChange {
            try saveChanges()
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
        let suppliedGoalIDs = Set(goals.map(\.id))
        let activeGoalDescriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.lifecycleStatusRawValue == "active"
            }
        )
        let activeGoals = try modelContext.fetch(activeGoalDescriptor).filter {
            suppliedGoalIDs.contains($0.id)
        }
        let activeGoalIDs = Set(activeGoals.map(\.id))
        let activePlans = plans.filter {
            $0.monthLabel == monthLabel && activeGoalIDs.contains($0.goalId)
        }
        guard !activePlans.isEmpty else {
            throw ExecutionError.invalidState
        }
        guard activePlans.allSatisfy({
            $0.state == .draft
                && ($0.isSkipped || $0.effectiveAmount > 0)
        }) else {
            throw ExecutionError.invalidState
        }

        let goalIDs = activePlans.map(\.goalId)
        guard Set(goalIDs).count == goalIDs.count else {
            throw ExecutionError.invalidState
        }

        let executionSnapshot = try ExecutionSnapshot.create(
            from: activePlans,
            goals: activeGoals
        )
        let existing = try getRecord(for: monthLabel)
        if let existing, existing.status == .closed {
            throw ExecutionError.recordAlreadyExists
        }
        let record = existing ?? MonthlyExecutionRecord(
            monthLabel: monthLabel,
            goalIds: goalIDs
        )
        let recordState = existing.map(ExecutionRecordMutationSnapshot.init)
        let planStates = activePlans.map(ExecutionPlanMutationSnapshot.init)
        let oldSnapshot = existing?.snapshot
        let startedAt = record.startedAt ?? now()
        var insertedRecord = false

        let allowedModels: [any PersistentModel] =
            activePlans.map { $0 as any PersistentModel }
            + [existing].compactMap { $0 as (any PersistentModel)? }
            + [oldSnapshot].compactMap { $0 as (any PersistentModel)? }

        let savedRecord = try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            restoreTouchedState: {
                planStates.forEach { $0.restore() }
                if let recordState {
                    recordState.restore()
                }
                if insertedRecord {
                    PersistenceOperationTransaction.discardInserted(
                        [record],
                        from: self.modelContext
                    )
                }
                PersistenceOperationTransaction.discardInserted(
                    [executionSnapshot],
                    from: self.modelContext
                )
            }
        ) {
            if existing == nil {
                self.modelContext.insert(record)
                insertedRecord = true
            }

            record.trackedGoalIds = try JSONEncoder().encode(goalIDs)
            record.snapshot = executionSnapshot
            if record.status == .draft {
                record.startTracking(
                    at: startedAt,
                    undoWindowHours: self.undoWindowHours()
                )
            } else if record.status == .executing && record.startedAt == nil {
                record.startedAt = startedAt
                record.canUndoUntil = startedAt.addingTimeInterval(
                    TimeInterval(self.undoWindowHours() * 3_600)
                )
            }

            for plan in activePlans {
                plan.state = .executing
                plan.executionRecord = record
            }
            record.plans = activePlans

            try self.seedAllocationHistoryBaseline(
                goals: activeGoals,
                monthLabel: monthLabel,
                at: startedAt
            )
            return record
        }

        AppLog.info("Execution tracking started successfully for \(monthLabel)", category: .executionTracking)
        return savedRecord
    }

    private func seedAllocationHistoryBaseline(
        goals: [Goal],
        monthLabel: String,
        at timestamp: Date
    ) throws {
        let goalIds = Set(goals.map(\.id))
        let allAssets = try modelContext.fetch(FetchDescriptor<Asset>())
        let existingBaselinePredicate = #Predicate<AllocationHistory> { history in
            history.monthLabel == monthLabel && history.timestamp == timestamp
        }
        let existingBaseline = try modelContext.fetch(
            FetchDescriptor<AllocationHistory>(predicate: existingBaselinePredicate)
        )

        var baselineEntries: [(asset: Asset, goal: Goal, amount: Double)] = []
        baselineEntries.reserveCapacity(allAssets.count)
        for asset in allAssets {
            for allocation in (asset.allocations ?? []) {
                guard let goal = allocation.goal, goalIds.contains(goal.id) else { continue }
                baselineEntries.append(
                    (asset: asset, goal: goal, amount: allocation.amountValue)
                )
            }
        }

        let expectedFingerprintCounts = Dictionary(
            grouping: baselineEntries.map {
                AllocationBaselineFingerprint(
                    assetID: $0.asset.id,
                    goalID: $0.goal.id,
                    amount: $0.amount
                )
            },
            by: { $0 }
        ).mapValues(\.count)
        let existingFingerprintCounts = Dictionary(
            grouping: existingBaseline.compactMap {
                history -> AllocationBaselineFingerprint? in
                guard let assetID = history.assetId,
                      let goalID = history.goalId
                else {
                    return nil
                }
                return AllocationBaselineFingerprint(
                    assetID: assetID,
                    goalID: goalID,
                    amount: history.amount
                )
            },
            by: { $0 }
        ).mapValues(\.count)
        if existingBaseline.count == baselineEntries.count,
           existingFingerprintCounts == expectedFingerprintCounts {
            return
        }

        for history in existingBaseline {
            modelContext.delete(history)
        }
        for entry in baselineEntries {
            let history = AllocationHistory(
                asset: entry.asset,
                goal: entry.goal,
                amount: entry.amount,
                timestamp: timestamp
            )
            history.monthLabel = monthLabel
            modelContext.insert(history)
        }
    }

    /// Mark month as complete
    func markComplete(_ record: MonthlyExecutionRecord) async throws {
        guard record.status == .executing else {
            throw ExecutionError.invalidState
        }
        let completedAt = now()
        let canonicalGoalIDs = try canonicalActiveGoalIDs(from: record.goalIds)
        let canonicalGoalIDSet = Set(canonicalGoalIDs)
        let financialInputFingerprint = try completionFinancialInputFingerprint(
            for: record
        )
        let canonicalGoalSnapshots = (record.snapshot?.goalSnapshots ?? []).filter {
            canonicalGoalIDSet.contains($0.goalId)
        }

        // Derive every fallible financial input before mutating the record.
        let (exchangeRatesSnapshot, contributionSnapshots) =
            try await buildCompletedExecutionSnapshot(
                for: record,
                goalIDs: canonicalGoalIDSet,
                end: completedAt
            )
        let refreshedCanonicalGoalIDs = try canonicalActiveGoalIDs(
            from: record.goalIds
        )
        guard record.status == .executing,
              refreshedCanonicalGoalIDs == canonicalGoalIDs
        else {
            throw ExecutionError.executionInputsChanged
        }
        let completionSnapshot = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: completedAt,
            exchangeRatesSnapshot: exchangeRatesSnapshot,
            goalSnapshots: canonicalGoalSnapshots,
            contributionSnapshots: contributionSnapshots
        )

        let plans = try fetchPlans(
            for: record.monthLabel,
            goalIDs: canonicalGoalIDSet
        ).filter { $0.state == .executing }
        let recordState = ExecutionRecordMutationSnapshot(record)
        let planStates = plans.map(ExecutionPlanMutationSnapshot.init)
        let executionSnapshotState = record.snapshot.map(
            ExecutionSnapshotMutationSnapshot.init
        )
        var insertedEvent: CompletionEvent?

        var allowedModels: [any PersistentModel] =
            [record as any PersistentModel]
            + plans.map { $0 as any PersistentModel }
        if let snapshot = record.snapshot {
            allowedModels.append(snapshot)
        }

        guard try completionFinancialInputFingerprint(for: record)
            == financialInputFingerprint
        else {
            throw ExecutionError.executionInputsChanged
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            restoreTouchedState: {
                recordState.restore()
                planStates.forEach { $0.restore() }
                executionSnapshotState?.restore()
                if let insertedEvent {
                    PersistenceOperationTransaction.discardInserted(
                        [insertedEvent],
                        from: self.modelContext
                    )
                }
                PersistenceOperationTransaction.discardInserted(
                    [completionSnapshot],
                    from: self.modelContext
                )
            }
        ) {
            record.trackedGoalIds = try JSONEncoder().encode(canonicalGoalIDs)
            try record.snapshot?.replaceGoalSnapshots(
                with: canonicalGoalSnapshots
            )
            record.markComplete(
                at: completedAt,
                undoWindowHours: self.undoWindowHours()
            )
            for plan in plans {
                plan.state = .completed
            }
            record.completedExecution = completionSnapshot
            self.modelContext.insert(completionSnapshot)

            let event = try self.makeCompletionEvent(
                record,
                self.nextCompletionSequence(for: record),
                completedAt,
                completionSnapshot
            )
            insertedEvent = event
            self.modelContext.insert(event)
        }

        // Post notification on main actor for SwiftUI state updates
        NotificationCenter.default.post(name: .monthlyExecutionCompleted, object: record)
    }

    /// Undo completion (within grace period)
    func undoCompletion(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        guard record.status == .closed else {
            throw ExecutionError.invalidState
        }
        let goalIDs = Set(try canonicalActiveGoalIDs(from: record.goalIds))
        let plans = try fetchPlans(
            for: record.monthLabel,
            goalIDs: goalIDs
        ).filter { $0.state == .completed }
        let latest = latestOpenCompletionEvent(for: record)
        let recordState = ExecutionRecordMutationSnapshot(record)
        let planStates = plans.map(ExecutionPlanMutationSnapshot.init)
        let eventState = latest.map(CompletionEventMutationSnapshot.init)
        var allowedModels: [any PersistentModel] =
            [record as any PersistentModel]
            + plans.map { $0 as any PersistentModel }
        if let latest {
            allowedModels.append(latest)
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            restoreTouchedState: {
                recordState.restore()
                planStates.forEach { $0.restore() }
                eventState?.restore()
            }
        ) {
            record.undoCompletion()
            for plan in plans {
                plan.state = .executing
            }
            latest?.undoneAt = self.now()
            latest?.undoReason = "manualUndo"
        }
    }

    /// Undo start tracking (within grace period)
    func undoStartTracking(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        guard record.status == .executing else {
            throw ExecutionError.invalidState
        }
        let plans = try fetchPlans(
            for: record.monthLabel,
            goalIDs: Set(record.goalIds)
        ).filter { $0.state == .executing }
        let recordState = ExecutionRecordMutationSnapshot(record)
        let planStates = plans.map(ExecutionPlanMutationSnapshot.init)
        let allowedModels: [any PersistentModel] =
            [record as any PersistentModel]
            + plans.map { $0 as any PersistentModel }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            restoreTouchedState: {
                recordState.restore()
                planStates.forEach { $0.restore() }
            }
        ) {
            record.undoStartTracking()
            for plan in plans {
                plan.state = .draft
                plan.executionRecord = nil
            }
            record.plans = []
        }
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
        return try await calculator.contributionTotalsInGoalCurrency(for: record, end: now())
    }

    /// Calculate overall progress percentage for a record.
    func calculateProgress(for record: MonthlyExecutionRecord) async throws -> Double {
        let totals = try await getContributionTotals(for: record)

        if record.status == .closed {
            guard let snapshot = record.snapshot else { return 0 }
            return snapshot.overallCompletion(with: totals)
        }

        guard record.status == .executing else { return 0 }

        // Active months: compute planned total from persisted MonthlyPlans
        let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        let plans = try planService.fetchPlans(for: record.monthLabel)
        let goalIDs = Set(try canonicalActiveGoalIDs(from: record.goalIds))
        let targets = plans
            .filter { goalIDs.contains($0.goalId) }
            .map {
                ExecutionProgressTarget(
                    goalId: $0.goalId,
                    plannedAmount: $0.effectiveAmount,
                    isSkipped: $0.isSkipped
                )
            }
        return ExecutionProgressAggregation.percentage(
            targets: targets,
            contributions: totals
        )
    }

    /// Fetch goals matching a record's tracked goal IDs
    private func fetchTrackedGoals(for record: MonthlyExecutionRecord) throws -> [Goal] {
        let trackedIds = record.goalIds
        guard !trackedIds.isEmpty else { return [] }

        let predicate = #Predicate<Goal> { goal in
            trackedIds.contains(goal.id)
                && goal.lifecycleStatusRawValue == "active"
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
        goalIDs: Set<UUID>,
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

        for event in events where
            goalIDs.contains(event.goalId) && abs(event.assetDelta) > epsilon
        {
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
                    do {
                        rateUsed = try await exchangeRateService.fetchRate(
                            from: event.assetCurrency,
                            to: event.goalCurrency
                        )
                    } catch {
                        throw ExecutionProgressCalculator.CalculationError.exchangeRateUnavailable(
                            from: event.assetCurrency,
                            to: event.goalCurrency
                        )
                    }
                    guard rateUsed.isFinite, rateUsed > 0 else {
                        throw ExecutionProgressCalculator.CalculationError.exchangeRateUnavailable(
                            from: event.assetCurrency,
                            to: event.goalCurrency
                        )
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

    private func canonicalActiveGoalIDs(from candidateIDs: [UUID]) throws -> [UUID] {
        let candidateSet = Set(candidateIDs)
        guard !candidateSet.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.lifecycleStatusRawValue == "active"
            }
        )
        let activeIDs = Set(try modelContext.fetch(descriptor).map(\.id))
        var seen: Set<UUID> = []
        return candidateIDs.filter {
            candidateSet.contains($0)
                && activeIDs.contains($0)
                && seen.insert($0).inserted
        }
    }

    private func fetchPlans(
        for monthLabel: String,
        goalIDs: Set<UUID>
    ) throws -> [MonthlyPlan] {
        guard !goalIDs.isEmpty else { return [] }
        let predicate = #Predicate<MonthlyPlan> { plan in
            plan.monthLabel == monthLabel
        }
        return try modelContext.fetch(
            FetchDescriptor<MonthlyPlan>(predicate: predicate)
        ).filter { goalIDs.contains($0.goalId) }
    }

    private func completionFinancialInputFingerprint(
        for record: MonthlyExecutionRecord
    ) throws -> CompletionFinancialInputFingerprint {
        modelContext.processPendingChanges()

        let trackedGoalIDs = Set(record.goalIds)
        let goals = try modelContext.fetch(FetchDescriptor<Goal>())
            .filter { trackedGoalIDs.contains($0.id) }
        let plans = try modelContext.fetch(FetchDescriptor<MonthlyPlan>())
            .filter {
                $0.monthLabel == record.monthLabel
                    && trackedGoalIDs.contains($0.goalId)
            }
        let allocations = try modelContext.fetch(
            FetchDescriptor<AssetAllocation>()
        ).filter {
            guard let goalID = $0.goal?.id else { return false }
            return trackedGoalIDs.contains(goalID)
        }
        let histories = try modelContext.fetch(
            FetchDescriptor<AllocationHistory>()
        ).filter {
            guard let goalID = $0.goalId else { return false }
            return trackedGoalIDs.contains(goalID)
        }
        let relevantAssetIDs = Set(
            allocations.compactMap { $0.asset?.id }
                + histories.compactMap(\.assetId)
        )
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
            .filter { relevantAssetIDs.contains($0.id) }
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            .filter {
                guard let assetID = $0.asset?.id else { return false }
                return relevantAssetIDs.contains(assetID)
            }

        return CompletionFinancialInputFingerprint(
            record: .init(record),
            goals: goals.map(CompletionGoalInputFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            plans: plans.map(CompletionPlanInputFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            assets: assets.map(CompletionAssetInputFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            transactions: transactions
                .map(CompletionTransactionInputFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            allocations: allocations
                .map(CompletionAllocationInputFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            histories: histories
                .map(CompletionAllocationHistoryInputFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
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

private struct AllocationBaselineFingerprint: Hashable {
    let assetID: UUID
    let goalID: UUID
    let amount: Double
}

private struct CompletionFinancialInputFingerprint: Equatable {
    let record: CompletionRecordInputFingerprint
    let goals: [CompletionGoalInputFingerprint]
    let plans: [CompletionPlanInputFingerprint]
    let assets: [CompletionAssetInputFingerprint]
    let transactions: [CompletionTransactionInputFingerprint]
    let allocations: [CompletionAllocationInputFingerprint]
    let histories: [CompletionAllocationHistoryInputFingerprint]
}

private struct CompletionRecordInputFingerprint: Equatable {
    let id: UUID
    let monthLabel: String
    let statusRawValue: String
    let startedAt: Date?
    let trackedGoalIDs: Data
    let snapshotID: UUID?
    let snapshotTotalPlannedBits: UInt64?
    let snapshotData: Data?

    init(_ record: MonthlyExecutionRecord) {
        id = record.id
        monthLabel = record.monthLabel
        statusRawValue = record.statusRawValue
        startedAt = record.startedAt
        trackedGoalIDs = record.trackedGoalIds
        snapshotID = record.snapshot?.id
        snapshotTotalPlannedBits = record.snapshot?.totalPlanned.bitPattern
        snapshotData = record.snapshot?.snapshotData
    }
}

private struct CompletionGoalInputFingerprint: Equatable {
    let id: UUID
    let currency: String
    let targetAmountBits: UInt64
    let deadline: Date
    let lifecycleStatusRawValue: String
    let lifecycleStatusChangedAt: Date?

    init(_ goal: Goal) {
        id = goal.id
        currency = goal.currency
        targetAmountBits = goal.targetAmount.bitPattern
        deadline = goal.deadline
        lifecycleStatusRawValue = goal.lifecycleStatusRawValue
        lifecycleStatusChangedAt = goal.lifecycleStatusChangedAt
    }
}

private struct CompletionPlanInputFingerprint: Equatable {
    let id: UUID
    let goalID: UUID
    let monthLabel: String
    let requiredMonthlyBits: UInt64
    let remainingAmountBits: UInt64
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let stateRawValue: String
    let customAmountBits: UInt64?
    let flexStateRawValue: String
    let isProtected: Bool
    let isSkipped: Bool
    let executionRecordID: UUID?

    init(_ plan: MonthlyPlan) {
        id = plan.id
        goalID = plan.goalId
        monthLabel = plan.monthLabel
        requiredMonthlyBits = plan.requiredMonthly.bitPattern
        remainingAmountBits = plan.remainingAmount.bitPattern
        monthsRemaining = plan.monthsRemaining
        currency = plan.currency
        statusRawValue = plan.statusRawValue
        stateRawValue = plan.stateRawValue
        customAmountBits = plan.customAmount?.bitPattern
        flexStateRawValue = plan.flexStateRawValue
        isProtected = plan.isProtected
        isSkipped = plan.isSkipped
        executionRecordID = plan.executionRecord?.id
    }
}

private struct CompletionAssetInputFingerprint: Equatable {
    let id: UUID
    let currency: String
    let address: String?
    let chainID: String?
    let currentAmountBits: UInt64

    init(_ asset: Asset) {
        id = asset.id
        currency = asset.currency
        address = asset.address
        chainID = asset.chainId
        currentAmountBits = asset.currentAmount.bitPattern
    }
}

private struct CompletionTransactionInputFingerprint: Equatable {
    let id: UUID
    let assetID: UUID?
    let amountBits: UInt64
    let date: Date
    let sourceRawValue: String
    let externalID: String?

    init(_ transaction: Transaction) {
        id = transaction.id
        assetID = transaction.asset?.id
        amountBits = transaction.amount.bitPattern
        date = transaction.date
        sourceRawValue = transaction.sourceRawValue
        externalID = transaction.externalId
    }
}

private struct CompletionAllocationInputFingerprint: Equatable {
    let id: UUID
    let assetID: UUID?
    let goalID: UUID?
    let amountBits: UInt64
    let createdDate: Date
    let lastModifiedDate: Date

    init(_ allocation: AssetAllocation) {
        id = allocation.id
        assetID = allocation.asset?.id
        goalID = allocation.goal?.id
        amountBits = allocation.amountValue.bitPattern
        createdDate = allocation.createdDate
        lastModifiedDate = allocation.lastModifiedDate
    }
}

private struct CompletionAllocationHistoryInputFingerprint: Equatable {
    let id: UUID
    let assetID: UUID?
    let goalID: UUID?
    let amountBits: UInt64
    let timestamp: Date
    let createdAt: Date
    let monthLabel: String
    let sourceTransactionID: UUID?
    let sourcePreviousAmountBits: UInt64?

    init(_ history: AllocationHistory) {
        id = history.id
        assetID = history.assetId
        goalID = history.goalId
        amountBits = history.amount.bitPattern
        timestamp = history.timestamp
        createdAt = history.createdAt
        monthLabel = history.monthLabel
        sourceTransactionID = history.sourceTransactionId
        sourcePreviousAmountBits = history.sourcePreviousAmount?.bitPattern
    }
}

@MainActor
private struct ExecutionRecordMutationSnapshot {
    private let record: MonthlyExecutionRecord
    private let statusRawValue: String
    private let startedAt: Date?
    private let completedAt: Date?
    private let canUndoUntil: Date?
    private let trackedGoalIds: Data
    private let snapshot: ExecutionSnapshot?
    private let completedExecution: CompletedExecution?
    private let plans: [MonthlyPlan]?
    private let completionEvents: [CompletionEvent]?

    init(_ record: MonthlyExecutionRecord) {
        self.record = record
        statusRawValue = record.statusRawValue
        startedAt = record.startedAt
        completedAt = record.completedAt
        canUndoUntil = record.canUndoUntil
        trackedGoalIds = record.trackedGoalIds
        snapshot = record.snapshot
        completedExecution = record.completedExecution
        plans = record.plans
        completionEvents = record.completionEvents
    }

    func restore() {
        record.statusRawValue = statusRawValue
        record.startedAt = startedAt
        record.completedAt = completedAt
        record.canUndoUntil = canUndoUntil
        record.trackedGoalIds = trackedGoalIds
        record.snapshot = snapshot
        record.completedExecution = completedExecution
        record.plans = plans
        record.completionEvents = completionEvents
    }
}

@MainActor
private struct ExecutionPlanMutationSnapshot {
    private let plan: MonthlyPlan
    private let stateRawValue: String
    private let lastModifiedDate: Date
    private let executionRecord: MonthlyExecutionRecord?

    init(_ plan: MonthlyPlan) {
        self.plan = plan
        stateRawValue = plan.stateRawValue
        lastModifiedDate = plan.lastModifiedDate
        executionRecord = plan.executionRecord
    }

    func restore() {
        plan.stateRawValue = stateRawValue
        plan.lastModifiedDate = lastModifiedDate
        plan.executionRecord = executionRecord
    }
}

@MainActor
private struct ExecutionSnapshotMutationSnapshot {
    private let snapshot: ExecutionSnapshot
    private let totalPlanned: Double
    private let snapshotData: Data

    init(_ snapshot: ExecutionSnapshot) {
        self.snapshot = snapshot
        totalPlanned = snapshot.totalPlanned
        snapshotData = snapshot.snapshotData
    }

    func restore() {
        snapshot.totalPlanned = totalPlanned
        snapshot.snapshotData = snapshotData
    }
}

@MainActor
private struct CompletionEventMutationSnapshot {
    private let event: CompletionEvent
    private let undoneAt: Date?
    private let undoReason: String?

    init(_ event: CompletionEvent) {
        self.event = event
        undoneAt = event.undoneAt
        undoReason = event.undoReason
    }

    func restore() {
        event.undoneAt = undoneAt
        event.undoReason = undoReason
    }
}

// MARK: - Errors

extension ExecutionTrackingService {
    enum ExecutionError: LocalizedError {
        case recordAlreadyExists
        case recordNotFound
        case undoPeriodExpired
        case invalidState
        case executionInputsChanged

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
            case .executionInputsChanged:
                return "Execution inputs changed while completion was being prepared. Review the active goals and retry."
            }
        }
    }
}
