import Foundation
import Testing
@testable import CryptoSavingsTracker

struct FinishedGoalFundingPresentationTests {
    @Test("released allocation remains visible as balance already decreased")
    func releasedAllocationUsesBalanceAlreadyDecreasedTitle() {
        let allocationID = UUID()
        let presentation = FinishedGoalFundingPresentation.make(
            snapshot: makeSnapshot(
                entries: [
                    makeEntry(
                        allocationID: allocationID,
                        assetCurrency: "USDT",
                        amount: 35,
                        settlement: .balanceAlreadyDecreased
                    )
                ]
            )
        )

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].id == allocationID)
        #expect(presentation.rows[0].assetCurrency == "USDT")
        #expect(presentation.rows[0].amount == 35)
        #expect(presentation.rows[0].settlementTitle == "Balance already decreased")
    }

    @Test("retained allocation is labeled reserved as spent")
    func retainedAllocationUsesReservedAsSpentTitle() {
        let presentation = FinishedGoalFundingPresentation.make(
            snapshot: makeSnapshot(
                entries: [
                    makeEntry(
                        assetCurrency: "EUR",
                        amount: 125,
                        settlement: .keepAsSpent
                    )
                ]
            )
        )

        #expect(presentation.rows[0].settlementTitle == "Reserved as spent")
    }

    @Test("legacy finished goal without snapshot is labeled pending review")
    func legacyGoalWithoutSnapshotIsPendingReview() {
        #expect(FinishedGoalFundingContent.make(snapshot: nil) == .pendingReview)
    }

    @Test("presentation uses snapshot amount instead of current asset balance")
    func presentationUsesSnapshotAmount() {
        let presentation = FinishedGoalFundingPresentation.make(
            snapshot: makeSnapshot(
                entries: [
                    makeEntry(
                        assetCurrency: "BTC",
                        amount: 0.125,
                        settlement: .keepAsSpent
                    )
                ]
            )
        )

        #expect(presentation.rows[0].amount == 0.125)
    }

    @Test("review-time balance is labeled as review-time evidence")
    func reviewTimeEvidenceUsesReviewLabel() {
        let presentation = FinishedGoalFundingPresentation.make(
            snapshot: makeSnapshot(
                entries: [
                    makeEntry(
                        assetCurrency: "USDT",
                        amount: 40,
                        settlement: .keepAsSpent,
                        bestKnownBalance: 5_000,
                        balanceTiming: .reviewTime
                    )
                ]
            )
        )

        #expect(presentation.rows[0].balanceEvidenceTitle == "Best-known balance at review")
    }

    private func makeSnapshot(entries: [GoalCompletionSnapshot.Entry]) -> GoalCompletionSnapshot {
        GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: UUID(),
            goalName: "Finished goal",
            goalCurrency: "USD",
            goalTargetAmount: 100,
            goalCompletedAt: Date(timeIntervalSince1970: 1_000),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_000),
            entries: entries
        )
    }

    private func makeEntry(
        allocationID: UUID = UUID(),
        assetCurrency: String,
        amount: Double,
        settlement: FinishedAllocationSettlement,
        bestKnownBalance: Double? = nil,
        balanceTiming: GoalCompletionBalanceTiming = .completionTime
    ) -> GoalCompletionSnapshot.Entry {
        GoalCompletionSnapshot.Entry(
            allocationID: allocationID,
            assetID: UUID(),
            assetCurrency: assetCurrency,
            amount: amount,
            accountingMode: .manual,
            settlement: settlement,
            bestKnownBalance: bestKnownBalance,
            balanceCapturedAt: bestKnownBalance == nil ? nil : Date(timeIntervalSince1970: 1_000),
            balanceTiming: balanceTiming
        )
    }
}
