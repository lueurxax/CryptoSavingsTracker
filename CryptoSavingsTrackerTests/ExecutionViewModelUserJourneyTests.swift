//
//  ExecutionViewModelUserJourneyTests.swift
//  CryptoSavingsTrackerTests
//
//  Integration using the real view models/services:
//  - seed two goals and a shared asset
//  - create plans via MonthlyPlanService (goal calc with mock FX)
//  - start execution via MonthlyExecutionViewModel
//  - deposit to goal A, reallocate to goal B
//  - reload execution VM and assert totals reflect contributions (no phantom zeros)
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ExecutionViewModelUserJourneyTests {
    var modelContainer: ModelContainer
    var planService: MonthlyPlanService
    var executionVM: MonthlyExecutionViewModel
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

        // Use mock FX to avoid network in goal calculation
        let mockFX = MockExchangeRateService()
        let goalCalc = GoalCalculationService(
            exchangeRateService: mockFX,
            tatumService: DIContainer.shared.tatumService,
            modelContext: context
        )
        self.planService = MonthlyPlanService(modelContext: context, goalCalculationService: goalCalc)
        self.executionVM = MonthlyExecutionViewModel(modelContext: context)
        self.contributionService = ContributionService(modelContext: context)
    }

    @Test("ViewModel journey: execution reflects deposit + reallocation totals")
    func testViewModelDepositAndReallocate() async throws {
        let context = modelContainer.mainContext

        // Seed goals and shared asset
        let goalA = Goal(
            name: "VM Goal A",
            currency: "USD",
            targetAmount: 4000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        let goalB = Goal(
            name: "VM Goal B",
            currency: "USD",
            targetAmount: 3000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goalA)
        context.insert(goalB)

        let sharedAsset = Asset(currency: "USD")
        let seedTx = Transaction(amount: 200, asset: sharedAsset)
        sharedAsset.transactions.append(seedTx)
        context.insert(sharedAsset)
        try context.save()

        // Create plans via service (mirrors planning pipeline)
        let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: [goalA, goalB])
        #expect(plans.count == 2)

        // Start execution via VM
        await executionVM.startTracking(plans: plans, goals: [goalA, goalB])
        guard let record = executionVM.executionRecord else {
            Issue.record("Execution record missing after startTracking")
            return
        }
        #expect(record.status == .executing)

        // Deposit to Goal A
        let deposit = try contributionService.recordDeposit(
            amount: 120,
            assetAmount: 120,
            to: goalA,
            from: sharedAsset,
            exchangeRate: 1.0
        )
        try DIContainer.shared.executionTrackingService(modelContext: context)
            .linkContribution(deposit, to: record)

        // Reallocate 40 from goal A to goal B
        let reallocation = try contributionService.recordReallocation(
            fiatAmount: 40,
            assetAmount: 40,
            from: goalA,
            to: goalB,
            asset: sharedAsset,
            exchangeRate: 1.0
        )
        let execService = DIContainer.shared.executionTrackingService(modelContext: context)
        try execService.linkContribution(reallocation.withdrawal, to: record)
        try execService.linkContribution(reallocation.deposit, to: record)

        // Reload execution VM to simulate UI refresh
        await executionVM.loadCurrentMonth()

        // Check execution totals exposed by VM
        let totals = executionVM.contributedTotals
        #expect(totals[goalA.id] == 80, "Goal A net should be 80 after reallocation")
        #expect(totals[goalB.id] == 40, "Goal B should gain 40 via reallocation")

        // Ensure snapshot/record still present
        #expect(executionVM.executionRecord?.snapshot != nil)

        // Verify progress > 0 (reflecting contributions)
        #expect(executionVM.overallProgress > 0)
    }
}
