import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalOnboardingMutationAtomicityTests {
    private enum ForcedSaveError: Error {
        case failed
    }

    @MainActor
    private final class FailFirstSave {
        private let modelContext: ModelContext
        private(set) var attempts = 0

        init(modelContext: ModelContext) {
            self.modelContext = modelContext
        }

        func save() throws {
            attempts += 1
            if attempts == 1 {
                throw ForcedSaveError.failed
            }
            try modelContext.save()
        }
    }

    @MainActor
    private final class AlwaysFailSave {
        private(set) var attempts = 0

        func save() throws {
            attempts += 1
            throw ForcedSaveError.failed
        }
    }

    @MainActor
    private final class SpyNotificationManager: NotificationManager {
        private(set) var cancelledGoalIDs: [UUID] = []

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
            cancelledGoalIDs.append(goal.id)
        }
    }

    private final class NotificationFlag: @unchecked Sendable {
        var wasPosted = false
    }

    private final class UndoProbe: NSObject {
        var wasUndone = false
    }

    @Test("Goal create uses the save seam, rolls back its graph, and retries once")
    func goalCreateFailureIsAtomicAndSameContextRetrySafe() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        context.insert(unrelatedGoal)
        try context.save()

        let targetGoal = TestDataFactory.createSampleGoal(name: "Retryable goal")
        targetGoal.reminderFrequency = ReminderFrequency.weekly.rawValue
        targetGoal.reminderTime = Date(timeIntervalSince1970: 1_000)
        targetGoal.firstReminderDate = Date(timeIntervalSince1970: 2_000)

        let priorUndoManager = UndoManager()
        let undoProbe = UndoProbe()
        priorUndoManager.registerUndo(withTarget: undoProbe) { probe in
            probe.wasUndone = true
        }
        context.undoManager = priorUndoManager

        let failFirstSave = FailFirstSave(modelContext: context)
        let notificationManager = SpyNotificationManager()
        let notificationFlag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationFlag.wasPosted = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let service = GoalMutationService(
            modelContext: context,
            notificationManager: notificationManager,
            accessGuard: GoalOnboardingAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.createGoal(targetGoal)
        }

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 1)
        #expect(targetGoal.modelContext == nil)
        #expect(targetGoal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(targetGoal.reminderTime == Date(timeIntervalSince1970: 1_000))
        #expect(targetGoal.firstReminderDate == Date(timeIntervalSince1970: 2_000))
        #expect(unrelatedGoal.name == "Durable unrelated goal")
        #expect(context.undoManager === priorUndoManager)
        #expect(priorUndoManager.canUndo)
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
        #expect(notificationFlag.wasPosted == false)

        priorUndoManager.undo()
        #expect(undoProbe.wasUndone)

        try await service.createGoal(targetGoal)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect(
            try context.fetch(FetchDescriptor<Goal>()).filter {
                $0.id == targetGoal.id
            }.count == 1
        )
        #expect(targetGoal.reminderFrequency == nil)
        #expect(targetGoal.reminderTime == nil)
        #expect(targetGoal.firstReminderDate == nil)
        #expect(notificationManager.cancelledGoalIDs == [targetGoal.id])
        #expect(notificationFlag.wasPosted)
    }

    @Test("Goal save uses the injected seam and restores service-owned reminder changes")
    func goalSaveFailurePreservesPreexistingUnsavedEdits() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Durable goal")
        goal.reminderFrequency = ReminderFrequency.monthly.rawValue
        goal.reminderTime = Date(timeIntervalSince1970: 3_000)
        goal.firstReminderDate = Date(timeIntervalSince1970: 4_000)
        context.insert(goal)
        try context.save()

        goal.name = "Unsaved rename"
        let alwaysFailSave = AlwaysFailSave()
        let notificationManager = SpyNotificationManager()
        let service = GoalMutationService(
            modelContext: context,
            notificationManager: notificationManager,
            accessGuard: GoalOnboardingAllowAllAccessGuard(),
            saveChanges: alwaysFailSave.save
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.saveGoal(goal)
        }

        #expect(alwaysFailSave.attempts == 1)
        #expect(goal.name == "Unsaved rename")
        #expect(goal.reminderFrequency == ReminderFrequency.monthly.rawValue)
        #expect(goal.reminderTime == Date(timeIntervalSince1970: 3_000))
        #expect(goal.firstReminderDate == Date(timeIntervalSince1970: 4_000))
        #expect(notificationManager.cancelledGoalIDs.isEmpty)

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == goal.id
            }
        )
        #expect(durableGoal.name == "Durable goal")
        #expect(durableGoal.reminderFrequency == ReminderFrequency.monthly.rawValue)
    }

    @Test("Onboarding failure removes only its graph and same-context retry creates one graph")
    func onboardingFailureIsAtomicAndSameContextRetrySafe() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        context.insert(unrelatedGoal)
        try context.save()

        let failFirstSave = FailFirstSave(modelContext: context)
        let notificationManager = SpyNotificationManager()
        let notificationFlag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationFlag.wasPosted = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let service = OnboardingMutationService(
            modelContext: context,
            notificationManager: notificationManager,
            saveChanges: failFirstSave.save
        )
        let template = GoalTemplate.allTemplates[0]

        await #expect(throws: PersistenceMutationError.self) {
            try await service.createGoalFromTemplate(template, userProfile: UserProfile())
        }

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 1)
        #expect(
            try context.fetch(FetchDescriptor<Goal>()).contains {
                $0.name == template.createGoal().name
            } == false
        )
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(unrelatedGoal.name == "Durable unrelated goal")
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
        #expect(notificationFlag.wasPosted == false)

        try await service.createGoalFromTemplate(template, userProfile: UserProfile())

        context.processPendingChanges()
        let createdGoals = try context.fetch(FetchDescriptor<Goal>()).filter {
            $0.name == template.createGoal().name
        }
        #expect(failFirstSave.attempts == 2)
        #expect(createdGoals.count == 1)
        #expect(
            try context.fetch(FetchDescriptor<AssetAllocation>()).count
                == template.generateAssets().count
        )
        #expect(notificationManager.cancelledGoalIDs == createdGoals.map(\.id))
        #expect(notificationFlag.wasPosted)
    }

    @Test("Onboarding failure leaves no durable graph and can retry from a fresh context")
    func onboardingFailureIsFreshContextRetrySafe() async throws {
        let container = try TestContainer.create()
        let failingContext = ModelContext(container)
        let alwaysFailSave = AlwaysFailSave()
        let template = GoalTemplate.allTemplates[0]
        let failingService = OnboardingMutationService(
            modelContext: failingContext,
            notificationManager: SpyNotificationManager(),
            saveChanges: alwaysFailSave.save
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await failingService.createGoalFromTemplate(template, userProfile: UserProfile())
        }

        let retryContext = ModelContext(container)
        #expect(try retryContext.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(try retryContext.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try retryContext.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)

        let retryService = OnboardingMutationService(
            modelContext: retryContext,
            notificationManager: SpyNotificationManager()
        )
        try await retryService.createGoalFromTemplate(template, userProfile: UserProfile())

        #expect(
            try retryContext.fetch(FetchDescriptor<Goal>()).filter {
                $0.name == template.createGoal().name
            }.count == 1
        )
        #expect(
            try retryContext.fetch(FetchDescriptor<AssetAllocation>()).count
                == template.generateAssets().count
        )
    }

    @Test("Onboarding persists exactly the asset recommendations selected by the user")
    func onboardingPersistsExactlySelectedAssets() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let template = GoalTemplate.allTemplates[1]
        let selectedAssetCurrencies: Set<String> = [
            template.recommendedAssets[1].currency,
            template.recommendedAssets[3].currency
        ]
        let service = OnboardingMutationService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        )

        try await service.createGoalFromTemplate(
            template,
            userProfile: UserProfile(),
            selectedAssetCurrencies: selectedAssetCurrencies
        )

        let persistedCurrencies = Set(
            try context.fetch(FetchDescriptor<Asset>()).map(\.currency)
        )
        #expect(persistedCurrencies == selectedAssetCurrencies)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 2)
    }

    @Test("Onboarding retry after a durable commit reconciles one deterministic graph")
    func onboardingCommitBeforeCompletionFlagIsRestartSafe() async throws {
        let container = try TestContainer.create()
        let template = GoalTemplate.allTemplates[1]
        let selected = Set(template.recommendedAssets.prefix(2).map(\.currency))

        let firstContext = ModelContext(container)
        let firstService = OnboardingMutationService(
            modelContext: firstContext,
            notificationManager: SpyNotificationManager()
        )
        try await firstService.createGoalFromTemplate(
            template,
            userProfile: UserProfile(),
            selectedAssetCurrencies: selected
        )
        let firstGoalID = try #require(
            firstContext.fetch(FetchDescriptor<Goal>()).first?.id
        )

        // Simulate termination after SwiftData committed but before the
        // onboarding completion flag was persisted.
        let restartedContext = ModelContext(container)
        let restartedService = OnboardingMutationService(
            modelContext: restartedContext,
            notificationManager: SpyNotificationManager()
        )
        try await restartedService.createGoalFromTemplate(
            template,
            userProfile: UserProfile(),
            // A process restart rebuilds the screen's default selection. The
            // durable operation must reconcile the committed graph instead of
            // silently adding newly-defaulted assets.
            selectedAssetCurrencies: Set(template.recommendedAssets.map(\.currency))
        )

        let goals = try restartedContext.fetch(FetchDescriptor<Goal>())
        let assets = try restartedContext.fetch(FetchDescriptor<Asset>())
        let allocations = try restartedContext.fetch(FetchDescriptor<AssetAllocation>())
        #expect(goals.count == 1)
        #expect(goals.first?.id == firstGoalID)
        #expect(Set(assets.map(\.currency)) == selected)
        #expect(allocations.count == selected.count)
    }

    @Test("Goal edit caller preserves reminder lifecycle state and modification date across save retry")
    func goalEditCallerFailureRestoresServiceOwnedStateBeforeRetry() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Original goal")
        let originalModifiedAt = Date(timeIntervalSince1970: 5_000)
        let reminderTime = Date(timeIntervalSince1970: 6_000)
        let firstReminderDate = Date(timeIntervalSince1970: 7_000)
        goal.lastModifiedDate = originalModifiedAt
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = reminderTime
        goal.firstReminderDate = firstReminderDate
        context.insert(goal)
        try context.save()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = GoalMutationService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            accessGuard: GoalOnboardingAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )
        let viewModel = GoalEditViewModel(
            goal: goal,
            modelContext: context,
            goalMutationService: service
        )
        goal.name = "Edited goal"
        viewModel.triggerChangeDetection()

        await #expect(throws: PersistenceMutationError.self) {
            try await viewModel.save()
        }

        #expect(failFirstSave.attempts == 1)
        #expect(goal.name == "Edited goal")
        #expect(goal.lastModifiedDate == originalModifiedAt)
        #expect(goal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(goal.reminderTime == reminderTime)
        #expect(goal.firstReminderDate == firstReminderDate)

        try await viewModel.save()

        #expect(failFirstSave.attempts == 2)
        #expect(goal.lastModifiedDate > originalModifiedAt)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == goal.id
            }
        )
        #expect(durableGoal.name == "Edited goal")
        #expect(durableGoal.reminderFrequency == nil)
        #expect(durableGoal.lastModifiedDate > originalModifiedAt)
    }

    @Test("Nested operation transactions fail safely and restore the caller undo manager")
    func nestedOperationTransactionIsRejectedSafely() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let priorUndoManager = UndoManager()
        context.undoManager = priorUndoManager

        try PersistenceOperationTransaction.perform(
            in: context,
            saveChanges: {},
            restoreTouchedState: {}
        ) {
            do {
                try PersistenceOperationTransaction.perform(
                    in: context,
                    saveChanges: {},
                    restoreTouchedState: {}
                ) {}
                Issue.record("Nested operations on one ModelContext must be rejected")
            } catch let error as PersistenceOperationTransactionError {
                switch error {
                case .nestedOperationUnsupported:
                    break
                case .durableModelResolutionFailed:
                    Issue.record("Unexpected durable-resolution error")
                }
            }
        }

        #expect(context.undoManager === priorUndoManager)
    }

    @Test("A failed operation restores the caller undo manager and its existing stack")
    func failedOperationRestoresPriorUndoStack() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let priorUndoManager = UndoManager()
        let undoProbe = UndoProbe()
        priorUndoManager.registerUndo(withTarget: undoProbe) { probe in
            probe.wasUndone = true
        }
        context.undoManager = priorUndoManager

        #expect(throws: ForcedSaveError.self) {
            try PersistenceOperationTransaction.perform(
                in: context,
                saveChanges: {
                    throw ForcedSaveError.failed
                },
                restoreTouchedState: {}
            ) {}
        }

        #expect(context.undoManager === priorUndoManager)
        #expect(priorUndoManager.canUndo)
        priorUndoManager.undo()
        #expect(undoProbe.wasUndone)
    }
}

@MainActor
private final class GoalOnboardingAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}
