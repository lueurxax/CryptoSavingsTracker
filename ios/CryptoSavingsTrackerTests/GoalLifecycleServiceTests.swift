import Foundation
import UserNotifications
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalLifecycleServiceTests {
    @MainActor
    private final class SpyNotificationManager: NotificationManager {
        var cancelledGoalIDs: [UUID] = []
        var onCancel: ((Goal) -> Void)?

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
            onCancel?(goal)
            cancelledGoalIDs.append(goal.id)
        }

        override func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            Issue.record("GoalLifecycleService should not request notification authorization.")
            return false
        }
    }

    @Test("GoalLifecycleService clears reminder fields during cancel")
    func cancelGoalClearsReminderFields() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let notificationManager = SpyNotificationManager()
        let service = GoalLifecycleService(modelContext: context, notificationManager: notificationManager)
        let timestamp = Date(timeIntervalSince1970: 1_234)
        let goal = makeGoal(name: "Cancel Goal")
        context.insert(goal)
        try context.save()

        await service.cancelGoal(goal, at: timestamp)

        #expect(goal.lifecycleStatus == .cancelled)
        #expect(goal.lifecycleStatusChangedAt == timestamp)
        #expect(notificationManager.cancelledGoalIDs == [goal.id])
        assertReminderFieldsCleared(goal)
    }

    @Test("GoalLifecycleService clears reminder fields during finish")
    func finishGoalClearsReminderFields() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let notificationManager = SpyNotificationManager()
        let service = GoalLifecycleService(modelContext: context, notificationManager: notificationManager)
        let timestamp = Date(timeIntervalSince1970: 2_345)
        let goal = makeGoal(name: "Finish Goal")
        context.insert(goal)
        try context.save()
        var observedPersistedSnapshotBeforeCancellation = false
        notificationManager.onCancel = { cancelledGoal in
            let verificationContext = ModelContext(container)
            let persistedGoal = try? verificationContext.fetch(FetchDescriptor<Goal>())
                .first { $0.id == cancelledGoal.id }
            observedPersistedSnapshotBeforeCancellation = persistedGoal?.completionSnapshotData != nil
        }

        let plan = try service.prepareFinishGoal(goal)
        let snapshot = try await service.finishGoal(
            goal,
            plan: plan,
            decisions: [],
            at: timestamp
        )

        #expect(goal.lifecycleStatus == .finished)
        #expect(goal.lifecycleStatusChangedAt == timestamp)
        #expect(goal.completionSnapshot == snapshot)
        #expect(notificationManager.cancelledGoalIDs == [goal.id])
        #expect(observedPersistedSnapshotBeforeCancellation)
        assertReminderFieldsCleared(goal)
    }

    @Test("GoalLifecycleService clears reminder fields during delete")
    func deleteGoalClearsReminderFields() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let notificationManager = SpyNotificationManager()
        let service = GoalLifecycleService(modelContext: context, notificationManager: notificationManager)
        let timestamp = Date(timeIntervalSince1970: 3_456)
        let goal = makeGoal(name: "Delete Goal")
        context.insert(goal)
        try context.save()

        await service.deleteGoal(goal, at: timestamp)

        #expect(goal.lifecycleStatus == .deleted)
        #expect(goal.lifecycleStatusChangedAt == timestamp)
        #expect(notificationManager.cancelledGoalIDs == [goal.id])
        assertReminderFieldsCleared(goal)
    }

    @Test("snapshot-backed finished retained allocation cannot be cancelled")
    func snapshotBackedFinishedGoalCancelIsNoOp() async throws {
        try await assertFinishedGoalCancelIsNoOp(snapshotBacked: true)
    }

    @Test("legacy finished allocation cannot be cancelled")
    func legacyFinishedGoalCancelIsNoOp() async throws {
        try await assertFinishedGoalCancelIsNoOp(snapshotBacked: false)
    }

    private func makeGoal(name: String) -> Goal {
        let goal = TestDataFactory.createSampleGoal(name: name)
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3_600)
        return goal
    }

    private func assertFinishedGoalCancelIsNoOp(snapshotBacked: Bool) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let notificationManager = SpyNotificationManager()
        let service = GoalLifecycleService(modelContext: context, notificationManager: notificationManager)
        let finishedAt = Date(timeIntervalSince1970: 4_000)
        let goal = makeGoal(name: snapshotBacked ? "Settled Finished" : "Legacy Finished")
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 40)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        goal.markFinished(at: finishedAt)
        if snapshotBacked {
            goal.completionSnapshotData = try GoalCompletionSnapshotCodec.encode(
                GoalCompletionSnapshot(
                    id: UUID(),
                    schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
                    goalID: goal.id,
                    goalName: goal.name,
                    goalCurrency: goal.currency,
                    goalTargetAmount: goal.targetAmount,
                    goalCompletedAt: finishedAt,
                    snapshotCreatedAt: finishedAt,
                    entries: [
                        GoalCompletionSnapshot.Entry(
                            allocationID: allocation.id,
                            assetID: asset.id,
                            assetCurrency: asset.currency,
                            amount: 40,
                            accountingMode: .manual,
                            settlement: .keepAsSpent,
                            bestKnownBalance: 100,
                            balanceCapturedAt: finishedAt,
                            balanceTiming: .completionTime
                        )
                    ]
                )
            )
        }
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())
        let originalSnapshotData = goal.completionSnapshotData
        let originalLastModifiedDate = goal.lastModifiedDate
        var lifecycleNotifications: [Notification.Name] = []
        let center = NotificationCenter.default
        let tokens = [Notification.Name.goalDeleted, .goalUpdated].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { notification in
                guard (notification.object as? Goal)?.id == goal.id else { return }
                lifecycleNotifications.append(notification.name)
            }
        }
        defer {
            tokens.forEach(center.removeObserver)
        }

        await service.cancelGoal(goal, at: Date(timeIntervalSince1970: 5_000))

        #expect(goal.lifecycleStatus == .finished)
        #expect(goal.lifecycleStatusChangedAt == finishedAt)
        #expect(goal.lastModifiedDate == originalLastModifiedDate)
        #expect(goal.completionSnapshotData == originalSnapshotData)
        #expect(goal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(goal.reminderTime != nil)
        #expect(goal.firstReminderDate != nil)
        #expect(goal.allocations?.contains { $0.id == allocation.id } == true)
        #expect(asset.allocations?.contains { $0.id == allocation.id } == true)
        #expect(try context.fetchCount(FetchDescriptor<AssetAllocation>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == baselineHistoryCount)
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
        #expect(lifecycleNotifications.isEmpty)
    }

    private func assertReminderFieldsCleared(_ goal: Goal) {
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }
}
