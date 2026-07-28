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
    var id: UUID = UUID()
    var capturedAt: Date = Date()
    var totalPlanned: Double = 0.0            // Sum of all goals' planned amounts
    var snapshotData: Data = Data()              // Codable array of GoalSnapshots

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
        guard let decoded = try? JSONDecoder().decode([ExecutionGoalSnapshot].self, from: snapshotData) else {
            AppLog.error("Failed to decode snapshots from \(snapshotData.count) bytes of data", category: .executionTracking)
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

    func replaceGoalSnapshots(with snapshots: [ExecutionGoalSnapshot]) throws {
        snapshotData = try JSONEncoder().encode(snapshots)
        totalPlanned = Self.compatibleCurrencyTotal(for: snapshots)
    }

    fileprivate static func compatibleCurrencyTotal(
        for snapshots: [ExecutionGoalSnapshot]
    ) -> Double {
        let included = snapshots.filter { !$0.isSkipped }
        let currencies = Set(included.map { $0.currency.uppercased() })
        guard currencies.count <= 1 else { return 0 }
        return included.reduce(0) { $0 + $1.plannedAmount }
    }
}

// MARK: - ExecutionGoalSnapshot Struct

/// Snapshot of a single goal's plan at execution start
struct ExecutionGoalSnapshot: Codable, Sendable, Identifiable, Equatable {
    let goalId: UUID

    var id: UUID { goalId }
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
    enum CreationError: Error {
        case duplicateGoal(UUID)
    }

    /// Factory method to create properly initialized snapshot for SwiftData
    /// This ensures all properties are set before insertion into ModelContext
    static func create(from plans: [MonthlyPlan], goals: [Goal]) throws -> ExecutionSnapshot {

        let id = UUID()
        let capturedAt = Date()

        // Create goal lookup dictionary
        let goalDict = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

        // Create snapshots with goal names
        var seenGoalIDs: Set<UUID> = []
        let snapshots = try plans.map { plan in
            guard seenGoalIDs.insert(plan.goalId).inserted else {
                throw CreationError.duplicateGoal(plan.goalId)
            }
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
            return snapshot
        }


        let calculatedTotal = compatibleCurrencyTotal(for: snapshots)

        // Encode to Data for SwiftData storage
        let encodedData = try JSONEncoder().encode(snapshots)

        // Create using memberwise init with ALL properties set
        let snapshot = ExecutionSnapshot(
            id: id,
            capturedAt: capturedAt,
            totalPlanned: calculatedTotal,
            snapshotData: encodedData
        )


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
        ExecutionProgressAggregation.percentage(
            targets: goalSnapshots.map {
                ExecutionProgressTarget(
                    goalId: $0.goalId,
                    plannedAmount: $0.plannedAmount,
                    isSkipped: $0.isSkipped
                )
            },
            contributions: contributions
        )
    }
}

struct ExecutionProgressTarget: Equatable {
    let goalId: UUID
    let plannedAmount: Double
    let isSkipped: Bool
}

enum ExecutionProgressAggregation {
    static func percentage(
        targets: [ExecutionProgressTarget],
        contributions: [UUID: Double]
    ) -> Double {
        let included = targets.filter {
            !$0.isSkipped && $0.plannedAmount.isFinite && $0.plannedAmount > 0
        }
        guard !included.isEmpty else { return 0 }

        let completedFractions = included.reduce(0.0) { total, target in
            let contributed = contributions[target.goalId] ?? 0
            let fraction = contributed.isFinite
                ? contributed / target.plannedAmount
                : 0
            return total + min(max(fraction, 0), 1)
        }
        return (completedFractions / Double(included.count)) * 100
    }
}

enum ExecutionAmountFormatter {
    static func string(amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(currency.uppercased()) \(amount)"
    }
}
