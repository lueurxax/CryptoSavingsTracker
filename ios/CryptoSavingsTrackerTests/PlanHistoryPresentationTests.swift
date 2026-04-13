//
//  PlanHistoryPresentationTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct PlanHistoryPresentationTests {
    @Test("Month summary copy distinguishes actual from planned totals")
    func monthSummaryCopy() {
        let summary = PlanHistoryPresentation.monthSummary(
            actualTotal: 80,
            requiredTotal: 100,
            currency: "USD"
        )

        #expect(summary.hasPrefix("Contributed "))
        #expect(summary.hasSuffix(" planned"))
        #expect(summary.contains("80"))
        #expect(summary.contains("100"))
    }

    @Test("Month row accessibility label captures completion totals and undo availability")
    func monthRowAccessibilityLabel() {
        let completedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let label = PlanHistoryPresentation.monthRowAccessibilityLabel(
            monthLabel: "2026-01",
            latestCompletedAt: completedAt,
            actualTotal: 80,
            requiredTotal: 100,
            undoAvailable: true,
            currency: "USD"
        )

        #expect(label.contains("January 2026."))
        #expect(label.contains("Completed on"))
        #expect(label.contains("Contributed"))
        #expect(label.contains("80"))
        #expect(label.contains("100"))
        #expect(label.contains("Undo available."))
    }

    @Test("Event status copy prefers undone timestamp over undo state")
    func eventStatusCopyForUndoneEntry() {
        let undoneAt = Date(timeIntervalSince1970: 1_704_153_600)
        let status = PlanHistoryPresentation.eventStatusText(
            undoneAt: undoneAt,
            isLatestOpen: true,
            canUndo: true
        )

        #expect(status.hasPrefix("Undone at "))
        #expect(status.contains("Jan 2, 2024"))
    }

    @Test("History list empty state explains how entries appear")
    func historyListEmptyStateCopy() {
        #expect(PlanHistoryPresentation.listEmptyStateTitle == "No Completed Months Yet")
        #expect(
            PlanHistoryPresentation.listEmptyStateDescription
                == "Finish a monthly plan to build a completion timeline you can review here."
        )
    }

    @Test("History detail empty state names the month that has no retained events")
    func historyDetailEmptyStateCopy() {
        #expect(PlanHistoryPresentation.detailEmptyStateTitle(monthLabel: "2026-01") == "No Saved Events for January 2026")
        #expect(
            PlanHistoryPresentation.detailEmptyStateDescription(monthLabel: "2026-01")
                == "No retained completion events are available for January 2026. Pull to refresh if you expected a recent change."
        )
    }

    @Test("History list load error is retryable with recovery guidance")
    func historyListLoadErrorCopy() {
        let error = PlanHistoryPresentation.listLoadError

        #expect(error.title == "Unable to Load History")
        #expect(error.message == "The completed-month timeline could not be loaded right now.")
        #expect(error.recoverySuggestion == "Pull to refresh or try again in a moment.")
        #expect(error.isRetryable)
        #expect(error.category == .unknown)
    }

    @Test("History detail load error includes the requested month")
    func historyDetailLoadErrorCopy() {
        let error = PlanHistoryPresentation.detailLoadError(monthLabel: "2026-01")

        #expect(error.title == "Unable to Load January 2026 History")
        #expect(error.message == "The completion events for this month could not be loaded right now.")
        #expect(error.recoverySuggestion == "Pull to refresh or try again in a moment.")
        #expect(error.isRetryable)
    }
}
