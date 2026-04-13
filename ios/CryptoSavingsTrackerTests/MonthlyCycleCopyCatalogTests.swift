//
//  MonthlyCycleCopyCatalogTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
@testable import CryptoSavingsTracker

@MainActor
struct MonthlyCycleCopyCatalogTests {
    @Test("Undo-start expiry copy matches the Back to Planning action")
    func undoStartExpiredCopy() {
        let message = MonthlyCycleCopyCatalog.undoStartExpired(month: "April 2026")

        #expect(message == "Back to Planning is no longer available for April 2026 because the undo window ended.")
    }

    @Test("Undo-finish expiry copy matches the Undo Finish action")
    func undoCompletionExpiredCopy() {
        let message = MonthlyCycleCopyCatalog.undoCompletionExpired(month: "April 2026")

        #expect(message == "Undo Finish is no longer available for April 2026 because the undo window ended.")
    }

    @Test("Conflict copy tells the user how to recover")
    func recordConflictCopy() {
        let message = MonthlyCycleCopyCatalog.recordConflict()

        #expect(message == "Monthly state is out of sync. Refresh Monthly Planning and try again.")
    }
}
