//
//  MonthlyCycleStateResolver.swift
//  CryptoSavingsTracker
//
//  Canonical monthly cycle resolver for planning/execution UI state.
//

import Foundation

enum PlanningMonthContractError: LocalizedError, Equatable {
    case invalidMonthLabel(String)
    case invalidPaymentDay(Int)

    var errorDescription: String? {
        switch self {
        case .invalidMonthLabel(let label):
            return "Invalid planning month label: \(label)"
        case .invalidPaymentDay(let day):
            return "Invalid planning payment day: \(day)"
        }
    }
}

/// Canonical calendar contract for planning and execution.
///
/// Month labels are durable storage identities and therefore always use UTC.
/// Local time zones may be used to render an instant for the user, but never to
/// select a different persisted month. Payment schedules are also evaluated in
/// UTC so a selected month, its plans, its confirmation, and its execution
/// record share one identity at local/UTC month boundaries.
enum PlanningMonthContract {
    static let storageTimeZone = TimeZone(secondsFromGMT: 0)!

    static func storageLabel(for date: Date) -> String {
        label(for: date, timeZone: storageTimeZone)
    }

    static func displayLabel(for date: Date, timeZone: TimeZone) -> String {
        label(for: date, timeZone: timeZone)
    }

    static func referenceDate(for monthLabel: String, now: Date) throws -> Date {
        let start = try startDate(for: monthLabel)
        return storageLabel(for: now) == monthLabel ? max(now, start) : start
    }

    static func startDate(for monthLabel: String) throws -> Date {
        let (year, month) = try components(from: monthLabel)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        guard let date = calendar.date(
            from: DateComponents(
                timeZone: storageTimeZone,
                year: year,
                month: month,
                day: 1,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) else {
            throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
        }
        return date
    }

    static func nextLabel(after monthLabel: String) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        let start = try startDate(for: monthLabel)
        guard let next = calendar.date(byAdding: .month, value: 1, to: start) else {
            throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
        }
        return storageLabel(for: next)
    }

    static func paymentPeriodsRemaining(
        in monthLabel: String,
        paymentDay: Int,
        deadline: Date,
        now: Date
    ) throws -> Int {
        guard (1...28).contains(paymentDay) else {
            throw PlanningMonthContractError.invalidPaymentDay(paymentDay)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        let reference = try referenceDate(for: monthLabel, now: now)
        let start = try startDate(for: monthLabel)
        let startComponents = calendar.dateComponents([.year, .month], from: start)
        guard var paymentDate = calendar.date(
            from: DateComponents(
                timeZone: storageTimeZone,
                year: startComponents.year,
                month: startComponents.month,
                day: paymentDay,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) else {
            throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
        }

        let isCurrentMonth = storageLabel(for: now) == monthLabel
        if isCurrentMonth, paymentDate <= reference {
            guard let next = calendar.date(byAdding: .month, value: 1, to: paymentDate) else {
                throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
            }
            paymentDate = next
        }

        var count = 0
        while paymentDate <= deadline {
            count += 1
            guard let next = calendar.date(byAdding: .month, value: 1, to: paymentDate) else {
                break
            }
            paymentDate = next
        }
        return max(1, count)
    }

    static func nextPaymentDate(
        in monthLabel: String,
        paymentDay: Int,
        now: Date
    ) throws -> Date {
        guard (1...28).contains(paymentDay) else {
            throw PlanningMonthContractError.invalidPaymentDay(paymentDay)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        let reference = try referenceDate(for: monthLabel, now: now)
        let start = try startDate(for: monthLabel)
        let components = calendar.dateComponents([.year, .month], from: start)
        guard var paymentDate = calendar.date(
            from: DateComponents(
                timeZone: storageTimeZone,
                year: components.year,
                month: components.month,
                day: paymentDay,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) else {
            throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
        }
        let isCurrentMonth = storageLabel(for: now) == monthLabel
        if isCurrentMonth, paymentDate <= reference {
            guard let next = calendar.date(byAdding: .month, value: 1, to: paymentDate) else {
                throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
            }
            paymentDate = next
        }
        return paymentDate
    }

    static func addingOneMonth(to date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        return calendar.date(byAdding: .month, value: 1, to: date)
    }

    private static func label(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return "Unknown"
        }
        return String(format: "%04d-%02d", year, month)
    }

    private static func components(from monthLabel: String) throws -> (Int, Int) {
        let pieces = monthLabel.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              pieces[0].count == 4,
              pieces[1].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              (1...12).contains(month)
        else {
            throw PlanningMonthContractError.invalidMonthLabel(monthLabel)
        }
        return (year, month)
    }
}

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

        if let latestClosedEntry = indexed
            .filter({ $0.0.status == .closed })
            .sorted(by: { $0.1 > $1.1 })
            .first {
            let latestClosed = latestClosedEntry.0
            let canUndoCompletion = canUndo(latestClosed, nowUtc: input.nowUtc, undoWindowSeconds: input.undoWindowSeconds)
            if canUndoCompletion {
                return .closed(month: latestClosed.monthLabel, canUndoCompletion: true)
            }
            let planningMonth: String
            if latestClosedEntry.1 >= currentIndex {
                guard let nextClosedMonth = try? PlanningMonthContract.nextLabel(
                    after: latestClosed.monthLabel
                ) else {
                    return .conflict(
                        month: latestClosed.monthLabel,
                        reason: .invalidMonthLabel
                    )
                }
                planningMonth = nextClosedMonth
            } else {
                planningMonth = input.currentStorageMonthLabelUtc
            }
            return .planning(
                month: planningMonth,
                source: .nextMonthAfterClosed
            )
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
