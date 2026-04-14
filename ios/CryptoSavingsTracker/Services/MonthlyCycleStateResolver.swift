//
//  MonthlyCycleStateResolver.swift
//  CryptoSavingsTracker
//
//  Canonical monthly cycle resolver for planning/execution UI state.
//

import Foundation

enum PlanningSource: Equatable {
    case currentMonth
    case nextMonthAfterClosed

    nonisolated static func == (lhs: PlanningSource, rhs: PlanningSource) -> Bool {
        switch (lhs, rhs) {
        case (.currentMonth, .currentMonth), (.nextMonthAfterClosed, .nextMonthAfterClosed):
            return true
        default:
            return false
        }
    }
}

enum CycleConflictReason: Equatable {
    case duplicateActiveRecords
    case invalidMonthLabel
    case futureRecord

    nonisolated static func == (lhs: CycleConflictReason, rhs: CycleConflictReason) -> Bool {
        switch (lhs, rhs) {
        case (.duplicateActiveRecords, .duplicateActiveRecords),
             (.invalidMonthLabel, .invalidMonthLabel),
             (.futureRecord, .futureRecord):
            return true
        default:
            return false
        }
    }
}

enum UiCycleState: Equatable {
    case planning(month: String, source: PlanningSource)
    case executing(month: String, canFinish: Bool, canUndoStart: Bool)
    case closed(month: String, canUndoCompletion: Bool)
    case conflict(month: String?, reason: CycleConflictReason)

    nonisolated static func == (lhs: UiCycleState, rhs: UiCycleState) -> Bool {
        switch (lhs, rhs) {
        case let (.planning(lhsMonth, lhsSource), .planning(rhsMonth, rhsSource)):
            return lhsMonth == rhsMonth && lhsSource == rhsSource
        case let (.executing(lhsMonth, lhsFinish, lhsUndo), .executing(rhsMonth, rhsFinish, rhsUndo)):
            return lhsMonth == rhsMonth && lhsFinish == rhsFinish && lhsUndo == rhsUndo
        case let (.closed(lhsMonth, lhsUndo), .closed(rhsMonth, rhsUndo)):
            return lhsMonth == rhsMonth && lhsUndo == rhsUndo
        case let (.conflict(lhsMonth, lhsReason), .conflict(rhsMonth, rhsReason)):
            return lhsMonth == rhsMonth && lhsReason == rhsReason
        default:
            return false
        }
    }
}

struct ExecutionRecordSnapshot: Equatable {
    let monthLabel: String
    let status: MonthlyExecutionRecord.ExecutionStatus
    let completedAt: Date?
    let startedAt: Date?
    let canUndoUntil: Date?
}

struct ResolverInput {
    let nowUtc: Date
    let displayTimeZone: TimeZone
    let currentStorageMonthLabelUtc: String
    let records: [ExecutionRecordSnapshot]
    let undoWindowSeconds: TimeInterval
}

struct MonthlyCycleStateResolver {
    func resolve(_ input: ResolverInput) -> UiCycleState {
        guard let currentIndex = monthIndex(for: input.currentStorageMonthLabelUtc) else {
            return .conflict(month: nil, reason: .invalidMonthLabel)
        }

        for record in input.records where monthIndex(for: record.monthLabel) == nil {
            return .conflict(month: nil, reason: .invalidMonthLabel)
        }

        let indexed = input.records.compactMap { record -> (ExecutionRecordSnapshot, Int)? in
            guard let idx = monthIndex(for: record.monthLabel) else { return nil }
            return (record, idx)
        }

        if let future = indexed.first(where: { $0.1 > currentIndex + 1 }) {
            return .conflict(month: future.0.monthLabel, reason: .futureRecord)
        }

        let executingByMonth = Dictionary(grouping: indexed.filter { $0.0.status == .executing }) { $0.0.monthLabel }
        if let duplicateMonth = executingByMonth.first(where: { $0.value.count > 1 })?.key {
            return .conflict(month: duplicateMonth, reason: .duplicateActiveRecords)
        }

        if let activeExecuting = indexed
            .filter({ $0.0.status == .executing })
            .sorted(by: { $0.1 > $1.1 })
            .first?.0 {
            return .executing(
                month: activeExecuting.monthLabel,
                canFinish: true,
                canUndoStart: canUndo(activeExecuting, nowUtc: input.nowUtc, undoWindowSeconds: input.undoWindowSeconds)
            )
        }

        if let latestClosed = indexed
            .filter({ $0.0.status == .closed })
            .sorted(by: { $0.1 > $1.1 })
            .first?.0 {
            let canUndoCompletion = canUndo(latestClosed, nowUtc: input.nowUtc, undoWindowSeconds: input.undoWindowSeconds)
            if canUndoCompletion {
                return .closed(month: latestClosed.monthLabel, canUndoCompletion: true)
            }
            return .planning(month: input.currentStorageMonthLabelUtc, source: .nextMonthAfterClosed)
        }

        return .planning(month: input.currentStorageMonthLabelUtc, source: .currentMonth)
    }

    private func canUndo(_ snapshot: ExecutionRecordSnapshot, nowUtc: Date, undoWindowSeconds: TimeInterval) -> Bool {
        if let canUndoUntil = snapshot.canUndoUntil {
            return nowUtc < canUndoUntil
        }

        let baseDate: Date?
        switch snapshot.status {
        case .closed:
            baseDate = snapshot.completedAt
        case .executing:
            baseDate = snapshot.startedAt
        case .draft:
            baseDate = nil
        }

        guard undoWindowSeconds > 0, let baseDate else { return false }
        return nowUtc < baseDate.addingTimeInterval(undoWindowSeconds)
    }

    private func monthIndex(for monthLabel: String) -> Int? {
        let comps = monthLabel.split(separator: "-")
        guard comps.count == 2,
              let year = Int(comps[0]),
              let month = Int(comps[1]),
              (1...12).contains(month) else {
            return nil
        }
        return year * 12 + month
    }
}
