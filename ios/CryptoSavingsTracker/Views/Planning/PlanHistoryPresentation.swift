//
//  PlanHistoryPresentation.swift
//  CryptoSavingsTracker
//

import Foundation

enum PlanHistoryPresentation {
    static let listEmptyStateTitle = "No Completed Months Yet"
    static let listEmptyStateDescription = "Finish a monthly plan to build a completion timeline you can review here."

    static func monthTitle(from monthLabel: String) -> String {
        guard let date = monthParser.date(from: monthLabel) else {
            return monthLabel
        }

        return monthTitleFormatter.string(from: date)
    }

    static func detailEmptyStateTitle(monthLabel: String) -> String {
        "No Saved Events for \(monthTitle(from: monthLabel))"
    }

    static func detailEmptyStateDescription(monthLabel: String) -> String {
        "No retained completion events are available for \(monthTitle(from: monthLabel)). Pull to refresh if you expected a recent change."
    }

    static var listLoadError: UserFacingError {
        UserFacingError(
            title: "Unable to Load History",
            message: "The completed-month timeline could not be loaded right now.",
            recoverySuggestion: "Pull to refresh or try again in a moment.",
            isRetryable: true,
            category: .unknown
        )
    }

    static func detailLoadError(monthLabel: String) -> UserFacingError {
        UserFacingError(
            title: "Unable to Load \(monthTitle(from: monthLabel)) History",
            message: "The completion events for this month could not be loaded right now.",
            recoverySuggestion: "Pull to refresh or try again in a moment.",
            isRetryable: true,
            category: .unknown
        )
    }

    static func monthSummary(actualTotal: Double, requiredTotal: Double, currency: String = "USD") -> String {
        let actual = planHistoryCurrency(amount: actualTotal, currency: currency)
        let required = planHistoryCurrency(amount: requiredTotal, currency: currency)
        return "Contributed \(actual) of \(required) planned"
    }

    static func monthRowAccessibilityLabel(
        monthLabel: String,
        latestCompletedAt: Date,
        actualTotal: Double,
        requiredTotal: Double,
        undoAvailable: Bool,
        currency: String = "USD"
    ) -> String {
        var components = [
            monthTitle(from: monthLabel),
            "Completed on \(accessibilityDateFormatter.string(from: latestCompletedAt))",
            monthSummary(actualTotal: actualTotal, requiredTotal: requiredTotal, currency: currency)
        ]

        if undoAvailable {
            components.append("Undo available")
        }

        return sentenceList(from: components)
    }

    static func monthRowAccessibilityHint(undoAvailable: Bool) -> String {
        if undoAvailable {
            return "Opens this month's completion history. Undo is still available for the latest completion."
        }

        return "Opens this month's completion history."
    }

    static func detailSummaryAccessibilityValue(
        actualTotal: Double,
        requiredTotal: Double,
        eventsCount: Int,
        currency: String = "USD"
    ) -> String {
        let summary = monthSummary(actualTotal: actualTotal, requiredTotal: requiredTotal, currency: currency)
        let eventsCopy = eventsCount == 1 ? "1 completion event" : "\(eventsCount) completion events"
        return sentenceList(from: [summary, eventsCopy])
    }

    static func eventStatusText(undoneAt: Date?, isLatestOpen: Bool, canUndo: Bool) -> String {
        if let undoneAt {
            return "Undone at \(timelineTimestamp(from: undoneAt))"
        }

        if isLatestOpen {
            return canUndo ? "Undo available" : "Undo expired"
        }

        return "Completed"
    }

    static func timelineAccessibilityLabel(
        completedAt: Date,
        sequence: Int,
        status: String,
        actualTotal: Double,
        requiredTotal: Double,
        currency: String = "USD"
    ) -> String {
        sentenceList(from: [
            "Completion event \(sequence)",
            "Completed \(timelineTimestamp(from: completedAt))",
            status,
            monthSummary(actualTotal: actualTotal, requiredTotal: requiredTotal, currency: currency)
        ])
    }

    static func timelineTimestamp(from date: Date) -> String {
        let text = timelineTimestampFormatter.string(from: date)
        return text.replacingOccurrences(of: " AM", with: "\u{202F}AM")
            .replacingOccurrences(of: " PM", with: "\u{202F}PM")
    }

    private static func sentenceList(from parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : "\($0)." }
            .joined(separator: " ")
    }

    private static func planHistoryCurrency(amount: Double, currency: String) -> String {
        CurrencyFormatter.format(amount: amount, currency: currency, maximumFractionDigits: 2)
    }

    private static let monthParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timelineTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        return formatter
    }()
}
