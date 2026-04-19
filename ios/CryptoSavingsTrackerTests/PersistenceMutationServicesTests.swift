import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceMutationServicesTests {
    private final class NotificationCaptureBox: @unchecked Sendable {
        var userInfo: [AnyHashable: Any]?
    }

    private final class NotificationFlagBox: @unchecked Sendable {
        var wasPosted = false
    }

    @Test("GoalMutationService inserts and saves detached goal")
    func goalMutationServicePersistsDetachedGoal() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Cutover Goal")

        try await service.createGoal(goal)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1)
        #expect(goals.first?.name == "Cutover Goal")
        #expect(goal.modelContext != nil)
    }

    @Test("GoalMutationService clears reminder fields during create and save")
    func goalMutationServiceClearsReminderFields() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Reminder Cleanup Goal")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)

        try await service.createGoal(goal)

        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)

        goal.reminderFrequency = ReminderFrequency.monthly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(7200)

        try await service.saveGoal(goal)

        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("GoalMutationService clears reminder fields during restore")
    func goalMutationServiceClearsReminderFieldsOnRestore() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Archived Goal")
        goal.archive()
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.restoreGoal(goal)

        #expect(goal.isArchived == false)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("GoalMutationService clears reminder fields during archive")
    func goalMutationServiceClearsReminderFieldsOnArchive() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Archive Reminder Cleanup Goal")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.archiveGoal(goal)

        #expect(goal.isArchived == true)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("GoalMutationService clears reminder fields during resume")
    func goalMutationServiceClearsReminderFieldsOnResume() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Resume Reminder Cleanup Goal")
        goal.archive()
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.resumeGoal(goal)

        #expect(goal.isArchived == false)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("AssetMutationService creates asset with initial allocation history")
    func assetMutationServiceCreatesInitialAllocationHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = AssetMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Asset Goal")
        context.insert(goal)
        try context.save()

        let asset = try await service.createAsset(
            currency: "BTC",
            address: "0x1234567890123456789012345678901234567890",
            chainId: "ethereum-mainnet",
            goal: goal
        )

        let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect((asset.allocations ?? []).count == 1)
        #expect(allocations.count == 1)
        #expect(histories.count == 1)
        #expect(histories.first?.goalId == goal.id)
    }

    @Test("PlanningMutationService prepares plans for execution")
    func planningMutationServicePreparesPlansForExecution() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let draftGoal = TestDataFactory.createSampleGoal(name: "Draft Goal")
        let executedGoal = TestDataFactory.createSampleGoal(name: "Executed Goal")
        context.insert(draftGoal)
        context.insert(executedGoal)

        let zeroPlan = MonthlyPlan(
            goalId: draftGoal.id,
            monthLabel: "2026-03",
            requiredMonthly: 0,
            remainingAmount: 0,
            monthsRemaining: 1,
            currency: "USD",
            state: .draft
        )
        let executedPlan = MonthlyPlan(
            goalId: executedGoal.id,
            monthLabel: "2026-03",
            requiredMonthly: 150,
            remainingAmount: 500,
            monthsRemaining: 4,
            currency: "USD",
            state: .executing
        )
        context.insert(zeroPlan)
        context.insert(executedPlan)
        try context.save()

        try service.preparePlansForExecution([zeroPlan, executedPlan])

        #expect(zeroPlan.state == .draft)
        #expect(zeroPlan.isSkipped == true)
        #expect(executedPlan.state == .draft)
        #expect(executedPlan.isSkipped == false)
    }

    @Test("GoalMutationService rejects writes for shared goals")
    func goalMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Goal")
        let service = GoalMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        await #expect(throws: FamilyShareReadOnlyAccessError.self) {
            try await service.saveGoal(goal)
        }
    }

    @Test("AssetMutationService rejects asset creation for shared goals")
    func assetMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Asset Goal")
        context.insert(goal)
        try context.save()
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        await #expect(throws: FamilyShareReadOnlyAccessError.self) {
            _ = try await service.createAsset(
                currency: "BTC",
                address: "0x1234567890123456789012345678901234567890",
                chainId: "ethereum-mainnet",
                goal: goal
            )
        }
    }

    @Test("TransactionMutationService rejects writes for shared assets")
    func transactionMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Goal")
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(goal)
        context.insert(asset)
        try context.save()
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        #expect(throws: FamilyShareReadOnlyAccessError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 100,
                date: Date(),
                comment: "Blocked",
                autoAllocateGoalId: nil
            )
        }
    }

    @Test("TransactionMutationService posts retained goal updates without retired planning notifications")
    func transactionMutationServiceOmitsRetiredPlanningNotification() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "MVP Goal")
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(goal)
        context.insert(asset)
        try context.save()

        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let planningSignal = NotificationFlagBox()
        let sharedGoalSignal = NotificationCaptureBox()

        let planningToken = NotificationCenter.default.addObserver(
            forName: .monthlyPlanningAssetUpdated,
            object: nil,
            queue: nil
        ) { _ in
            planningSignal.wasPosted = true
        }

        let sharedGoalToken = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            sharedGoalSignal.userInfo = notification.userInfo
        }

        defer {
            NotificationCenter.default.removeObserver(planningToken)
            NotificationCenter.default.removeObserver(sharedGoalToken)
        }

        _ = try service.createTransaction(
            for: asset,
            amount: 125,
            date: Date(),
            comment: "MVP contribution",
            autoAllocateGoalId: nil
        )

        let affectedGoalIDs = sharedGoalSignal.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(planningSignal.wasPosted == false)
        #expect(sharedGoalSignal.userInfo?["reason"] as? String == "transactionMutation")
        #expect(affectedGoalIDs == [goal.id])
    }

    @Test("PlanningMutationService rejects updates for shared plans")
    func planningMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let goal = TestDataFactory.createSampleGoal(name: "Shared Planning Goal")
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-03",
            requiredMonthly: 150,
            remainingAmount: 500,
            monthsRemaining: 4,
            currency: "USD",
            state: .draft
        )
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        #expect(throws: FamilyShareReadOnlyAccessError.self) {
            try service.markPlanCompleted(plan)
        }
    }

    @Test("PlanningMutationService posts shared-goal change when feasibility updates goal semantics")
    func planningMutationServicePostsSharedGoalChangeForFeasibilityUpdates() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let goal = TestDataFactory.createSampleGoal(name: "Feasibility Goal")
        context.insert(goal)
        try context.save()

        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let capture = NotificationCaptureBox()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            capture.userInfo = notification.userInfo
        }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try service.applyFeasibilitySuggestion(
            .reduceTarget(goalId: goal.id, goalName: goal.name, to: 3500, currency: goal.currency),
            goals: [goal]
        )

        let affectedGoalIDs = capture.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(capture.userInfo?["reason"] as? String == "goalMutation")
        #expect(affectedGoalIDs == [goal.id])
    }

    @Test("OnboardingMutationService posts shared-goal change after template goal creation")
    func onboardingMutationServicePostsSharedGoalChange() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = OnboardingMutationService(modelContext: context)

        let capture = NotificationCaptureBox()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            capture.userInfo = notification.userInfo
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await service.createGoalFromTemplate(.allTemplates[0], userProfile: UserProfile())

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let affectedGoalIDs = capture.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(goals.count == 1)
        #expect(capture.userInfo?["reason"] as? String == "goalMutation")
        #expect(affectedGoalIDs == [goals[0].id])
        #expect(goals[0].reminderFrequency == nil)
        #expect(goals[0].reminderTime == nil)
        #expect(goals[0].firstReminderDate == nil)
    }
}

@MainActor
private final class AllowAllFamilyShareAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

@MainActor
private final class DenyingFamilyShareAccessGuard: FamilyShareAccessChecking {
    private let sharedGoalIDs: Set<UUID>

    init(sharedGoalIDs: Set<UUID>) {
        self.sharedGoalIDs = sharedGoalIDs
    }

    convenience init(sharedGoalIDs: [UUID]) {
        self.init(sharedGoalIDs: Set(sharedGoalIDs))
    }

    func isSharedGoalID(_ goalID: UUID) -> Bool {
        sharedGoalIDs.contains(goalID)
    }

    func assertOwnerWritable(goalID: UUID) throws {
        if isSharedGoalID(goalID) {
            throw FamilyShareReadOnlyAccessError.sharedGoalReadOnly
        }
    }

    func assertOwnerWritable(goal: Goal) throws {
        try assertOwnerWritable(goalID: goal.id)
    }

    func assertOwnerWritable(asset: Asset) throws {
        for allocation in asset.allocations ?? [] {
            if let goal = allocation.goal {
                try assertOwnerWritable(goal: goal)
                return
            }
        }
    }

    func assertOwnerWritable(transaction: Transaction) throws {
        if let asset = transaction.asset {
            try assertOwnerWritable(asset: asset)
        }
    }

    func assertOwnerWritable(plan: MonthlyPlan) throws {
        try assertOwnerWritable(goalID: plan.goalId)
    }

    func assertOwnerWritable(plans: [MonthlyPlan]) throws {
        for plan in plans {
            try assertOwnerWritable(plan: plan)
        }
    }

    func assertOwnerWritable(goals: [Goal]) throws {
        for goal in goals {
            try assertOwnerWritable(goal: goal)
        }
    }
}
