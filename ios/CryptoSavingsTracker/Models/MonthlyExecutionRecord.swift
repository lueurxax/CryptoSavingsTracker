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
    @Attribute(.unique) var id: UUID
    var monthLabel: String              // "2025-09"
    var statusRawValue: String          // For SwiftData predicate support
    var createdAt: Date
    var startedAt: Date?                // When user clicked "Start Tracking"
    var completedAt: Date?              // When marked complete

    // UX: Undo grace period
    var canUndoUntil: Date?             // 24hr window to undo state change

    // Link to existing plans (NOT relationship - uses goalId lookup)
    // SwiftData doesn't support [UUID] arrays, so we encode to Data
    var trackedGoalIds: Data            // Codable [UUID]

    // Snapshot
    @Relationship(deleteRule: .cascade)
    var snapshot: ExecutionSnapshot?    // Created when tracking starts

    // Completion metadata (exchange rates snapshot, etc.)
    @Relationship(deleteRule: .cascade)
    var completedExecution: CompletedExecution?

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
    func startTracking() {
        guard status == .draft else { return }
        status = .executing
        startedAt = Date()
        canUndoUntil = Date().addingTimeInterval(24 * 3600) // 24 hours
    }

    /// Mark month as complete (executing → closed)
    func markComplete() {
        guard status == .executing else { return }
        status = .closed
        completedAt = Date()
        canUndoUntil = Date().addingTimeInterval(24 * 3600) // 24 hours
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
