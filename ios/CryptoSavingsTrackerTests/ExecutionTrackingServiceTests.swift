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
        goal1.allocations = (goal1.allocations ?? []) + [alloc1]
        goal2.allocations = (goal2.allocations ?? []) + [alloc2]
        asset.allocations = (asset.allocations ?? []) + [alloc1]
        asset.allocations = (asset.allocations ?? []) + [alloc2]
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
        asset.transactions = (asset.transactions ?? []) + [tx]
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
        asset.allocations = (asset.allocations ?? []) + [allocation]
        goal.allocations = (goal.allocations ?? []) + [allocation]

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

    @Test("Undo completion keeps immutable completion history")
    func testUndoCompletionKeepsCompletionEvent() async throws {
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoal(
            name: "History Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 100)
        goal.allocations = (goal.allocations ?? []) + [allocation]
        asset.allocations = (asset.allocations ?? []) + [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)

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

        let record = try executionService.startTracking(for: monthLabel, from: [plan], goals: [goal])
        let tx = Transaction(amount: 50, asset: asset, date: Date().addingTimeInterval(1))
        asset.transactions = (asset.transactions ?? []) + [tx]
        context.insert(tx)
        try context.save()

        try await executionService.markComplete(record)
        #expect((record.completionEvents ?? []).count == 1)
        let firstEventId = (record.completionEvents ?? []).first?.eventId
        #expect((record.completionEvents ?? []).first?.undoneAt == nil)

        try executionService.undoCompletion(record)

        #expect(record.status == .executing)
        #expect((record.completionEvents ?? []).count == 1)
        #expect((record.completionEvents ?? []).first?.eventId == firstEventId)
        #expect((record.completionEvents ?? []).first?.undoneAt != nil)
        #expect((record.completionEvents ?? []).first?.completionSnapshot != nil)
    }

    @Test("Backfill completion events is idempotent for legacy closed records")
    func testBackfillCompletionEventsIdempotent() throws {
        let context = modelContainer.mainContext
        let monthLabel = "2026-01"
        let completedAt = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z

        let record = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [])
        record.statusRawValue = "closed"
        record.completedAt = completedAt

        let snapshot = CompletedExecution(
            monthLabel: monthLabel,
            completedAt: completedAt,
            exchangeRatesSnapshot: ["USD->USD": 1],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        record.completedExecution = snapshot

        context.insert(record)
        context.insert(snapshot)
        try context.save()

        #expect((record.completionEvents ?? []).isEmpty)

        let firstInsertCount = try executionService.backfillCompletionEventsIfNeeded()
        let secondInsertCount = try executionService.backfillCompletionEventsIfNeeded()

        #expect(firstInsertCount == 1)
        #expect(secondInsertCount == 0)

        let events = try executionService.getCompletionEvents(limit: 50)
            .filter { $0.executionRecordId == record.id }
        #expect(events.count == 1)

        guard let event = events.first else {
            Issue.record("Expected one completion event after backfill")
            return
        }

        #expect(event.sequence == 1)
        #expect(event.sourceDiscriminator == snapshot.id.uuidString)
        #expect(event.completionSnapshot?.id == snapshot.id)
    }

    @Test("Completion events are returned in deterministic month and sequence order")
    func testCompletionEventsDeterministicOrder() throws {
        let context = modelContainer.mainContext

        let janRecord = MonthlyExecutionRecord(monthLabel: "2026-01", goalIds: [])
        janRecord.statusRawValue = "closed"
        let febRecord = MonthlyExecutionRecord(monthLabel: "2026-02", goalIds: [])
        febRecord.statusRawValue = "closed"

        let janSnapshot1 = CompletedExecution(
            monthLabel: "2026-01",
            completedAt: Date(timeIntervalSince1970: 1_704_067_200),
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        let janSnapshot2 = CompletedExecution(
            monthLabel: "2026-01",
            completedAt: Date(timeIntervalSince1970: 1_704_153_600),
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        let febSnapshot = CompletedExecution(
            monthLabel: "2026-02",
            completedAt: Date(timeIntervalSince1970: 1_706_745_600),
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: []
        )

        let janEvent1 = CompletionEvent(
            executionRecord: janRecord,
            sequence: 1,
            sourceDiscriminator: janSnapshot1.id.uuidString,
            completedAt: janSnapshot1.completedAt,
            completionSnapshot: janSnapshot1
        )
        let janEvent2 = CompletionEvent(
            executionRecord: janRecord,
            sequence: 2,
            sourceDiscriminator: janSnapshot2.id.uuidString,
            completedAt: janSnapshot2.completedAt,
            completionSnapshot: janSnapshot2
        )
        let febEvent = CompletionEvent(
            executionRecord: febRecord,
            sequence: 1,
            sourceDiscriminator: febSnapshot.id.uuidString,
            completedAt: febSnapshot.completedAt,
            completionSnapshot: febSnapshot
        )

        context.insert(janRecord)
        context.insert(febRecord)
        context.insert(janSnapshot1)
        context.insert(janSnapshot2)
        context.insert(febSnapshot)
        context.insert(janEvent1)
        context.insert(janEvent2)
        context.insert(febEvent)
        try context.save()

        let events = try executionService.getCompletionEvents(limit: 20)
        let labelsAndSequence = events.map { ($0.monthLabel, $0.sequence) }
        #expect(labelsAndSequence.prefix(3).map { "\($0.0)#\($0.1)" } == ["2026-02#1", "2026-01#2", "2026-01#1"])

        let grouped = Dictionary(grouping: events, by: { $0.monthLabel })
        #expect(grouped["2026-01"]?.count == 2)
        #expect(grouped["2026-02"]?.count == 1)
    }

    @Test("Resolver returns closed state while undo window is active")
    func testResolverClosedStateWithUndoWindow() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-02",
                    status: .closed,
                    completedAt: now.addingTimeInterval(-3600),
                    startedAt: now.addingTimeInterval(-7200),
                    canUndoUntil: now.addingTimeInterval(3600)
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .closed(month: "2026-02", canUndoCompletion: true))
    }

    @Test("Resolver returns planning for current month after closed undo window expires")
    func testResolverReturnsPlanningAfterClosedWindowExpires() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-02",
                    status: .closed,
                    completedAt: now.addingTimeInterval(-3 * 24 * 3600),
                    startedAt: now.addingTimeInterval(-4 * 24 * 3600),
                    canUndoUntil: now.addingTimeInterval(-1)
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .planning(month: "2026-03", source: .nextMonthAfterClosed))
    }

    @Test("Resolver returns executing for active month")
    func testResolverReturnsExecutingForActiveMonth() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-03",
                    status: .executing,
                    completedAt: nil,
                    startedAt: now.addingTimeInterval(-300),
                    canUndoUntil: now.addingTimeInterval(300)
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .executing(month: "2026-03", canFinish: true, canUndoStart: true))
    }

    @Test("Resolver returns conflict for malformed month labels")
    func testResolverReturnsConflictForMalformedMonthLabels() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "bad-label",
                    status: .executing,
                    completedAt: nil,
                    startedAt: now.addingTimeInterval(-60),
                    canUndoUntil: now.addingTimeInterval(60)
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .conflict(month: nil, reason: .invalidMonthLabel))
    }

    @Test("Resolver returns conflict for duplicate active executing records")
    func testResolverReturnsConflictForDuplicateExecutingRecords() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-03",
                    status: .executing,
                    completedAt: nil,
                    startedAt: now.addingTimeInterval(-180),
                    canUndoUntil: now.addingTimeInterval(180)
                ),
                ExecutionRecordSnapshot(
                    monthLabel: "2026-03",
                    status: .executing,
                    completedAt: nil,
                    startedAt: now.addingTimeInterval(-120),
                    canUndoUntil: now.addingTimeInterval(120)
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .conflict(month: "2026-03", reason: .duplicateActiveRecords))
    }

    @Test("Resolver future boundary accepts current plus one month")
    func testResolverFutureBoundaryCurrentPlusOneIsValid() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-04",
                    status: .draft,
                    completedAt: nil,
                    startedAt: nil,
                    canUndoUntil: nil
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .planning(month: "2026-03", source: .currentMonth))
    }

    @Test("Resolver future boundary rejects current plus two months")
    func testResolverFutureBoundaryCurrentPlusTwoIsConflict() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()
        let input = ResolverInput(
            nowUtc: now,
            displayTimeZone: .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [
                ExecutionRecordSnapshot(
                    monthLabel: "2026-05",
                    status: .draft,
                    completedAt: nil,
                    startedAt: nil,
                    canUndoUntil: nil
                )
            ],
            undoWindowSeconds: 24 * 3600
        )

        let state = resolver.resolve(input)
        #expect(state == .conflict(month: "2026-05", reason: .futureRecord))
    }

    @Test("Resolver keeps storage month deterministic for UTC display edges")
    func testResolverMonthBoundaryTimeZonesRemainDeterministic() {
        let resolver = MonthlyCycleStateResolver()
        let now = Date()

        let utcMinusTwelve = ResolverInput(
            nowUtc: now,
            displayTimeZone: TimeZone(secondsFromGMT: -12 * 3600) ?? .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [],
            undoWindowSeconds: 24 * 3600
        )
        let utcPlusFourteen = ResolverInput(
            nowUtc: now,
            displayTimeZone: TimeZone(secondsFromGMT: 14 * 3600) ?? .current,
            currentStorageMonthLabelUtc: "2026-03",
            records: [],
            undoWindowSeconds: 24 * 3600
        )

        let minusState = resolver.resolve(utcMinusTwelve)
        let plusState = resolver.resolve(utcPlusFourteen)

        #expect(minusState == .planning(month: "2026-03", source: .currentMonth))
        #expect(plusState == .planning(month: "2026-03", source: .currentMonth))
    }
}
