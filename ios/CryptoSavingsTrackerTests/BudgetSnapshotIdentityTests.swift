import Testing
import Foundation
@testable import CryptoSavingsTracker

struct BudgetSnapshotIdentityTests {

    @Test("goalsSignature is deterministic")
    func deterministicGoalsSignature() {
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let g1 = TestHelpers.createGoal(name: "A", currency: "USD", targetAmount: 1000, currentTotal: 0, deadline: deadline)
        let g2 = TestHelpers.createGoal(name: "B", currency: "EUR", targetAmount: 500, currentTotal: 0, deadline: deadline)

        let sig1 = BudgetSnapshotIdentity.goalsSignature(goals: [g1, g2], skippedGoalIds: [])
        let sig2 = BudgetSnapshotIdentity.goalsSignature(goals: [g2, g1], skippedGoalIds: [])

        #expect(sig1 == sig2)
    }

    @Test("rateSnapshotId is deterministic regardless of order")
    func deterministicRateSnapshotId() {
        let now = ISO8601DateFormatter().string(from: Date())
        let entriesA = [
            RateSnapshotEntry(from: "EUR", to: "USD", rate: Decimal(string: "1.1")!, timestampISO8601: now),
            RateSnapshotEntry(from: "GBP", to: "USD", rate: Decimal(string: "1.25")!, timestampISO8601: now)
        ]
        let entriesB = [entriesA[1], entriesA[0]]

        let idA = BudgetSnapshotIdentity.rateSnapshotId(fromRates: entriesA)
        let idB = BudgetSnapshotIdentity.rateSnapshotId(fromRates: entriesB)

        #expect(idA == idB)
    }
}
