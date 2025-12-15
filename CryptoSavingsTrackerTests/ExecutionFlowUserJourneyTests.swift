//
//  ExecutionFlowUserJourneyTests.swift
//  CryptoSavingsTrackerTests
//
//  High-level integration that mirrors the real user journey:
//  - two goals with a shared asset
//  - planning -> start execution
//  - deposit to goal A, reallocate to goal B
//  - verify execution totals and snapshot are in sync (no phantom data).
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ExecutionFlowUserJourneyTests {
    var modelContainer: ModelContainer
    var planService: MonthlyPlanService
    var executionService: ExecutionTrackingService
    var contributionService: ContributionService

    init() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self,
            Asset.self,
            AssetAllocation.self,
            Transaction.self,
            MonthlyPlan.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            ExecutionSnapshot.self,
            Contribution.self,
            configurations: config
        )
        let context = modelContainer.mainContext
        let goalCalc = GoalCalculationService(container: DIContainer.shared, modelContext: context)
        self.planService = MonthlyPlanService(modelContext: context, goalCalculationService: goalCalc)
        self.executionService = ExecutionTrackingService(modelContext: context)
        self.contributionService = ContributionService(modelContext: context)
    }

    @Test("User journey: deposit + reallocate updates execution totals and snapshot")
    func testDepositAndReallocateFlow() async throws {
        let context = modelContainer.mainContext
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // Goals
        let goalA = TestHelpers.createGoal(
            name: "Goal A",
            currency: "USD",
            targetAmount: 4000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        let goalB = TestHelpers.createGoal(
            name: "Goal B",
            currency: "USD",
            targetAmount: 3000,
            currentTotal: 0,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goalA)
        context.insert(goalB)

        // Shared asset with an initial transaction to simulate balance
        let sharedAsset = Asset(currency: "USD")
        let seedTx = Transaction(amount: 200, asset: sharedAsset)
        sharedAsset.transactions.append(seedTx)
        context.insert(sharedAsset)

        // Create plans via service to mirror production flow
        let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: [goalA, goalB])
        #expect(plans.count == 2)

        // Start execution (purges stale month contributions and refreshes snapshot)
        let record = try executionService.startTracking(for: monthLabel, from: plans, goals: [goalA, goalB])
        #expect(record.status == .executing)

        // Deposit to Goal A
        let deposit = try contributionService.recordDeposit(
            amount: 120,
            assetAmount: 120,
            to: goalA,
            from: sharedAsset,
            exchangeRate: 1.0
        )
        try contributionService.linkToExecutionRecord(deposit, recordId: record.id)

        // Reallocate 40 from Goal A to Goal B
        let reallocation = try contributionService.recordReallocation(
            fiatAmount: 40,
            assetAmount: 40,
            from: goalA,
            to: goalB,
            asset: sharedAsset,
            exchangeRate: 1.0
        )
        try contributionService.linkToExecutionRecord(reallocation.withdrawal, recordId: record.id)
        try contributionService.linkToExecutionRecord(reallocation.deposit, recordId: record.id)

        // Totals should reflect net A = 80, B = 40
        let totals = try executionService.getContributionTotals(for: record)
        #expect(totals[goalA.id] == 80)
        #expect(totals[goalB.id] == 40)

        // Snapshot should still have planned amounts (not stale)
        guard let snapshot = record.snapshot else {
            Issue.record("Snapshot missing after startTracking")
            return
        }
        let goalsSnap = snapshot.goalSnapshots
        #expect(goalsSnap.count == 2)

        // Progress should be computed against effective amounts (plans)
        let progress = try executionService.calculateProgress(for: record)
        #expect(progress > 0)

    }
}
