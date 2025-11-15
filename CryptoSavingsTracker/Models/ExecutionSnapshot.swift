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
final class ExecutionSnapshot: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var totalPlanned: Double            // Sum of all goals' planned amounts
    var snapshotData: Data              // Codable array of GoalSnapshots

    // Relationship
    var executionRecord: MonthlyExecutionRecord?

    init(from plans: [MonthlyPlan], goals: [Goal]) {
        self.id = UUID()
        self.capturedAt = Date()

        // Create goal lookup dictionary
        let goalDict = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

        // Create snapshots with goal names
        let snapshots = plans.map { plan in
            ExecutionGoalSnapshot(
                goalId: plan.goalId,
                goalName: goalDict[plan.goalId]?.name ?? "Unknown Goal",
                plannedAmount: plan.effectiveAmount,
                currency: plan.currency,
                flexState: plan.flexStateRawValue,
                isSkipped: plan.isSkipped,
                isProtected: plan.isProtected
            )
        }

        self.totalPlanned = snapshots.reduce(0) { $0 + $1.plannedAmount }

        // Encode to Data for SwiftData storage
        if let encoded = try? JSONEncoder().encode(snapshots) {
            self.snapshotData = encoded
        } else {
            self.snapshotData = Data()
        }
    }

    // MARK: - Computed Properties

    /// Decode snapshots when needed
    var goalSnapshots: [ExecutionGoalSnapshot] {
        guard let decoded = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshotData) else {
            return []
        }
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
