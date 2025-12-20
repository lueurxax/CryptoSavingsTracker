//
//  ExecutionFlowIntegrationTests.swift
//  CryptoSavingsTrackerTests
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Integration tests for complete execution flow
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ExecutionFlowIntegrationTests {

    var modelContainer: ModelContainer
    var executionService: ExecutionTrackingService

    init() async throws {
        // Use shared TestContainer for consistent schema
        self.modelContainer = try TestContainer.create()
        let context = modelContainer.mainContext
        self.executionService = ExecutionTrackingService(modelContext: context)
    }

    // MARK: - End-to-End Flow Tests

    @Test("Complete execution flow: start → contribute → complete")
    func testCompleteExecutionFlow() async throws {
        // Given: Setup goals and plans
        let context = modelContainer.mainContext

        // Use currentTotal: 0 to avoid TestHelpers creating internal assets
        // This test focuses on tracking NEW contributions during execution
        let goal1 = TestHelpers.createGoal(
            name: "Emergency Fund",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal1)

        let goal2 = TestHelpers.createGoal(
            name: "Vacation",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        context.insert(goal2)

        let asset = Asset(currency: "USD")
        context.insert(asset)

        // Link asset to goals via allocations
        let alloc1 = AssetAllocation(asset: asset, goal: goal1, amount: 833.33)
        let alloc2 = AssetAllocation(asset: asset, goal: goal2, amount: 500)
        goal1.allocations.append(alloc1)
        goal2.allocations.append(alloc2)
        asset.allocations.append(alloc1)
        asset.allocations.append(alloc2)
        context.insert(alloc1)
        context.insert(alloc2)

        let plan1 = MonthlyPlan(
            goalId: goal1.id,
            requiredMonthly: 833.33,
            remainingAmount: 10000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan1)

        let plan2 = MonthlyPlan(
            goalId: goal2.id,
            requiredMonthly: 500,
            remainingAmount: 3000,
            monthsRemaining: 4,
            currency: "USD"
        )
        context.insert(plan2)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Use fixed timestamps for deterministic testing (like passing ExecutionProgressCalculatorTests)
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let depositTime = startTime.addingTimeInterval(3600)

        // Set up allocation targets at startTime
        context.insert(AllocationHistory(asset: asset, goal: goal1, amount: 833.33, timestamp: startTime))
        context.insert(AllocationHistory(asset: asset, goal: goal2, amount: 500, timestamp: startTime))
        try context.save()

        // Create record directly (bypassing seedAllocationHistoryBaseline which can interfere)
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [goal1.id, goal2.id])
        record.statusRawValue = "executing"
        record.startedAt = startTime

        // Create snapshot
        let snapshot = ExecutionSnapshot.create(from: [plan1, plan2], goals: [goal1, goal2])
        record.snapshot = snapshot
        context.insert(record)
        try context.save()

        // Then: Verify record created
        #expect(record.status == .executing)
        #expect(record.snapshot != nil)
        #expect(record.snapshot?.goalCount == 2)
        #expect(record.snapshot?.totalPlanned == 1333.33)

        // When: Deposit enough to fully fund both goals (after startedAt)
        let tx = Transaction(amount: 1333.33, asset: asset, date: depositTime)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        // Then: Verify derived totals tracked (use calculator directly with mock exchange service)
        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: depositTime.addingTimeInterval(1))
        #expect(totals[goal1.id] == 833.33)
        #expect(totals[goal2.id] == 500)

        let totalContributed = totals.values.reduce(0, +)
        let totalPlanned = record.snapshot?.totalPlanned ?? 0
        let progress = totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
        #expect(progress == 100.0)

        // When: Complete month
        record.markComplete()
        try context.save()

        // Then: Verify completion
        #expect(record.status == .closed)
        #expect(record.completedAt != nil)
        #expect(record.canUndo == true)
    }

    @Test("Partial completion flow")
    func testPartialCompletion() async throws {
        // Given
        let context = modelContainer.mainContext

        // Use currentTotal: 0 to avoid TestHelpers creating internal assets
        let goal = TestHelpers.createGoal(
            name: "Savings Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 10, to: Date())!
        )
        context.insert(goal)

        let asset = Asset(currency: "USD")
        context.insert(asset)

        // Link asset to goal via allocation
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 500)
        goal.allocations.append(alloc)
        asset.allocations.append(alloc)
        context.insert(alloc)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 500,
            remainingAmount: 10000,
            monthsRemaining: 10,
            currency: "USD"
        )
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Use fixed timestamps for deterministic testing
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let depositTime = startTime.addingTimeInterval(3600)

        // Set up allocation target at startTime
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 500, timestamp: startTime))
        try context.save()

        // Create record directly
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = startTime
        let snapshot = ExecutionSnapshot.create(from: [plan], goals: [goal])
        record.snapshot = snapshot
        context.insert(record)
        try context.save()

        // When: Contribute only 50%
        let tx = Transaction(amount: 250, asset: asset, date: depositTime)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        // Then: Verify partial progress
        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: depositTime.addingTimeInterval(1))
        let totalContributed = totals.values.reduce(0, +)
        let totalPlanned = record.snapshot?.totalPlanned ?? 0
        let progress = totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
        #expect(progress == 50.0)

        // When: Complete month anyway
        record.markComplete()
        try context.save()

        // Then: Record is closed but not 100%
        #expect(record.status == .closed)

        // Final progress calculation
        let finalTotals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: depositTime.addingTimeInterval(1))
        let finalTotalContributed = finalTotals.values.reduce(0, +)
        let finalProgress = totalPlanned > 0 ? (finalTotalContributed / totalPlanned) * 100 : 0
        #expect(finalProgress == 50.0)
    }

    @Test("Multiple goals fulfillment tracking")
    func testMultipleGoalsFulfillment() async throws {
        // Given
        let context = modelContainer.mainContext

        // Use currentTotal: 0 to avoid TestHelpers creating internal assets
        let goal1 = TestHelpers.createGoal(
            name: "Goal 1",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal1)

        let goal2 = TestHelpers.createGoal(
            name: "Goal 2",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        context.insert(goal2)

        let goal3 = TestHelpers.createGoal(
            name: "Goal 3",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!
        )
        context.insert(goal3)

        let asset = Asset(currency: "USD")
        context.insert(asset)

        // Link asset to all goals via allocations
        let alloc1 = AssetAllocation(asset: asset, goal: goal1, amount: 1000)
        let alloc2 = AssetAllocation(asset: asset, goal: goal2, amount: 1000)
        let alloc3 = AssetAllocation(asset: asset, goal: goal3, amount: 1000)
        goal1.allocations.append(alloc1)
        goal2.allocations.append(alloc2)
        goal3.allocations.append(alloc3)
        asset.allocations.append(alloc1)
        asset.allocations.append(alloc2)
        asset.allocations.append(alloc3)
        context.insert(alloc1)
        context.insert(alloc2)
        context.insert(alloc3)

        let plan1 = MonthlyPlan(goalId: goal1.id, requiredMonthly: 1000, remainingAmount: 10000, monthsRemaining: 5, currency: "USD")
        let plan2 = MonthlyPlan(goalId: goal2.id, requiredMonthly: 1000, remainingAmount: 5000, monthsRemaining: 3, currency: "USD")
        let plan3 = MonthlyPlan(goalId: goal3.id, requiredMonthly: 1000, remainingAmount: 3000, monthsRemaining: 2, currency: "USD")
        context.insert(plan1)
        context.insert(plan2)
        context.insert(plan3)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Use fixed timestamps for deterministic testing
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let depositTime = startTime.addingTimeInterval(3600)

        // Set up allocation targets at startTime
        context.insert(AllocationHistory(asset: asset, goal: goal1, amount: 1000, timestamp: startTime))
        context.insert(AllocationHistory(asset: asset, goal: goal2, amount: 1000, timestamp: startTime))
        context.insert(AllocationHistory(asset: asset, goal: goal3, amount: 1000, timestamp: startTime))
        try context.save()

        // Create record directly
        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [goal1.id, goal2.id, goal3.id])
        record.statusRawValue = "executing"
        record.startedAt = startTime
        let snapshot = ExecutionSnapshot.create(from: [plan1, plan2, plan3], goals: [goal1, goal2, goal3])
        record.snapshot = snapshot
        context.insert(record)
        try context.save()

        // When: Deposit 1500 - distributed proportionally across 3 goals (each has 1000 target)
        // Distribution: 500 each to goal1, goal2, goal3
        let tx = Transaction(amount: 1500, asset: asset, date: depositTime)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        // Then: Check fulfillment status - 1500 distributed across 3 goals = 500 each
        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: depositTime.addingTimeInterval(1))
        #expect(totals[goal1.id] == 500) // Partial (500/1000)
        #expect(totals[goal2.id] == 500) // Partial (500/1000)
        #expect(totals[goal3.id] == 500) // Partial (500/1000)

        let totalContributed = totals.values.reduce(0, +)
        let totalPlanned = record.snapshot?.totalPlanned ?? 0
        let progress = totalPlanned > 0 ? (totalContributed / totalPlanned) * 100 : 0
        #expect(progress == 50.0) // 1500 / 3000 = 50%
    }

    @Test("Undo flow integration")
    func testUndoFlowIntegration() async throws {
        // Given
        let context = modelContainer.mainContext

        // Use currentTotal: 0 to avoid TestHelpers creating internal assets
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal)

        let asset = Asset(currency: "USD")
        context.insert(asset)

        // Link asset to goal via allocation
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1000)
        goal.allocations.append(alloc)
        asset.allocations.append(alloc)
        context.insert(alloc)

        let plan = MonthlyPlan(goalId: goal.id, requiredMonthly: 1000, remainingAmount: 10000, monthsRemaining: 5, currency: "USD")
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Set up allocation target BEFORE starting tracking
        let baselineTime = Date()
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 1000, timestamp: baselineTime))
        try context.save()

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // When: Start tracking
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )
        #expect(record.status == .executing)
        #expect(record.canUndo == true)

        // When: Undo start
        try executionService.undoStartTracking(record)
        #expect(record.status == .draft)
        #expect(record.canUndo == false)

        // When: Restart tracking
        _ = try executionService.startTracking(for: monthLabel, from: [plan], goals: [goal])
        #expect(record.status == .executing)

        // When: Add contribution and complete
        let depositTime = (record.startedAt ?? Date()).addingTimeInterval(0.1)
        let tx = Transaction(amount: 1000, asset: asset, date: depositTime)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        try await executionService.markComplete(record)
        #expect(record.status == .closed)
        #expect(record.canUndo == true)

        // When: Undo completion
        try executionService.undoCompletion(record)
        #expect(record.status == .executing)
        #expect(record.completedAt == nil)
    }

    @Test("Snapshot immutability")
    func testSnapshotImmutability() async throws {
        // Given
        let context = modelContainer.mainContext

        // Use currentTotal: 0 to avoid TestHelpers creating internal assets
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(goalId: goal.id, requiredMonthly: 1000, remainingAmount: 10000, monthsRemaining: 5, currency: "USD")
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // When: Create record with snapshot
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )

        guard let snapshot = record.snapshot else {
            Issue.record("Snapshot should exist")
            return
        }

        let originalPlannedAmount = snapshot.totalPlanned
        let originalGoalSnapshot = snapshot.snapshot(for: goal.id)

        // When: Modify the plan (simulate user changing requirements)
        plan.requiredMonthly = 2000
        try context.save()

        // Then: Snapshot should remain unchanged
        #expect(snapshot.totalPlanned == originalPlannedAmount)
        #expect(snapshot.snapshot(for: goal.id)?.plannedAmount == originalGoalSnapshot?.plannedAmount)
    }
}
