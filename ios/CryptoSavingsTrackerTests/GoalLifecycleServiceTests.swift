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

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
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

        await service.finishGoal(goal, at: timestamp)

        #expect(goal.lifecycleStatus == .finished)
        #expect(goal.lifecycleStatusChangedAt == timestamp)
        #expect(notificationManager.cancelledGoalIDs == [goal.id])
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

    private func makeGoal(name: String) -> Goal {
        let goal = TestDataFactory.createSampleGoal(name: name)
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3_600)
        return goal
    }

    private func assertReminderFieldsCleared(_ goal: Goal) {
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }
}
