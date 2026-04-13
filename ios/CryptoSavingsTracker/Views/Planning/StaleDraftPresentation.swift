//
//  StaleDraftPresentation.swift
//  CryptoSavingsTracker
//

import Foundation

enum StaleDraftPresentation {
    static let paginationAccessibilityLabel = "Stale draft pages"
    static let paginationAccessibilityHint = "Use the previous and next page buttons to review older stale drafts."

    static func bannerTitle(stalePlanCount: Int) -> String {
        let noun = stalePlanCount == 1 ? "stale draft" : "stale drafts"
        return "\(stalePlanCount) \(noun) from past months"
    }

    static func bannerSubtitle(stalePlanCount: Int) -> String {
        stalePlanCount == 1
            ? "Review this draft and decide how to handle it."
            : "Review each draft and decide how to handle it."
    }

    static func bannerSummary(stalePlanCount: Int, visibleRange: ClosedRange<Int>?) -> String {
        let noun = stalePlanCount == 1 ? "stale draft needs review" : "\(stalePlanCount) stale drafts need review"
        guard let visibleRange else {
            return "\(noun)."
        }

        return "\(noun). Showing drafts \(visibleRange.lowerBound) through \(visibleRange.upperBound)."
    }

    static func paginationStatus(currentPage: Int, totalPages: Int, visibleRange: ClosedRange<Int>) -> String {
        "Page \(currentPage + 1) of \(totalPages). Showing drafts \(visibleRange.lowerBound) through \(visibleRange.upperBound)."
    }

    static func monthTitle(from monthLabel: String) -> String {
        guard let date = monthParser.date(from: monthLabel) else {
            return monthLabel
        }

        return monthFormatter.string(from: date)
    }

    static func rowAccessibilityLabel(goalName: String, monthLabel: String, plannedAmount: String) -> String {
        sentenceList(from: [
            goalName,
            monthTitle(from: monthLabel),
            "Planned contribution \(plannedAmount)"
        ])
    }

    static func rowAccessibilityHint(goalName: String, monthLabel: String) -> String {
        "Opens actions to mark the \(goalName) draft for \(monthTitle(from: monthLabel)) as completed, skipped, or deleted."
    }

    static func resolveDialogTitle(goalName: String, monthLabel: String) -> String {
        "Review \(goalName) draft for \(monthTitle(from: monthLabel))"
    }

    static func resolveDialogMessage(goalName: String, monthLabel: String) -> String {
        "Choose how to handle the saved draft for \(goalName) in \(monthTitle(from: monthLabel))."
    }

    static func deleteAlertTitle(goalName: String, monthLabel: String) -> String {
        "Delete \(goalName) draft for \(monthTitle(from: monthLabel))?"
    }

    static func deleteAlertMessage(monthLabel: String) -> String {
        "This removes the draft for \(monthTitle(from: monthLabel)) with no historical record kept."
    }

    private static func sentenceList(from parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : "\($0)." }
            .joined(separator: " ")
    }

    private static let monthParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
