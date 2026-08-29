import SwiftData
import XCTest

@testable import CryptoSavingsTracker

@MainActor
final class AssetAllocationEditorPolicyTests: XCTestCase {
    func testEntryIdentityIsStableGoalAndAllocationCompositeWhenAllocationUUIDRepeats() {
        let allocationID = UUID()
        let assetID = UUID()
        let firstGoalID = UUID()
        let secondGoalID = UUID()
        let firstEntry = AssetAllocationEditorEntry(
            allocationID: allocationID,
            assetID: assetID,
            goalID: firstGoalID,
            goalName: "First",
            status: .finished,
            amount: 10,
            finishedState: .pendingReview
        )
        let secondEntry = AssetAllocationEditorEntry(
            allocationID: allocationID,
            assetID: assetID,
            goalID: secondGoalID,
            goalName: "Second",
            status: .finished,
            amount: 10,
            finishedState: .pendingReview
        )
        let transitionedFirstEntry = AssetAllocationEditorEntry(
            allocationID: allocationID,
            assetID: assetID,
            goalID: firstGoalID,
            goalName: "First",
            status: .finished,
            amount: 10,
            finishedState: .reservedAsSpent
        )

        XCTAssertEqual(
            firstEntry.id,
            AssetAllocationEditorEntryID(goalID: firstGoalID, allocationID: allocationID)
        )
        XCTAssertNotEqual(firstEntry.id, secondEntry.id)
        XCTAssertEqual(firstEntry.id, transitionedFirstEntry.id)
        XCTAssertEqual(Set([firstEntry.id, secondEntry.id]).count, 2)
    }

    func testExactSnapshotEntryClassifiesAllocationAsReservedAndCarriesIdentity() {
        let allocationID = UUID()
        let goalID = UUID()
        let assetID = UUID()
        let amount = 12.34567891
        let snapshot = makeSnapshot(
            goalID: goalID,
            entries: [
                makeSnapshotEntry(
                    allocationID: allocationID,
                    assetID: assetID,
                    amount: amount,
                    settlement: .keepAsSpent
                )
            ]
        )

        let state = AssetAllocationEditorPolicy.finishedState(
            allocationID: allocationID,
            goalID: goalID,
            assetID: assetID,
            amount: amount,
            goalStatus: .finished,
            hasCompletionSnapshotData: true,
            snapshot: snapshot
        )
        let entry = AssetAllocationEditorEntry(
            allocationID: allocationID,
            assetID: assetID,
            goalID: goalID,
            goalName: "Reserved",
            status: .finished,
            amount: amount,
            finishedState: state
        )

        XCTAssertEqual(state, .reservedAsSpent)
        XCTAssertEqual(entry.allocationID, allocationID)
        XCTAssertEqual(entry.assetID, assetID)
    }

    func testSameAssetDifferentRetainedSnapshotEntryFailsClosed() {
        let allocationID = UUID()
        let goalID = UUID()
        let assetID = UUID()
        let snapshot = makeSnapshot(
            goalID: goalID,
            entries: [
                makeSnapshotEntry(
                    allocationID: UUID(),
                    assetID: assetID,
                    amount: 10,
                    settlement: .keepAsSpent
                )
            ]
        )

        XCTAssertNil(
            AssetAllocationEditorPolicy.finishedState(
                allocationID: allocationID,
                goalID: goalID,
                assetID: assetID,
                amount: 10,
                goalStatus: .finished,
                hasCompletionSnapshotData: true,
                snapshot: snapshot
            )
        )
    }

    func testSnapshotAmountMismatchFailsClosed() {
        let allocationID = UUID()
        let goalID = UUID()
        let assetID = UUID()
        let snapshot = makeSnapshot(
            goalID: goalID,
            entries: [
                makeSnapshotEntry(
                    allocationID: allocationID,
                    assetID: assetID,
                    amount: 10,
                    settlement: .keepAsSpent
                )
            ]
        )

        XCTAssertNil(
            AssetAllocationEditorPolicy.finishedState(
                allocationID: allocationID,
                goalID: goalID,
                assetID: assetID,
                amount: 10.00000002,
                goalStatus: .finished,
                hasCompletionSnapshotData: true,
                snapshot: snapshot
            )
        )
    }

    func testReleasedSnapshotEntryFailsClosedWithoutReopeningSettlement() {
        let allocationID = UUID()
        let goalID = UUID()
        let assetID = UUID()
        let snapshot = makeSnapshot(
            goalID: goalID,
            entries: [
                makeSnapshotEntry(
                    allocationID: allocationID,
                    assetID: assetID,
                    amount: 10,
                    settlement: .balanceAlreadyDecreased
                )
            ]
        )

        XCTAssertNil(
            AssetAllocationEditorPolicy.finishedState(
                allocationID: allocationID,
                goalID: goalID,
                assetID: assetID,
                amount: 10,
                goalStatus: .finished,
                hasCompletionSnapshotData: true,
                snapshot: snapshot
            )
        )
    }

    func testSnapshotForDifferentGoalFailsClosed() {
        let allocationID = UUID()
        let goalID = UUID()
        let assetID = UUID()
        let snapshot = makeSnapshot(
            goalID: UUID(),
            entries: [
                makeSnapshotEntry(
                    allocationID: allocationID,
                    assetID: assetID,
                    amount: 10,
                    settlement: .keepAsSpent
                )
            ]
        )

        XCTAssertNil(
            AssetAllocationEditorPolicy.finishedState(
                allocationID: allocationID,
                goalID: goalID,
                assetID: assetID,
                amount: 10,
                goalStatus: .finished,
                hasCompletionSnapshotData: true,
                snapshot: snapshot
            )
        )
    }

    func testEightDecimalFinishedRowsRemainVisibleAndPreservedForSave() {
        let pendingGoalID = UUID()
        let reservedGoalID = UUID()
        let tinyAmount = 0.00000001
        let entries = [
            AssetAllocationEditorEntry(
                goalID: pendingGoalID,
                goalName: "Tiny pending goal",
                status: .finished,
                amount: tinyAmount,
                finishedState: .pendingReview
            ),
            AssetAllocationEditorEntry(
                goalID: reservedGoalID,
                goalName: "Tiny reserved goal",
                status: .finished,
                amount: tinyAmount,
                finishedState: .reservedAsSpent
            )
        ]

        XCTAssertTrue(AssetAllocationEditorPolicy.shouldPresentAllocation(amount: tinyAmount))
        XCTAssertFalse(AssetAllocationEditorPolicy.shouldPresentAllocation(amount: 0.000000001))

        let breakdown = AssetAllocationEditorPolicy.breakdown(balance: 1, entries: entries)
        XCTAssertEqual(breakdown.pendingReviewAmount, tinyAmount, accuracy: 0.000000000001)
        XCTAssertEqual(breakdown.finishedReservedAmount, tinyAmount, accuracy: 0.000000000001)

        let amounts = AssetAllocationEditorPolicy.amountsForSave(
            activeGoalIDs: [],
            draft: [:],
            existingEntries: entries
        )
        XCTAssertEqual(amounts[pendingGoalID], tinyAmount)
        XCTAssertEqual(amounts[reservedGoalID], tinyAmount)
    }

    func testEditorSaveRoundTripKeepsEightDecimalFinishedAllocation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let goal = Goal(
            name: "Tiny finished allocation",
            currency: "USD",
            targetAmount: 1,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
        goal.lifecycleStatus = .finished
        let asset = Asset(currency: "BTC")
        let deposit = Transaction(amount: 1, asset: asset)
        let tinyAmount = 0.00000001
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: tinyAmount)
        asset.transactions = [deposit]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        context.insert(goal)
        context.insert(asset)
        context.insert(deposit)
        context.insert(allocation)
        try context.save()

        let entries = [
            AssetAllocationEditorEntry(
                goalID: goal.id,
                goalName: goal.name,
                status: .finished,
                amount: tinyAmount,
                finishedState: .pendingReview
            )
        ]
        let amounts = AssetAllocationEditorPolicy.amountsForSave(
            activeGoalIDs: [],
            draft: [:],
            existingEntries: entries
        )

        try AllocationService(modelContext: context).updateAllocations(
            for: asset,
            newAllocations: [(goal, amounts[goal.id] ?? 0)]
        )

        XCTAssertEqual(asset.allocations?.count, 1)
        XCTAssertEqual(goal.allocations?.count, 1)
        let persistedAmount = try XCTUnwrap(asset.allocations?.first?.amountValue)
        XCTAssertEqual(persistedAmount, tinyAmount, accuracy: 0.000000000001)
    }

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

    func testWarningPrioritizesReservedConflictWhenPendingRowIsAlsoPresent() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Reserved goal",
                status: .finished,
                amount: 110,
                finishedState: .reservedAsSpent
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Active goal",
                status: .active,
                amount: 10
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Legacy finished goal",
                status: .finished,
                amount: 1,
                finishedState: .pendingReview
            )
        ]

        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 100, entries: entries),
            .reservedAllocationDataConflict
        )
    }

    func testWarningPrioritizesReducibleActiveExcessWhenPendingRowIsAlsoPresent() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Reserved goal",
                status: .finished,
                amount: 90,
                finishedState: .reservedAsSpent
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Active goal",
                status: .active,
                amount: 20
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Legacy finished goal",
                status: .finished,
                amount: 1,
                finishedState: .pendingReview
            )
        ]

        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 100, entries: entries),
            .reduceActiveAllocations
        )
    }

    func testOverAllocatedBreakdownKeepsBalanceRelativeDisplayPercentagesAndNormalizesChartGeometry() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Active goal",
                status: .active,
                amount: 20
            ),
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Reserved goal",
                status: .finished,
                amount: 90,
                finishedState: .reservedAsSpent
            )
        ]

        let breakdown = AssetAllocationEditorPolicy.breakdown(balance: 100, entries: entries)

        XCTAssertEqual(breakdown.activePercentage, 0.2, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.finishedReservedPercentage, 0.9, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.activeChartPercentage, 20.0 / 110.0, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.finishedReservedChartPercentage, 90.0 / 110.0, accuracy: 0.0000001)
        XCTAssertEqual(
            breakdown.activeChartPercentage
                + breakdown.pendingReviewChartPercentage
                + breakdown.finishedReservedChartPercentage
                + breakdown.unallocatedChartPercentage,
            1,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 100, entries: entries),
            .reduceActiveAllocations
        )
    }

    func testReservedOnlyExcessShowsTruthfulPercentageAndNonActionableDataWarning() {
        let entries = [
            AssetAllocationEditorEntry(
                goalID: UUID(),
                goalName: "Reserved goal",
                status: .finished,
                amount: 110,
                finishedState: .reservedAsSpent
            )
        ]

        let breakdown = AssetAllocationEditorPolicy.breakdown(balance: 100, entries: entries)

        XCTAssertEqual(breakdown.finishedReservedPercentage, 1.1, accuracy: 0.0000001)
        XCTAssertEqual(breakdown.finishedReservedChartPercentage, 1, accuracy: 0.0000001)
        XCTAssertEqual(
            AssetAllocationEditorPolicy.warning(balance: 100, entries: entries),
            .reservedAllocationDataConflict
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            AllocationHistory.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            CompletionEvent.self,
            ExecutionSnapshot.self
        ])
        let config = ModelConfiguration(
            "assetAllocationEditorPolicyTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSnapshot(
        goalID: UUID,
        entries: [GoalCompletionSnapshot.Entry]
    ) -> GoalCompletionSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        return GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: goalID,
            goalName: "Finished",
            goalCurrency: "USD",
            goalTargetAmount: 100,
            goalCompletedAt: timestamp,
            snapshotCreatedAt: timestamp,
            entries: entries
        )
    }

    private func makeSnapshotEntry(
        allocationID: UUID,
        assetID: UUID,
        amount: Double,
        settlement: FinishedAllocationSettlement
    ) -> GoalCompletionSnapshot.Entry {
        GoalCompletionSnapshot.Entry(
            allocationID: allocationID,
            assetID: assetID,
            assetCurrency: "BTC",
            amount: amount,
            accountingMode: .manual,
            settlement: settlement,
            bestKnownBalance: 1,
            balanceCapturedAt: Date(timeIntervalSince1970: 1_900_000_000),
            balanceTiming: .completionTime
        )
    }
}

private extension AssetAllocationEditorEntry {
    init(
        goalID: UUID,
        goalName: String,
        status: GoalLifecycleStatus,
        amount: Double,
        finishedState: FinishedAllocationEditorState? = nil
    ) {
        self.init(
            allocationID: UUID(),
            assetID: UUID(),
            goalID: goalID,
            goalName: goalName,
            status: status,
            amount: amount,
            finishedState: finishedState
        )
    }
}
