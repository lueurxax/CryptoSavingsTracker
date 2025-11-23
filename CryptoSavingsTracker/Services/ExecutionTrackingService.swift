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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        AppLog.debug("Received \(plans.count) plans and \(goals.count) goals", category: .executionTracking)

        // Check if record already exists
        if let existing = try getRecord(for: monthLabel) {
            if existing.status == .draft || existing.status == .executing {
                AppLog.debug("Found existing record for \(monthLabel), status: \(existing.status)", category: .executionTracking)

                // Always refresh snapshot from current plans to reflect latest adjustments
                let validPlans = plans.filter { plan in
                    let hasValidAmount = plan.effectiveAmount > 0 || plan.requiredMonthly > 0
                    AppLog.debug("Plan validation - goalId: \(plan.goalId), effectiveAmount: \(plan.effectiveAmount), requiredMonthly: \(plan.requiredMonthly), valid: \(hasValidAmount)", category: .executionTracking)
                    return hasValidAmount
                }

                AppLog.debug("Creating refreshed snapshot from \(validPlans.count) valid plans", category: .executionTracking)
                let snapshot = ExecutionSnapshot.create(from: validPlans, goals: goals)
                existing.snapshot = snapshot

                // Verify the snapshot
                if let decodedSnapshots = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshot.snapshotData) {
                    AppLog.debug("Refreshed snapshot contains \(decodedSnapshots.count) goal snapshots", category: .executionTracking)
                    for goalSnapshot in decodedSnapshots {
                        AppLog.debug("Goal snapshot: \(goalSnapshot.goalName) - \(goalSnapshot.plannedAmount) \(goalSnapshot.currency)", category: .executionTracking)
                    }
                }

                // Transition to executing if needed
                if existing.status == .draft {
                    existing.startTracking()
                }

                try modelContext.save()
                return existing
            } else {
                throw ExecutionError.recordAlreadyExists
            }
        }

        // Create new record
        let goalIds = plans.map { $0.goalId }
        AppLog.debug("Creating new execution record with \(goalIds.count) goal IDs", category: .executionTracking)
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: goalIds)

        // Create snapshot using factory method (ensures proper SwiftData initialization)
        AppLog.debug("Creating snapshot from \(plans.count) plans, effectiveAmounts: \(plans.map { $0.effectiveAmount })", category: .executionTracking)

        // Ensure we have valid plans with data
        let validPlans = plans.filter { plan in
            let hasValidAmount = plan.effectiveAmount > 0 || plan.requiredMonthly > 0
            AppLog.debug("Plan validation - goalId: \(plan.goalId), effectiveAmount: \(plan.effectiveAmount), requiredMonthly: \(plan.requiredMonthly), valid: \(hasValidAmount)", category: .executionTracking)
            return hasValidAmount
        }

        AppLog.debug("Filtered to \(validPlans.count) valid plans from \(plans.count) total", category: .executionTracking)

        let snapshot = ExecutionSnapshot.create(from: validPlans, goals: goals)
        AppLog.debug("Snapshot created - totalPlanned: \(snapshot.totalPlanned), snapshotData: \(snapshot.snapshotData.count) bytes", category: .executionTracking)

        // Verify snapshot data
        if let decodedSnapshots = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshot.snapshotData) {
            AppLog.debug("Verification: Snapshot contains \(decodedSnapshots.count) goal snapshots", category: .executionTracking)
            for goalSnapshot in decodedSnapshots {
                AppLog.debug("Goal snapshot: \(goalSnapshot.goalName) - \(goalSnapshot.plannedAmount) \(goalSnapshot.currency)", category: .executionTracking)
            }
        } else {
            AppLog.error("Failed to decode snapshot data for verification!", category: .executionTracking)
        }

        record.snapshot = snapshot

        // Start tracking
        record.startTracking()

        modelContext.insert(record)
        try modelContext.save()

        AppLog.info("Execution tracking started successfully for \(monthLabel)", category: .executionTracking)
        return record
    }

    /// Mark month as complete
    func markComplete(_ record: MonthlyExecutionRecord) throws {
        record.markComplete()
        try modelContext.save()
    }

    /// Undo completion (within grace period)
    func undoCompletion(_ record: MonthlyExecutionRecord) throws {
        guard record.canUndo else {
            throw ExecutionError.undoPeriodExpired
        }
        record.undoCompletion()
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

    // MARK: - Contribution Tracking

    /// Link contribution to execution record
    func linkContribution(_ contribution: Contribution, to record: MonthlyExecutionRecord) throws {
        contribution.executionRecordId = record.id
        contribution.isPlanned = true
        try modelContext.save()
    }

    /// Get contributions for execution record
    func getContributions(for record: MonthlyExecutionRecord) throws -> [Contribution] {
        let recordId = record.id
        let predicate = #Predicate<Contribution> { contribution in
            contribution.executionRecordId == recordId
        }

        let descriptor = FetchDescriptor<Contribution>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Get contributions grouped by goal
    func getContributionsByGoal(for record: MonthlyExecutionRecord) throws -> [UUID: [Contribution]] {
        let contributions = try getContributions(for: record)
        return Dictionary(grouping: contributions) { $0.goal?.id ?? UUID() }
    }

    /// Calculate total contributions per goal
    func getContributionTotals(for record: MonthlyExecutionRecord) throws -> [UUID: Double] {
        let contributionsByGoal = try getContributionsByGoal(for: record)

        return contributionsByGoal.mapValues { contributions in
            contributions.reduce(0) { $0 + $1.amount }
        }
    }

    // MARK: - Fulfillment Checking

    /// Check if specific goal is fulfilled for the month
    func isGoalFulfilled(goalId: UUID, in record: MonthlyExecutionRecord, against plan: MonthlyPlan) throws -> Bool {
        let contributions = try getContributions(for: record)
        let goalContributions = contributions.filter { $0.goal?.id == goalId }
        let totalContributed = goalContributions.reduce(0) { $0 + $1.amount }

        return totalContributed >= plan.effectiveAmount
    }

    /// Get fulfillment status for all goals
    func getFulfillmentStatus(
        for record: MonthlyExecutionRecord,
        plans: [MonthlyPlan]
    ) throws -> [UUID: Bool] {
        let totals = try getContributionTotals(for: record)
        let planDict = Dictionary(uniqueKeysWithValues: plans.map { ($0.goalId, $0) })

        var fulfillment: [UUID: Bool] = [:]
        for goalId in record.goalIds {
            guard let plan = planDict[goalId] else { continue }
            let contributed = totals[goalId] ?? 0
            fulfillment[goalId] = contributed >= plan.effectiveAmount
        }

        return fulfillment
    }

    /// Calculate overall progress percentage
    func calculateProgress(for record: MonthlyExecutionRecord) throws -> Double {
        guard let snapshot = record.snapshot else { return 0 }

        let totals = try getContributionTotals(for: record)
        let totalContributed = totals.values.reduce(0, +)

        return snapshot.totalPlanned > 0
            ? (totalContributed / snapshot.totalPlanned) * 100
            : 0
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
