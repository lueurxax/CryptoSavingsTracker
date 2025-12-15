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
    var contributionService: ContributionService

    init() async throws {
        // Create in-memory model container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self,
            Asset.self,
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

    // MARK: - End-to-End Flow Tests

    @Test("Complete execution flow: start → contribute → complete")
    func testCompleteExecutionFlow() async throws {
        // Given: Setup goals and plans
        let context = modelContainer.mainContext

        let goal1 = TestHelpers.createGoal(
            name: "Emergency Fund",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal1)

        let goal2 = TestHelpers.createGoal(
            name: "Vacation",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        context.insert(goal2)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan1 = MonthlyPlan(
            goalId: goal1.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan1)

        let plan2 = MonthlyPlan(
            goalId: goal2.id,
            requiredMonthly: 500,
            remainingAmount: 2000,
            monthsRemaining: 4,
            currency: "USD"
        )
        context.insert(plan2)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // When: Start tracking
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan1, plan2],
            goals: [goal1, goal2]
        )

        // Then: Verify record created
        #expect(record.status == .executing)
        #expect(record.snapshot != nil)
        #expect(record.snapshot?.goalCount == 2)
        #expect(record.snapshot?.totalPlanned == 1333.33)

        // When: Add contributions
        let contribution1 = try contributionService.recordDeposit(
            amount: 833.33,
            assetAmount: 0.01666,
            to: goal1,
            from: asset,
            exchangeRate: 50000
        )
        try contributionService.linkToExecutionRecord(contribution1, recordId: record.id)

        let contribution2 = try contributionService.recordDeposit(
            amount: 500,
            assetAmount: 0.01,
            to: goal2,
            from: asset,
            exchangeRate: 50000
        )
        try contributionService.linkToExecutionRecord(contribution2, recordId: record.id)

        // Then: Verify contributions tracked
        let contributions = try executionService.getContributions(for: record)
        #expect(contributions.count == 2)

        let totals = try executionService.getContributionTotals(for: record)
        #expect(totals[goal1.id] == 833.33)
        #expect(totals[goal2.id] == 500)

        let progress = try executionService.calculateProgress(for: record)
        #expect(progress == 100.0)

        // When: Complete month
        try executionService.markComplete(record)

        // Then: Verify completion
        #expect(record.status == .closed)
        #expect(record.completedAt != nil)
        #expect(record.canUndo == true)
    }

    @Test("Partial completion flow")
    func testPartialCompletion() async throws {
        // Given
        let context = modelContainer.mainContext

        let goal = TestHelpers.createGoal(
            name: "Savings Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 10, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 500,
            remainingAmount: 5000,
            monthsRemaining: 10,
            currency: "USD"
        )
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )

        // When: Contribute only 50%
        let contribution = try contributionService.recordDeposit(
            amount: 250,
            assetAmount: 0.005,
            to: goal,
            from: asset,
            exchangeRate: 50000
        )
        try contributionService.linkToExecutionRecord(contribution, recordId: record.id)

        // Then: Verify partial progress
        let progress = try executionService.calculateProgress(for: record)
        #expect(progress == 50.0)

        // When: Complete month anyway
        try executionService.markComplete(record)

        // Then: Record is closed but not 100%
        #expect(record.status == .closed)

        let finalProgress = try executionService.calculateProgress(for: record)
        #expect(finalProgress == 50.0)
    }

    @Test("Multiple goals fulfillment tracking")
    func testMultipleGoalsFulfillment() async throws {
        // Given
        let context = modelContainer.mainContext

        let goal1 = TestHelpers.createGoal(
            name: "Goal 1",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal1)

        let goal2 = TestHelpers.createGoal(
            name: "Goal 2",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 2000,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        context.insert(goal2)

        let goal3 = TestHelpers.createGoal(
            name: "Goal 3",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!
        )
        context.insert(goal3)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan1 = MonthlyPlan(goalId: goal1.id, requiredMonthly: 1000, remainingAmount: 5000, monthsRemaining: 5, currency: "USD")
        let plan2 = MonthlyPlan(goalId: goal2.id, requiredMonthly: 1000, remainingAmount: 3000, monthsRemaining: 3, currency: "USD")
        let plan3 = MonthlyPlan(goalId: goal3.id, requiredMonthly: 1000, remainingAmount: 2000, monthsRemaining: 2, currency: "USD")
        context.insert(plan1)
        context.insert(plan2)
        context.insert(plan3)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan1, plan2, plan3],
            goals: [goal1, goal2, goal3]
        )

        // When: Fully fund goal1, partially fund goal2, skip goal3
        let contribution1 = try contributionService.recordDeposit(amount: 1000, assetAmount: 0.02, to: goal1, from: asset, exchangeRate: 50000)
        try contributionService.linkToExecutionRecord(contribution1, recordId: record.id)

        let contribution2 = try contributionService.recordDeposit(amount: 500, assetAmount: 0.01, to: goal2, from: asset, exchangeRate: 50000)
        try contributionService.linkToExecutionRecord(contribution2, recordId: record.id)

        // Then: Check fulfillment status
        let totals = try executionService.getContributionTotals(for: record)
        #expect(totals[goal1.id] == 1000) // Fulfilled
        #expect(totals[goal2.id] == 500)  // Partial
        #expect(totals[goal3.id] == nil || totals[goal3.id] == 0) // Not funded

        let progress = try executionService.calculateProgress(for: record)
        #expect(progress == 50.0) // (1000 + 500) / 3000
    }

    @Test("Undo flow integration")
    func testUndoFlowIntegration() async throws {
        // Given
        let context = modelContainer.mainContext

        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(goalId: goal.id, requiredMonthly: 1000, remainingAmount: 5000, monthsRemaining: 5, currency: "USD")
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

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
        record.startTracking()
        #expect(record.status == .executing)

        // When: Add contribution and complete
        let contribution = try contributionService.recordDeposit(amount: 1000, assetAmount: 0.02, to: goal, from: asset, exchangeRate: 50000)
        try contributionService.linkToExecutionRecord(contribution, recordId: record.id)

        try executionService.markComplete(record)
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

        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(goalId: goal.id, requiredMonthly: 1000, remainingAmount: 5000, monthsRemaining: 5, currency: "USD")
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
