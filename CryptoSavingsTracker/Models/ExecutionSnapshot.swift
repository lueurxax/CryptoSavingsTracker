//
//  ExecutionSnapshot.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Captures monthly plan state when execution starts
//

import SwiftData
import Foundation

/// Captures the state of all MonthlyPlans when execution starts
@Model
final class ExecutionSnapshot {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var totalPlanned: Double            // Sum of all goals' planned amounts
    var snapshotData: Data              // Codable array of GoalSnapshots

    // Relationship
    @Relationship(inverse: \MonthlyExecutionRecord.snapshot)
    var executionRecord: MonthlyExecutionRecord?

    // Memberwise init - required by SwiftData
    init(id: UUID, capturedAt: Date, totalPlanned: Double, snapshotData: Data) {
        self.id = id
        self.capturedAt = capturedAt
        self.totalPlanned = totalPlanned
        self.snapshotData = snapshotData
    }

    // MARK: - Computed Properties

    /// Decode snapshots when needed
    var goalSnapshots: [ExecutionGoalSnapshot] {
        AppLog.debug("Accessing goalSnapshots, snapshotData size: \(snapshotData.count) bytes", category: .executionTracking)
        guard let decoded = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshotData) else {
            AppLog.error("Failed to decode snapshots from \(snapshotData.count) bytes of data", category: .executionTracking)
            return []
        }
        AppLog.debug("Successfully decoded \(decoded.count) goal snapshots", category: .executionTracking)
        return decoded
    }

    /// Get snapshot for specific goal
    func snapshot(for goalId: UUID) -> ExecutionGoalSnapshot? {
        return goalSnapshots.first { $0.goalId == goalId }
    }

    /// Count of goals in snapshot
    var goalCount: Int {
        return goalSnapshots.count
    }

    /// Count of non-skipped goals
    var activeGoalCount: Int {
        return goalSnapshots.filter { !$0.isSkipped }.count
    }
}

// MARK: - ExecutionGoalSnapshot Struct

/// Snapshot of a single goal's plan at execution start
struct ExecutionGoalSnapshot: Codable, Sendable {
    let goalId: UUID
    let goalName: String
    let plannedAmount: Double
    let currency: String
    let flexState: String           // protected/flexible/skipped
    let isSkipped: Bool
    let isProtected: Bool

    /// Human-readable flex state
    var flexStateDescription: String {
        switch flexState {
        case "protected": return "Protected from adjustments"
        case "flexible": return "Can be adjusted"
        case "skipped": return "Skipped this month"
        default: return "Unknown"
        }
    }

    /// Formatted amount for display
    func formattedAmount() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: plannedAmount)) ??
               "\(currency) \(String(format: "%.2f", plannedAmount))"
    }
}

// MARK: - Factory Method

extension ExecutionSnapshot {

    /// Factory method to create properly initialized snapshot for SwiftData
    /// This ensures all properties are set before insertion into ModelContext
    static func create(from plans: [MonthlyPlan], goals: [Goal]) -> ExecutionSnapshot {
        AppLog.debug("Creating snapshot from \(plans.count) plans and \(goals.count) goals", category: .executionTracking)

        let id = UUID()
        let capturedAt = Date()

        // Create goal lookup dictionary
        let goalDict = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        AppLog.debug("Created goal dictionary with \(goalDict.count) entries", category: .executionTracking)

        // Create snapshots with goal names
        let snapshots = plans.map { plan in
            let goalName = goalDict[plan.goalId]?.name ?? "Unknown Goal"
            let snapshot = ExecutionGoalSnapshot(
                goalId: plan.goalId,
                goalName: goalName,
                plannedAmount: plan.effectiveAmount,
                currency: plan.currency,
                flexState: plan.flexStateRawValue,
                isSkipped: plan.isSkipped,
                isProtected: plan.isProtected
            )
            AppLog.debug("Created snapshot for '\(goalName)': amount=\(plan.effectiveAmount), currency=\(plan.currency)", category: .executionTracking)
            return snapshot
        }

        AppLog.debug("Created \(snapshots.count) goal snapshots", category: .executionTracking)

        let calculatedTotal = snapshots.reduce(0) { $0 + $1.plannedAmount }
        AppLog.debug("Total planned: \(calculatedTotal)", category: .executionTracking)

        // Encode to Data for SwiftData storage
        let encodedData: Data
        if let encoded = try? JSONEncoder().encode(snapshots) {
            encodedData = encoded
            AppLog.debug("Successfully encoded snapshot data (\(encoded.count) bytes)", category: .executionTracking)
        } else {
            encodedData = Data()
            AppLog.error("Failed to encode snapshots!", category: .executionTracking)
        }

        // Create using memberwise init with ALL properties set
        let snapshot = ExecutionSnapshot(
            id: id,
            capturedAt: capturedAt,
            totalPlanned: calculatedTotal,
            snapshotData: encodedData
        )

        AppLog.debug("ExecutionSnapshot created - totalPlanned: \(calculatedTotal), snapshotData: \(encodedData.count) bytes", category: .executionTracking)

        return snapshot
    }
}

// MARK: - Snapshot Comparison

extension ExecutionSnapshot {

    /// Compare snapshot with current contributions
    struct SnapshotComparison {
        let goalId: UUID
        let goalName: String
        let planned: Double
        let contributed: Double
        let currency: String
        let isFulfilled: Bool
        let percentage: Double

        var formattedPlanned: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            return formatter.string(from: NSNumber(value: planned)) ?? "\(planned)"
        }

        var formattedContributed: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
            return formatter.string(from: NSNumber(value: contributed)) ?? "\(contributed)"
        }
    }

    /// Generate comparison with contributions
    func compare(with contributions: [UUID: Double]) -> [SnapshotComparison] {
        return goalSnapshots.map { snapshot in
            let contributed = contributions[snapshot.goalId] ?? 0
            let percentage = snapshot.plannedAmount > 0
                ? (contributed / snapshot.plannedAmount) * 100
                : 0

            return SnapshotComparison(
                goalId: snapshot.goalId,
                goalName: snapshot.goalName,
                planned: snapshot.plannedAmount,
                contributed: contributed,
                currency: snapshot.currency,
                isFulfilled: contributed >= snapshot.plannedAmount,
                percentage: percentage
            )
        }
    }

    /// Overall completion percentage
    func overallCompletion(with contributions: [UUID: Double]) -> Double {
        let totalContributed = contributions.values.reduce(0, +)
        return totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
    }
}
