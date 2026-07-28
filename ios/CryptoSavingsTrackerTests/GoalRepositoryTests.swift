import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalRepositoryTests {
    @Test("GoalRepository active list excludes every inactive lifecycle state")
    func goalRepositoryFetchesOnlyActiveGoals() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let repository = GoalRepository(modelContext: context)
        let active = TestDataFactory.createSampleGoal(name: "Active")
        let archived = TestDataFactory.createSampleGoal(name: "Archived")
        let cancelled = TestDataFactory.createSampleGoal(name: "Cancelled")
        let finished = TestDataFactory.createSampleGoal(name: "Finished")
        archived.archive()
        cancelled.markCancelled()
        finished.markFinished()

        context.insert(archived)
        context.insert(cancelled)
        context.insert(finished)
        context.insert(active)
        try context.save()

        let goals = try await repository.fetchGoals()

        #expect(goals.map(\.id) == [active.id])
    }

    @Test("Archived goal query exposes only restorable deleted goals")
    func archivedGoalQueryExposesDeletedGoals() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let active = TestDataFactory.createSampleGoal(name: "Active")
        let archived = TestDataFactory.createSampleGoal(name: "Archived")
        let cancelled = TestDataFactory.createSampleGoal(name: "Cancelled")
        archived.archive()
        cancelled.markCancelled()
        context.insert(active)
        context.insert(archived)
        context.insert(cancelled)
        try context.save()

        let goals = try context.fetch(GoalListQuery.archivedDescriptor())

        #expect(goals.map(\.id) == [archived.id])
    }

    @Test("Sidebar selection moves from an inactive goal to an active goal")
    func sidebarSelectionReconcilesInactiveGoal() {
        let inactive = TestDataFactory.createSampleGoal(name: "Inactive")
        let active = TestDataFactory.createSampleGoal(name: "Active")
        inactive.archive()

        let selection = GoalSidebarSelectionPolicy.reconcile(
            selectedGoal: inactive,
            activeGoals: [inactive, active]
        )

        #expect(selection?.id == active.id)
    }

    @Test("Sidebar selection clears when no active goal remains")
    func sidebarSelectionClearsWithoutActiveGoals() {
        let inactive = TestDataFactory.createSampleGoal(name: "Inactive")
        inactive.archive()

        let selection = GoalSidebarSelectionPolicy.reconcile(
            selectedGoal: inactive,
            activeGoals: [inactive]
        )

        #expect(selection == nil)
    }

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
