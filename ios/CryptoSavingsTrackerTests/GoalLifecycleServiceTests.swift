import Foundation
import UserNotifications
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalLifecycleServiceTests {
    private enum ForcedSaveError: Error {
        case failed
    }

    private final class NotificationRecorder: @unchecked Sendable {
        var count = 0
    }

    private final class SharedGoalNotificationRecorder: @unchecked Sendable {
        struct Event {
            let affectedGoalIDs: [UUID]
            let reason: String?
        }

        var events: [Event] = []

        func record(_ notification: Notification) {
            events.append(
                Event(
                    affectedGoalIDs: notification.userInfo?["affectedGoalIDs"] as? [UUID] ?? [],
                    reason: notification.userInfo?["reason"] as? String
                )
            )
        }
    }

    @MainActor
    private final class LifecycleAllowAllAccessGuard:
        FamilyShareAccessChecking {
        func isSharedGoalID(_ goalID: UUID) -> Bool { false }
        func assertOwnerWritable(goalID: UUID) throws {}
        func assertOwnerWritable(goal: Goal) throws {}
        func assertOwnerWritable(asset: Asset) throws {}
        func assertOwnerWritable(transaction: Transaction) throws {}
        func assertOwnerWritable(plan: MonthlyPlan) throws {}
        func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
        func assertOwnerWritable(goals: [Goal]) throws {}
    }

    private enum LifecycleAction: CaseIterable {
        case cancel
        case finish
        case delete
    }

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

    @MainActor
    private final class SuspendingNotificationManager: NotificationManager {
        private var cancellationStartedContinuation: CheckedContinuation<Void, Never>?
        private var cancellationResumeContinuation: CheckedContinuation<Void, Never>?
        private var cancellationStarted = false
        private var shouldSuspendNextCancellation = true

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
            cancellationStarted = true
            cancellationStartedContinuation?.resume()
            cancellationStartedContinuation = nil

            guard shouldSuspendNextCancellation else { return }
            shouldSuspendNextCancellation = false
            await withCheckedContinuation { continuation in
                cancellationResumeContinuation = continuation
            }
        }

        func waitUntilCancellationStarts() async {
            guard !cancellationStarted else { return }
            await withCheckedContinuation { continuation in
                cancellationStartedContinuation = continuation
            }
        }

        func resumeCancellation() {
            cancellationResumeContinuation?.resume()
            cancellationResumeContinuation = nil
        }
    }

    @Test("Cancelling a goal removes its allocations even when the remaining allocation exceeds the latest balance")
    func cancelGoalFreesAllocationFromOverAllocatedAsset() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeOverAllocatedFixture(in: context)
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        )

        try await service.cancelGoal(fixture.targetGoal)

        #expect(fixture.targetGoal.lifecycleStatus == .cancelled)
        try assertOnlyRemainingAllocationPersists(fixture, in: context)
    }

    @Test("Deleting a goal removes its allocations even when the remaining allocation exceeds the latest balance")
    func deleteGoalFreesAllocationFromOverAllocatedAsset() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeOverAllocatedFixture(in: context)
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        )

        try await service.deleteGoal(fixture.targetGoal)

        #expect(fixture.targetGoal.lifecycleStatus == .deleted)
        try assertOnlyRemainingAllocationPersists(fixture, in: context)
    }

    @Test("Each successful lifecycle action emits one shared-goal mutation after saving")
    func successfulLifecycleActionsEmitOneSharedGoalMutation() async throws {
        for action in LifecycleAction.allCases {
            let container = try TestContainer.create()
            let context = ModelContext(container)
            let goal = makeGoal(name: "Shared lifecycle goal")
            context.insert(goal)
            try context.save()
            let goalID = goal.id

            let recorder = SharedGoalNotificationRecorder()
            let observer = NotificationCenter.default.addObserver(
                forName: .sharedGoalDataDidChange,
                object: nil,
                queue: nil
            ) { notification in
                guard (notification.userInfo?["affectedGoalIDs"] as? [UUID])?.contains(goalID) == true else {
                    return
                }
                recorder.record(notification)
            }

            let service = GoalLifecycleService(
                modelContext: context,
                notificationManager: SpyNotificationManager()
            )
            switch action {
            case .cancel:
                try await service.cancelGoal(goal)
            case .finish:
                try await service.finishGoal(goal)
            case .delete:
                try await service.deleteGoal(goal)
            }
            NotificationCenter.default.removeObserver(observer)

            #expect(recorder.events.count == 1)
            #expect(recorder.events.first?.affectedGoalIDs == [goalID])
            #expect(recorder.events.first?.reason == "goalMutation")
        }
    }

    @Test("A failed lifecycle save rolls back allocations and emits no external side effects")
    func cancelGoalRollsBackWhenSaveFails() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeOverAllocatedFixture(in: context)
        let notificationManager = SpyNotificationManager()
        let recorder = NotificationRecorder()
        let sharedGoalRecorder = SharedGoalNotificationRecorder()
        let targetGoalID = fixture.targetGoal.id
        let originalLifecycleStatusChangedAt = fixture.targetGoal.lifecycleStatusChangedAt
        let originalLastModifiedDate = fixture.targetGoal.lastModifiedDate
        let originalReminderFrequency = fixture.targetGoal.reminderFrequency
        let originalReminderTime = fixture.targetGoal.reminderTime
        let originalFirstReminderDate = fixture.targetGoal.firstReminderDate
        fixture.targetAllocation.updateAmount(30)
        let originalAllocationAmount = fixture.targetAllocation.amount
        let originalAllocationCreatedDate = fixture.targetAllocation.createdDate
        let originalAllocationLastModifiedDate = fixture.targetAllocation.lastModifiedDate
        let observer = NotificationCenter.default.addObserver(
            forName: .goalDeleted,
            object: fixture.targetGoal,
            queue: nil
        ) { _ in
            recorder.count += 1
        }
        let sharedGoalObserver = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.userInfo?["affectedGoalIDs"] as? [UUID])?.contains(targetGoalID) == true else {
                return
            }
            sharedGoalRecorder.record(notification)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            NotificationCenter.default.removeObserver(sharedGoalObserver)
        }

        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: notificationManager,
            saveChanges: { throw ForcedSaveError.failed }
        )

        await #expect(throws: ForcedSaveError.self) {
            try await service.cancelGoal(fixture.targetGoal)
        }

        context.processPendingChanges()
        let persistedAllocationIDs = Set(
            try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id)
        )
        #expect(fixture.targetGoal.lifecycleStatus == .active)
        #expect(fixture.targetGoal.lifecycleStatusChangedAt == originalLifecycleStatusChangedAt)
        #expect(fixture.targetGoal.lastModifiedDate == originalLastModifiedDate)
        #expect(fixture.targetGoal.reminderFrequency == originalReminderFrequency)
        #expect(fixture.targetGoal.reminderTime == originalReminderTime)
        #expect(fixture.targetGoal.firstReminderDate == originalFirstReminderDate)
        #expect(persistedAllocationIDs.contains(fixture.targetAllocation.id))
        #expect(persistedAllocationIDs.contains(fixture.remainingAllocation.id))
        #expect(Set(fixture.asset.allocations?.map(\.id) ?? []) == persistedAllocationIDs)
        #expect(fixture.targetGoal.allocations?.map(\.id) == [fixture.targetAllocation.id])
        #expect(fixture.targetAllocation.asset?.id == fixture.asset.id)
        #expect(fixture.targetAllocation.goal?.id == fixture.targetGoal.id)
        #expect(fixture.targetAllocation.amount == originalAllocationAmount)
        #expect(fixture.targetAllocation.createdDate == originalAllocationCreatedDate)
        #expect(fixture.targetAllocation.lastModifiedDate == originalAllocationLastModifiedDate)
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
        #expect(recorder.count == 0)
        #expect(sharedGoalRecorder.events.isEmpty)
    }

    @Test("Lifecycle persistence rejects unrelated pending edits before saving")
    func cancelGoalRejectsUnrelatedPendingChangesBeforeSave() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let targetGoal = makeGoal(name: "Target Goal")
        let unrelatedGoal = makeGoal(name: "Persisted unrelated goal")
        context.insert(targetGoal)
        context.insert(unrelatedGoal)
        try context.save()

        unrelatedGoal.name = "Unsaved unrelated rename"
        unrelatedGoal.targetAmount = 9_999
        let insertedGoal = makeGoal(name: "Unsaved inserted goal")
        context.insert(insertedGoal)

        var didAttemptSave = false
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            saveChanges: {
                didAttemptSave = true
                throw ForcedSaveError.failed
            }
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.cancelGoal(targetGoal)
        }

        let goalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))
        #expect(didAttemptSave == false)
        #expect(targetGoal.lifecycleStatus == .active)
        #expect(unrelatedGoal.name == "Unsaved unrelated rename")
        #expect(unrelatedGoal.targetAmount == 9_999)
        #expect(insertedGoal.modelContext === context)
        #expect(goalIDs.contains(insertedGoal.id))

        let durableGoals = try ModelContext(container).fetch(FetchDescriptor<Goal>())
        #expect(
            durableGoals.first { $0.id == unrelatedGoal.id }?.name
                == "Persisted unrelated goal"
        )
        #expect(durableGoals.contains { $0.id == insertedGoal.id } == false)
    }

    @Test("A failed finish restores lifecycle state without reinserting persistent allocations")
    func finishGoalRestoresLifecycleWithoutReinsertingAllocationsWhenSaveFails() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Finish Goal")
        let asset = TestDataFactory.createSampleAsset(currency: "USD", goal: goal, amount: 40)
        context.insert(goal)
        context.insert(asset)
        try context.saveWithRelationships()
        let allocation = try #require(goal.allocations?.first)
        let notificationManager = SpyNotificationManager()

        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: notificationManager,
            saveChanges: { throw ForcedSaveError.failed }
        )

        await #expect(throws: ForcedSaveError.self) {
            try await service.finishGoal(goal)
        }

        context.processPendingChanges()
        let persistedAllocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        #expect(goal.lifecycleStatus == .active)
        #expect(persistedAllocations.map(\.id) == [allocation.id])
        #expect(goal.allocations?.map(\.id) == [allocation.id])
        #expect(asset.allocations?.map(\.id) == [allocation.id])
        #expect(allocation.goal?.id == goal.id)
        #expect(allocation.asset?.id == asset.id)
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
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

        try await service.cancelGoal(goal, at: timestamp)

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

    @Test("Cancel commits before notification suspension so concurrent finish cannot release a finished allocation")
    func cancelCommitsBeforeNotificationSuspension() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let notificationManager = SuspendingNotificationManager()
        let service = GoalLifecycleService(modelContext: context, notificationManager: notificationManager)
        let goal = makeGoal(name: "Concurrent Cancel")
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 40)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        try context.save()
        let finishPlan = try service.prepareFinishGoal(goal)

        let cancelTask = Task {
            try await service.cancelGoal(goal, at: Date(timeIntervalSince1970: 3_000))
        }
        await notificationManager.waitUntilCancellationStarts()

        #expect(goal.lifecycleStatus == .cancelled)
        await #expect(throws: GoalCompletionSettlementError.invalidGoalState(goal.id)) {
            try await service.finishGoal(
                goal,
                plan: finishPlan,
                decisions: [],
                at: Date(timeIntervalSince1970: 4_000)
            )
        }

        notificationManager.resumeCancellation()
        try await cancelTask.value

        #expect(goal.lifecycleStatus == .cancelled)
        #expect(goal.completionSnapshotData == nil)
        #expect((goal.allocations ?? []).isEmpty)
        #expect((asset.allocations ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<AssetAllocation>()) == 0)
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

        try await service.deleteGoal(goal, at: timestamp)

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

    @Test("Retiring a goal detaches its executing plan while preserving the remaining execution")
    func lifecycleRetirementDetachesExecutingPlan() async throws {
        for action in LifecycleAction.allCases {
            let container = try TestContainer.create()
            let context = ModelContext(container)
            let fixture = try makeExecutionFixture(
                in: context,
                includeRemainingGoal: true
            )
            let service = GoalLifecycleService(
                modelContext: context,
                notificationManager: SpyNotificationManager()
            )

            switch action {
            case .cancel:
                try await service.cancelGoal(fixture.targetGoal)
                #expect(fixture.targetGoal.lifecycleStatus == .cancelled)
            case .finish:
                try await service.finishGoal(fixture.targetGoal)
                #expect(fixture.targetGoal.lifecycleStatus == .finished)
            case .delete:
                try await service.deleteGoal(fixture.targetGoal)
                #expect(fixture.targetGoal.lifecycleStatus == .deleted)
            }

            context.processPendingChanges()
            #expect(fixture.targetPlan.state == .draft)
            #expect(fixture.targetPlan.executionRecord == nil)
            #expect(fixture.record.status == .executing)
            #expect(
                fixture.record.goalIds
                    == fixture.remainingGoal.map { [$0.id] } ?? []
            )
            #expect(
                fixture.record.plans?.map(\.id)
                    == fixture.remainingPlan.map { [$0.id] } ?? []
            )
            #expect(fixture.remainingPlan?.state == .executing)
            #expect(
                fixture.remainingPlan?.executionRecord?.id
                    == fixture.record.id
            )
        }
    }

    @Test("Retiring the final goal returns the execution record to a reusable draft")
    func finalGoalRetirementClosesOrphanedExecutionState() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeExecutionFixture(
            in: context,
            includeRemainingGoal: false
        )
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        )

        try await service.finishGoal(fixture.targetGoal)

        #expect(fixture.record.status == .draft)
        #expect(fixture.record.goalIds.isEmpty)
        #expect(fixture.record.startedAt == nil)
        #expect(fixture.record.canUndoUntil == nil)
        #expect(fixture.record.plans?.isEmpty == true)
        #expect(fixture.targetPlan.state == .draft)
        #expect(fixture.targetPlan.executionRecord == nil)
    }

    @Test("Restoring the final retired goal can restart the same draft record")
    func restoredFinalGoalCanRestartExecution() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeExecutionFixture(
            in: context,
            includeRemainingGoal: false
        )
        try await GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        ).finishGoal(fixture.targetGoal)
        try await GoalMutationService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            accessGuard: LifecycleAllowAllAccessGuard()
        ).resumeGoal(fixture.targetGoal)

        let restarted = try ExecutionTrackingService(
            modelContext: context
        ).startTracking(
            for: fixture.record.monthLabel,
            from: [fixture.targetPlan],
            goals: [fixture.targetGoal]
        )

        #expect(restarted.id == fixture.record.id)
        #expect(restarted.status == .executing)
        #expect(restarted.goalIds == [fixture.targetGoal.id])
        #expect(restarted.plans?.map(\.id) == [fixture.targetPlan.id])
        #expect(fixture.targetPlan.state == .executing)
        #expect(fixture.targetPlan.executionRecord?.id == restarted.id)
    }

    @Test("Failed retirement restores goal plan and execution membership atomically")
    func lifecycleRetirementFailureRestoresExecutionGraph() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeExecutionFixture(
            in: context,
            includeRemainingGoal: false
        )
        let originalStartedAt = fixture.record.startedAt
        let originalUndoDeadline = fixture.record.canUndoUntil
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            saveChanges: { throw ForcedSaveError.failed }
        )

        await #expect(throws: ForcedSaveError.self) {
            try await service.finishGoal(fixture.targetGoal)
        }

        context.processPendingChanges()
        #expect(fixture.targetGoal.lifecycleStatus == .active)
        #expect(fixture.targetPlan.state == .executing)
        #expect(fixture.targetPlan.executionRecord?.id == fixture.record.id)
        #expect(fixture.record.status == .executing)
        #expect(fixture.record.goalIds == [fixture.targetGoal.id])
        #expect(fixture.record.plans?.map(\.id) == [fixture.targetPlan.id])
        #expect(fixture.record.startedAt == originalStartedAt)
        #expect(fixture.record.canUndoUntil == originalUndoDeadline)
    }

    @Test("Restoring a retired goal keeps its plan draft for the next execution")
    func restoredGoalDoesNotRemainStrandedExecuting() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let fixture = try makeExecutionFixture(
            in: context,
            includeRemainingGoal: true
        )
        let accessGuard = LifecycleAllowAllAccessGuard()
        let lifecycleService = GoalLifecycleService(
            modelContext: context,
            notificationManager: SpyNotificationManager()
        )

        try await lifecycleService.cancelGoal(fixture.targetGoal)
        try await GoalMutationService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            accessGuard: accessGuard
        ).resumeGoal(fixture.targetGoal)

        #expect(fixture.targetGoal.lifecycleStatus == .active)
        #expect(fixture.targetPlan.state == .draft)
        #expect(fixture.targetPlan.executionRecord == nil)
        #expect(
            fixture.record.goalIds
                == fixture.remainingGoal.map { [$0.id] } ?? []
        )
    }

    private struct ExecutionFixture {
        let targetGoal: Goal
        let remainingGoal: Goal?
        let record: MonthlyExecutionRecord
        let targetPlan: MonthlyPlan
        let remainingPlan: MonthlyPlan?
    }

    private func makeExecutionFixture(
        in context: ModelContext,
        includeRemainingGoal: Bool
    ) throws -> ExecutionFixture {
        let targetGoal = makeGoal(name: "Executing target")
        let remainingGoal = includeRemainingGoal
            ? makeGoal(name: "Executing survivor")
            : nil
        let goals = [targetGoal] + [remainingGoal].compactMap { $0 }
        let plans = goals.map {
            MonthlyPlan(
                goalId: $0.id,
                monthLabel: "2026-07",
                requiredMonthly: 100,
                remainingAmount: 1_000,
                monthsRemaining: 10,
                currency: "USD",
                state: .executing
            )
        }
        let record = MonthlyExecutionRecord(
            monthLabel: "2026-07",
            goalIds: goals.map(\.id)
        )
        record.startTracking(
            at: Date(timeIntervalSince1970: 1_750_000_000)
        )
        record.plans = plans
        for plan in plans {
            plan.executionRecord = record
        }
        for goal in goals {
            context.insert(goal)
        }
        for plan in plans {
            context.insert(plan)
        }
        context.insert(record)
        try context.saveWithRelationships()

        return ExecutionFixture(
            targetGoal: targetGoal,
            remainingGoal: remainingGoal,
            record: record,
            targetPlan: plans[0],
            remainingPlan: plans.count > 1 ? plans[1] : nil
        )
    }

    private typealias OverAllocatedFixture = (
        targetGoal: Goal,
        remainingGoal: Goal,
        asset: Asset,
        targetAllocation: AssetAllocation,
        remainingAllocation: AssetAllocation
    )

    private func makeOverAllocatedFixture(in context: ModelContext) throws -> OverAllocatedFixture {
        let targetGoal = makeGoal(name: "Target Goal")
        let remainingGoal = makeGoal(name: "Remaining Goal")
        let asset = Asset(currency: "USD")
        let openingBalance = Transaction(amount: 100, asset: asset)

        asset.transactions = [openingBalance]

        context.insert(targetGoal)
        context.insert(remainingGoal)
        context.insert(asset)
        context.insert(openingBalance)
        try context.saveWithRelationships()

        try AllocationService(modelContext: context).updateAllocations(
            for: asset,
            newAllocations: [
                (goal: targetGoal, amount: 25),
                (goal: remainingGoal, amount: 75)
            ]
        )
        let targetAllocation = try #require(
            asset.allocations?.first { $0.goal?.id == targetGoal.id }
        )
        let remainingAllocation = try #require(
            asset.allocations?.first { $0.goal?.id == remainingGoal.id }
        )

        let withdrawal = Transaction(amount: -50, asset: asset)
        asset.transactions = (asset.transactions ?? []) + [withdrawal]
        context.insert(withdrawal)
        try context.saveWithRelationships()

        #expect(asset.currentAmount == 50)
        #expect(asset.isOverAllocated)
        return (targetGoal, remainingGoal, asset, targetAllocation, remainingAllocation)
    }

    private func assertOnlyRemainingAllocationPersists(
        _ fixture: OverAllocatedFixture,
        in context: ModelContext
    ) throws {
        context.processPendingChanges()
        let persistedAllocations = try context.fetch(FetchDescriptor<AssetAllocation>())

        #expect(!persistedAllocations.contains { $0.id == fixture.targetAllocation.id })
        #expect(persistedAllocations.contains { $0.id == fixture.remainingAllocation.id })
        #expect(fixture.asset.allocations?.map(\.id) == [fixture.remainingAllocation.id])
        #expect(fixture.targetGoal.allocations?.isEmpty == true)
        #expect(fixture.remainingGoal.allocations?.map(\.id) == [fixture.remainingAllocation.id])
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

        try await service.cancelGoal(goal, at: Date(timeIntervalSince1970: 5_000))

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
