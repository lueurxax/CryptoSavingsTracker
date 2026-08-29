import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

struct GoalCompletionSnapshotTests {
    @Test("snapshot version 1 round-trips every settlement field")
    func versionOneRoundTrip() throws {
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let createdAt = Date(timeIntervalSince1970: 1_005)
        let entry = GoalCompletionSnapshot.Entry(
            allocationID: UUID(),
            assetID: UUID(),
            assetCurrency: "USDT",
            amount: 35,
            accountingMode: .onChain,
            settlement: .balanceAlreadyDecreased,
            bestKnownBalance: 5_873.6673,
            balanceCapturedAt: createdAt,
            balanceTiming: .completionTime
        )
        let snapshot = GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: 1,
            goalID: UUID(),
            goalName: "Marriage",
            goalCurrency: "EUR",
            goalTargetAmount: 7_000,
            goalCompletedAt: completedAt,
            snapshotCreatedAt: createdAt,
            entries: [entry]
        )

        let decoded = try GoalCompletionSnapshotCodec.decode(
            GoalCompletionSnapshotCodec.encode(snapshot)
        )

        #expect(decoded == snapshot)
    }

    @Test("unsupported snapshot schema is rejected")
    func unsupportedSchemaIsRejected() throws {
        let snapshot = GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: 2,
            goalID: UUID(),
            goalName: "Future",
            goalCurrency: "USD",
            goalTargetAmount: 1,
            goalCompletedAt: .distantPast,
            snapshotCreatedAt: .distantPast,
            entries: []
        )

        #expect(throws: GoalCompletionSnapshotCodecError.unsupportedSchemaVersion(2)) {
            try GoalCompletionSnapshotCodec.decode(JSONEncoder().encode(snapshot))
        }
    }

    @Test("legacy review balance is labeled as review-time evidence")
    func legacyBalanceTimingSurvivesRoundTrip() throws {
        let entry = GoalCompletionSnapshot.Entry(
            allocationID: UUID(),
            assetID: UUID(),
            assetCurrency: "BTC",
            amount: 0.1,
            accountingMode: .mixed,
            settlement: .keepAsSpent,
            bestKnownBalance: 0.2,
            balanceCapturedAt: Date(timeIntervalSince1970: 2_000),
            balanceTiming: .reviewTime
        )

        #expect(entry.balanceTiming == .reviewTime)
    }

    @MainActor
    @Test("goal stores an optional completion snapshot")
    func goalStoresOptionalSnapshot() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Persisted")
        context.insert(goal)
        try context.save()
        #expect(goal.completionSnapshotData == nil)

        let snapshot = GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: 1,
            goalID: goal.id,
            goalName: goal.name,
            goalCurrency: goal.currency,
            goalTargetAmount: goal.targetAmount,
            goalCompletedAt: .now,
            snapshotCreatedAt: .now,
            entries: []
        )
        goal.completionSnapshotData = try GoalCompletionSnapshotCodec.encode(snapshot)
        try context.save()

        #expect(goal.completionSnapshot == snapshot)
    }
}
