//
//  ExecutionTrackingServiceTests.swift
//  CryptoSavingsTrackerTests
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Tests for ExecutionTrackingService
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

struct ExecutionTrackingServiceTests {

    var modelContainer: ModelContainer
    var executionService: ExecutionTrackingService

    init() async throws {
        // Create in-memory model container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self,
            MonthlyPlan.self,
            MonthlyExecutionRecord.self,
            ExecutionSnapshot.self,
            Contribution.self,
            configurations: config
        )

        let context = modelContainer.mainContext
        self.executionService = ExecutionTrackingService(modelContext: context)
    }

    // MARK: - Record Creation Tests

    @Test("Create execution record from plans")
    func testCreateExecutionRecord() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // When
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )

        // Then
        #expect(record.monthLabel == monthLabel)
        #expect(record.status == .executing)
        #expect(record.snapshot != nil)
        #expect(record.snapshot?.goalCount == 1)
        #expect(record.snapshot?.totalPlanned == 833.33)
        #expect(record.startedAt != nil)
        #expect(record.canUndo == true)
    }

    @Test("Prevent duplicate execution records")
    func testPreventDuplicateRecords() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Create first record
        _ = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )

        // When/Then - Attempting to create duplicate should throw
        do {
            _ = try executionService.startTracking(
                for: monthLabel,
                from: [plan],
                goals: [goal]
            )
            Issue.record("Should have thrown recordAlreadyExists error")
        } catch ExecutionTrackingService.ExecutionError.recordAlreadyExists {
            // Expected
        }
    }

    // MARK: - Lifecycle Tests

    @Test("Complete execution record")
    func testCompleteRecord() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
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

        // When
        try executionService.markComplete(record)

        // Then
        #expect(record.status == .closed)
        #expect(record.completedAt != nil)
        #expect(record.canUndo == true)
    }

    @Test("Undo completion within grace period")
    func testUndoCompletion() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
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

        try executionService.markComplete(record)

        // When
        try executionService.undoCompletion(record)

        // Then
        #expect(record.status == .executing)
        #expect(record.completedAt == nil)
        #expect(record.canUndoUntil == nil)
    }

    @Test("Undo start tracking within grace period")
    func testUndoStartTracking() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
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

        // When
        try executionService.undoStartTracking(record)

        // Then
        #expect(record.status == .draft)
        #expect(record.startedAt == nil)
        #expect(record.canUndoUntil == nil)
    }

    // MARK: - Contribution Tracking Tests

    @Test("Link contribution to execution record")
    func testLinkContribution() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
            currency: "USD"
        )
        context.insert(plan)

        let contribution = Contribution(
            amount: 500,
            goal: goal,
            asset: asset,
            source: .manualDeposit
        )
        context.insert(contribution)
        try context.save()

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let record = try executionService.startTracking(
            for: monthLabel,
            from: [plan],
            goals: [goal]
        )

        // When
        try executionService.linkContribution(contribution, to: record)

        // Then
        #expect(contribution.executionRecordId == record.id)
        #expect(contribution.isPlanned == true)
    }

    @Test("Get contributions for execution record")
    func testGetContributions() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
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

        // Create contributions
        let contribution1 = Contribution(
            amount: 300,
            goal: goal,
            asset: asset,
            source: .manualDeposit
        )
        contribution1.executionRecordId = record.id
        context.insert(contribution1)

        let contribution2 = Contribution(
            amount: 200,
            goal: goal,
            asset: asset,
            source: .manualDeposit
        )
        contribution2.executionRecordId = record.id
        context.insert(contribution2)
        try context.save()

        // When
        let contributions = try executionService.getContributions(for: record)

        // Then
        #expect(contributions.count == 2)
        #expect(contributions.contains { $0.id == contribution1.id })
        #expect(contributions.contains { $0.id == contribution2.id })
    }

    @Test("Calculate contribution totals per goal")
    func testGetContributionTotals() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 833.33,
            remainingAmount: 5000,
            monthsRemaining: 6,
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

        // Create contributions
        let contribution1 = Contribution(amount: 300, goal: goal, asset: asset, source: .manualDeposit)
        contribution1.executionRecordId = record.id
        context.insert(contribution1)

        let contribution2 = Contribution(amount: 250, goal: goal, asset: asset, source: .manualDeposit)
        contribution2.executionRecordId = record.id
        context.insert(contribution2)
        try context.save()

        // When
        let totals = try executionService.getContributionTotals(for: record)

        // Then
        #expect(totals[goal.id] == 550)
    }

    @Test("Calculate overall progress")
    func testCalculateProgress() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let plan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 1000,
            remainingAmount: 5000,
            monthsRemaining: 5,
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

        // Create contribution (50% of planned)
        let contribution = Contribution(amount: 500, goal: goal, asset: asset, source: .manualDeposit)
        contribution.executionRecordId = record.id
        context.insert(contribution)
        try context.save()

        // When
        let progress = try executionService.calculateProgress(for: record)

        // Then
        #expect(progress == 50.0)
    }
}
