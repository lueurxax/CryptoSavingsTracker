//
//  StaleDraftPresentationTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct StaleDraftPresentationTests {
    @Test("Banner summary copy reflects stale draft counts and page coverage")
    func bannerSummaryCopy() {
        let summary = StaleDraftPresentation.bannerSummary(
            stalePlanCount: 7,
            visibleRange: 6...7
        )

        #expect(summary == "7 stale drafts need review. Showing drafts 6 through 7.")
    }

    @Test("Row accessibility label names the goal month and planned amount")
    func rowAccessibilityLabel() {
        let label = StaleDraftPresentation.rowAccessibilityLabel(
            goalName: "Emergency Fund",
            monthLabel: "2026-02",
            plannedAmount: "$250.00"
        )

        #expect(label == "Emergency Fund. February 2026. Planned contribution $250.00.")
    }

    @Test("Pagination status announces current page and draft range")
    func paginationStatusCopy() {
        let status = StaleDraftPresentation.paginationStatus(
            currentPage: 1,
            totalPages: 3,
            visibleRange: 6...10
        )

        #expect(status == "Page 2 of 3. Showing drafts 6 through 10.")
    }

    @Test("Pagination accessibility copy explains how to move between stale draft pages")
    func paginationAccessibilityCopy() {
        #expect(StaleDraftPresentation.paginationAccessibilityLabel == "Stale draft pages")
        #expect(
            StaleDraftPresentation.paginationAccessibilityHint
                == "Use the previous and next page buttons to review older stale drafts."
        )
    }
}
