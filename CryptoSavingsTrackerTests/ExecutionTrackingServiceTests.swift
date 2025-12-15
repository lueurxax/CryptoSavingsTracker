//
//  ExecutionTrackingServiceTests.swift
//  CryptoSavingsTrackerTests
//
//  Minimal regression coverage for execution tracking.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ExecutionTrackingServiceTests {
    var modelContainer: ModelContainer
    var executionService: ExecutionTrackingService
    var contributionService: ContributionService

    init() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self,
            Asset.self,
            AssetAllocation.self,
            Transaction.self,
            AllocationHistory.self,
            MonthlyPlan.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            ExecutionSnapshot.self,
            Contribution.self,
            configurations: config
        )
        let context = modelContainer.mainContext
        self.executionService = ExecutionTrackingService(modelContext: context)
        self.contributionService = ContributionService(modelContext: context)
    }

    @Test("Reallocation moves contributions to second goal in execution")
    func testReallocationAddsSecondGoalContributions() async throws {
        let context = modelContainer.mainContext

        let goal1 = TestHelpers.createGoal(
            name: "Primary Goal",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        let goal2 = TestHelpers.createGoal(
            name: "Secondary Goal",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal1)
        context.insert(goal2)

        let asset = Asset(currency: "USD")
        context.insert(asset)

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let plan1 = MonthlyPlan(
            goalId: goal1.id,
            monthLabel: monthLabel,
            requiredMonthly: 200,
            remainingAmount: 5000,
            monthsRemaining: 6,
            currency: "USD"
        )
        let plan2 = MonthlyPlan(
            goalId: goal2.id,
            monthLabel: monthLabel,
            requiredMonthly: 150,
            remainingAmount: 3000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan1)
        context.insert(plan2)
        try context.save()

        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan1, plan2],
            goals: [goal1, goal2]
        )

        // Deposit to goal1
        let deposit = try contributionService.recordDeposit(
            amount: 100,
            assetAmount: 100,
            to: goal1,
            from: asset,
            exchangeRate: 1.0
        )
        try contributionService.linkToExecutionRecord(deposit, recordId: record.id)

        // Reallocate 40 from goal1 to goal2
        let reallocation = try contributionService.recordReallocation(
            fiatAmount: 40,
            assetAmount: 40,
            from: goal1,
            to: goal2,
            asset: asset,
            exchangeRate: 1.0
        )
        try contributionService.linkToExecutionRecord(reallocation.deposit, recordId: record.id)
        try contributionService.linkToExecutionRecord(reallocation.withdrawal, recordId: record.id)

        let totals = try executionService.getContributionTotals(for: record)
        #expect(totals[goal1.id] == 60, "Goal1 should retain net 60 after reallocating 40")
        #expect(totals[goal2.id] == 40, "Goal2 should gain 40 via reallocation")
        #expect(totals.keys.count == 2, "Both goals should appear in execution totals")
    }

    @Test("Start tracking does not duplicate AllocationHistory baseline")
    func testStartTrackingDoesNotDuplicateAllocationHistoryBaseline() async throws {
        let context = modelContainer.mainContext

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000, daysFromNow: 60)
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 50)
        asset.allocations.append(allocation)
        goal.allocations.append(allocation)

        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: monthLabel,
            requiredMonthly: 100,
            remainingAmount: 1000,
            monthsRemaining: 10,
            currency: "USD"
        )
        context.insert(plan)
        try context.save()

        _ = try executionService.startTracking(for: monthLabel, from: [plan], goals: [goal])
        try context.save()

        var histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 1)

        _ = try executionService.startTracking(for: monthLabel, from: [plan], goals: [goal])
        try context.save()

        histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 1)
    }
}
