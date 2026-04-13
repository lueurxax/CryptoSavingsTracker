import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalRepositoryTests {
    @Test("GoalRepository clears retired reminder fields before save")
    func goalRepositoryClearsRetiredReminderFieldsOnSave() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let repository = GoalRepository(modelContext: context)
        let goal = TestDataFactory.createSampleGoal(name: "Repository Save Goal")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)

        try await repository.save(goal)

        let savedGoals = try context.fetch(FetchDescriptor<Goal>())
        #expect(savedGoals.count == 1)
        #expect(savedGoals.first?.reminderFrequency == nil)
        #expect(savedGoals.first?.reminderTime == nil)
        #expect(savedGoals.first?.firstReminderDate == nil)
    }
}
