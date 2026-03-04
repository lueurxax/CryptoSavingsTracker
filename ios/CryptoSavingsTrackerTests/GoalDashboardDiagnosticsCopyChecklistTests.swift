//
//  GoalDashboardDiagnosticsCopyChecklistTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
@testable import CryptoSavingsTracker

struct GoalDashboardDiagnosticsCopyChecklistTests {
    @Test("DASH-COPY-ERR-001 diagnostics copy quality checklist passes")
    func diagnosticsCopyChecklistPasses() {
        let violations = GoalDashboardCopyCatalog.diagnosticsChecklistViolations()
        #expect(violations.isEmpty, "Checklist violations: \(violations.joined(separator: ", "))")
    }
}
