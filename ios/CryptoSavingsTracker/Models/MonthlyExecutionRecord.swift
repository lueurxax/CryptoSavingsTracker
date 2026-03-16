//
//  MonthlyExecutionRecord.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Tracks monthly execution state and links to goal plans
//

import SwiftData
import Foundation

/// Per-month execution tracking record that links to existing MonthlyPlans
@Model
final class MonthlyExecutionRecord {
    var id: UUID = UUID()
    var monthLabel: String = ""              // "2025-09"
    var statusRawValue: String = ExecutionStatus.draft.rawValue          // For SwiftData predicate support
    var createdAt: Date = Date()
    var startedAt: Date?                // When user clicked "Start Tracking"
    var completedAt: Date?              // When marked complete

    // UX: Undo grace period
    var canUndoUntil: Date?             // 24hr window to undo state change

    // Link to existing plans (NOT relationship - uses goalId lookup)
    // SwiftData doesn't support [UUID] arrays, so we encode to Data
    var trackedGoalIds: Data = Data()            // Codable [UUID]

    // Snapshot
    @Relationship(deleteRule: .cascade)
    var snapshot: ExecutionSnapshot?    // Created when tracking starts

    // Completion metadata (exchange rates snapshot, etc.)
    @Relationship(deleteRule: .cascade, inverse: \CompletedExecution.executionRecord)
    var completedExecution: CompletedExecution?

    // Plans linked to this execution record
    @Relationship(inverse: \MonthlyPlan.executionRecord)
    var plans: [MonthlyPlan] = []

    // Append-only completion history for auditability.
    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.executionRecord)
    var completionEvents: [CompletionEvent] = []

    init(monthLabel: String, goalIds: [UUID]) {
        self.id = UUID()
        self.monthLabel = monthLabel
        self.statusRawValue = ExecutionStatus.draft.rawValue
        self.createdAt = Date()

        // Encode UUID array to Data
        if let encoded = try? JSONEncoder().encode(goalIds) {
            self.trackedGoalIds = encoded
        } else {
            self.trackedGoalIds = Data()
        }
    }

    // MARK: - Computed Properties

    /// Status enum wrapper
    var status: ExecutionStatus {
        get {
            ExecutionStatus(rawValue: statusRawValue) ?? .draft
        }
        set {
            statusRawValue = newValue.rawValue
        }
    }

    /// Decode goal IDs when needed
    var goalIds: [UUID] {
        guard let decoded = try? JSONDecoder().decode([UUID].self, from: trackedGoalIds) else {
            return []
        }
        return decoded
    }

    /// UX: Check if undo is still available
    var canUndo: Bool {
        guard let undoDeadline = canUndoUntil else { return false }
        return Date() < undoDeadline
    }

    // MARK: - State Transitions

    /// Start tracking contributions (draft → executing)
    func startTracking(undoWindowHours: Int = 24) {
        guard status == .draft else { return }
        status = .executing
        startedAt = Date()
        canUndoUntil = Date().addingTimeInterval(TimeInterval(max(0, undoWindowHours) * 3600))
    }

    /// Mark month as complete (executing → closed)
    func markComplete(undoWindowHours: Int = 24) {
        guard status == .executing else { return }
        status = .closed
        completedAt = Date()
        canUndoUntil = Date().addingTimeInterval(TimeInterval(max(0, undoWindowHours) * 3600))
    }

    /// Undo completion (closed → executing)
    func undoCompletion() {
        guard status == .closed && canUndo else { return }
        status = .executing
        completedAt = nil
        canUndoUntil = nil
    }

    /// Undo start tracking (executing → draft)
    func undoStartTracking() {
        guard status == .executing && canUndo else { return }
        status = .draft
        startedAt = nil
        canUndoUntil = nil
    }
}

@Model
final class CompletionEvent {
    var eventId: UUID = UUID()
    var executionRecordId: UUID = UUID()
    var monthLabel: String = ""
    var sequence: Int = 0
    var sourceDiscriminator: String = ""
    var completedAt: Date = Date()
    var undoneAt: Date?
    var undoReason: String?
    var createdAt: Date = Date()

    @Relationship
    var executionRecord: MonthlyExecutionRecord?

    @Relationship(deleteRule: .nullify)
    var completionSnapshot: CompletedExecution?

    init(
        executionRecord: MonthlyExecutionRecord,
        sequence: Int,
        sourceDiscriminator: String,
        completedAt: Date,
        completionSnapshot: CompletedExecution
    ) {
        self.eventId = UUID()
        self.executionRecordId = executionRecord.id
        self.monthLabel = executionRecord.monthLabel
        self.sequence = sequence
        self.sourceDiscriminator = sourceDiscriminator
        self.completedAt = completedAt
        self.undoneAt = nil
        self.undoReason = nil
        self.createdAt = Date()
        self.executionRecord = executionRecord
        self.completionSnapshot = completionSnapshot
    }
}

// MARK: - ExecutionStatus Enum

extension MonthlyExecutionRecord {
    enum ExecutionStatus: String, Codable, Sendable {
        case draft      // Internal: planning phase
        case executing  // Internal: active tracking
        case closed     // Internal: completed/archived

        /// UI Display Names (user-friendly)
        var displayName: String {
            switch self {
            case .draft: return "Planning"
            case .executing: return "Active This Month"
            case .closed: return "Completed"
            }
        }

        /// Icon for UI
        var icon: String {
            switch self {
            case .draft: return "pencil.circle"
            case .executing: return "chart.line.uptrend.xyaxis.circle"
            case .closed: return "checkmark.circle.fill"
            }
        }

        /// Color for UI (semantic)
        var color: String {
            switch self {
            case .draft: return "systemBlue"
            case .executing: return "systemGreen"
            case .closed: return "systemGray"
            }
        }
    }
}

// MARK: - Queries and Predicates

extension MonthlyExecutionRecord {

    /// Predicate for current month's record
    static func currentMonthPredicate() -> Predicate<MonthlyExecutionRecord> {
        let currentMonth = Self.monthLabel(from: Date())
        return #Predicate<MonthlyExecutionRecord> { record in
            record.monthLabel == currentMonth
        }
    }

    /// Predicate for active (executing) records
    static var executingPredicate: Predicate<MonthlyExecutionRecord> {
        #Predicate<MonthlyExecutionRecord> { record in
            record.statusRawValue == "executing"
        }
    }

    /// Predicate for completed records
    static var completedPredicate: Predicate<MonthlyExecutionRecord> {
        #Predicate<MonthlyExecutionRecord> { record in
            record.statusRawValue == "closed"
        }
    }

    /// Predicate for records that can be undone
    static func canUndoPredicate() -> Predicate<MonthlyExecutionRecord> {
        let now = Date()
        return #Predicate<MonthlyExecutionRecord> { record in
            record.canUndoUntil != nil && record.canUndoUntil! > now
        }
    }

    /// Generate month label from date (format: "YYYY-MM") using UTC calendar
    static func monthLabel(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return "Unknown"
        }
        return String(format: "%04d-%02d", year, month)
    }
}
