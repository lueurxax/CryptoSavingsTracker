import XCTest

@testable import CryptoSavingsTracker

@MainActor
final class AssetAllocationEditorPolicyTests: XCTestCase {
    func testBreakdownSeparatesPendingAndReservedFinishedAllocations() {
        let activeGoalID = UUID()
        let pendingGoalID = UUID()
        let reservedGoalID = UUID()
        let entries = [
            AssetAllocationEditorEntry(
                goalID: activeGoalID,
                goalName: "Active goal",
                status: .active,
                amount: 695,
                finishedState: nil
            ),
            AssetAllocationEditorEntry(
                goalID: pendingGoalID,
                goalName: "Legacy finished goal",
                status: .finished,
                amount: 4_456,
                finishedState: .pendingReview
            ),
            AssetAllocationEditorEntry(
                goalID: reservedGoalID,
                goalName: "Settled finished goal",
                status: .finished,
                amount: 686,
                finishedState: .reservedAsSpent
            )
        ]

        let breakdown = AssetAllocationEditorPolicy.breakdown(
            balance: 5_873.6673,
            entries: entries
        )

        XCTAssertEqual(breakdown.activeAllocatedAmount, 695, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.pendingReviewAmount, 4_456, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.finishedReservedAmount, 686, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.unallocatedAmount, 36.6673, accuracy: 0.0000001)
        XCTAssertEqual(
            breakdown.activePercentage
                + breakdown.pendingReviewPercentage
                + breakdown.finishedReservedPercentage
                + breakdown.unallocatedPercentage,
            1,
            accuracy: 0.0000001
        )
    }

    func testSaveAmountsPreservePendingAndReservedFinishedAllocations() {
        let activeGoalID = UUID()
        let pendingGoalID = UUID()
        let reservedGoalID = UUID()
        let entries = [
            AssetAllocationEditorEntry(
                goalID: activeGoalID,
                goalName: "Active goal",
                status: .active,
                amount: 1_410,
                finishedState: nil
            ),
            AssetAllocationEditorEntry(
                goalID: pendingGoalID,
                goalName: "Legacy finished goal",
                status: .finished,
                amount: 4_456,
                finishedState: .pendingReview
            ),
            AssetAllocationEditorEntry(
                goalID: reservedGoalID,
                goalName: "Settled finished goal",
                status: .finished,
                amount: 686,
                finishedState: .reservedAsSpent
            )
        ]

        let amounts = AssetAllocationEditorPolicy.amountsForSave(
            activeGoalIDs: [activeGoalID],
            draft: [activeGoalID: 1_500, pendingGoalID: 0, reservedGoalID: 0],
            existingEntries: entries
        )

        XCTAssertEqual(amounts[activeGoalID], 1_500)
        XCTAssertEqual(amounts[pendingGoalID], 4_456)
        XCTAssertEqual(amounts[reservedGoalID], 686)
    }

    func testClearingActiveAllocationsLeavesFinishedAllocationReserved() {
        let activeGoalID = UUID()
        let finishedGoalID = UUID()

        let cleared = AssetAllocationEditorPolicy.clearingActiveAllocations(
            in: [activeGoalID: 1_410, finishedGoalID: 4_427],
            activeGoalIDs: [activeGoalID]
        )

        XCTAssertNil(cleared[activeGoalID])
        XCTAssertEqual(cleared[finishedGoalID], 4_427)
    }

    func testWarningReviewsLegacyRowsWhenTheyCauseDisplayedShortfall() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Active goal",
                status: .active,
                amount: 695,
                finishedState: nil
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Legacy finished goal",
                status: .finished,
                amount: 4_456,
                finishedState: .pendingReview
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Settled finished goal",
                status: .finished,
                amount: 686,
                finishedState: .reservedAsSpent
            )
        ]

        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 5_000, entries: entries),
            .reviewFinishedAllocations
        )
    }

    func testWarningReducesActiveAllocationsWhenNoLegacyRowsExist() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Active goal",
                status: .active,
                amount: 110,
                finishedState: nil
            )
        ]

        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 100, entries: entries),
            .reduceActiveAllocations
        )
    }
}
