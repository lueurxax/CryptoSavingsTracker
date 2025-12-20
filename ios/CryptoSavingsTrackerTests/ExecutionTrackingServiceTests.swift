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

    init() async throws {
        // Use shared TestContainer for consistent schema
        self.modelContainer = try TestContainer.create()
        let context = modelContainer.mainContext
        self.executionService = ExecutionTrackingService(modelContext: context)
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

        // Link asset to goals via allocations (required for ExecutionProgressCalculator)
        let alloc1 = AssetAllocation(asset: asset, goal: goal1, amount: 100)
        let alloc2 = AssetAllocation(asset: asset, goal: goal2, amount: 0)
        goal1.allocations.append(alloc1)
        goal2.allocations.append(alloc2)
        asset.allocations.append(alloc1)
        asset.allocations.append(alloc2)
        context.insert(alloc1)
        context.insert(alloc2)

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

        // Use fixed timestamps for deterministic testing
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let depositTime = startTime.addingTimeInterval(3600)
        let reallocateTime = depositTime.addingTimeInterval(1800)

        // Set up baseline allocation at startTime - initially only goal1 has target of 100
        context.insert(AllocationHistory(asset: asset, goal: goal1, amount: 100, timestamp: startTime))
        try context.save()

        // Create record directly (bypassing seedAllocationHistoryBaseline)
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [goal1.id, goal2.id])
        record.statusRawValue = "executing"
        record.startedAt = startTime
        context.insert(record)
        try context.save()

        // Deposit 100 USD after tracking started (goes to goal1 since it has the target)
        let tx = Transaction(amount: 100, asset: asset, date: depositTime)
        asset.transactions.append(tx)
        context.insert(tx)

        // Reallocate 40 from goal1 to goal2 by changing targets
        context.insert(AllocationHistory(asset: asset, goal: goal1, amount: 60, timestamp: reallocateTime))
        context.insert(AllocationHistory(asset: asset, goal: goal2, amount: 40, timestamp: reallocateTime))
        try context.save()

        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: reallocateTime.addingTimeInterval(1))
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
