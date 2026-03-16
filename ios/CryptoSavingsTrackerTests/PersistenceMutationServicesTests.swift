import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceMutationServicesTests {

    @Test("GoalMutationService inserts and saves detached goal")
    func goalMutationServicePersistsDetachedGoal() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context)
        let goal = TestDataFactory.createSampleGoal(name: "Cutover Goal")

        try await service.createGoal(goal)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1)
        #expect(goals.first?.name == "Cutover Goal")
        #expect(goal.modelContext != nil)
    }

    @Test("AssetMutationService creates asset with initial allocation history")
    func assetMutationServiceCreatesInitialAllocationHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = AssetMutationService(modelContext: context)
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
        #expect(asset.allocations.count == 1)
        #expect(allocations.count == 1)
        #expect(histories.count == 1)
        #expect(histories.first?.goalId == goal.id)
    }

    @Test("PlanningMutationService prepares plans for execution")
    func planningMutationServicePreparesPlansForExecution() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let service = PlanningMutationService(modelContext: context, exchangeRateService: exchangeRates)

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
}
