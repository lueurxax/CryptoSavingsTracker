//
//  ExecutionSharedAssetIntegrationTests.swift
//  CryptoSavingsTrackerTests
//
//  Reproduces the shared-asset edge case:
//  1) Create two goals
//  2) Start planning & execution
//  3) Add a shared asset with a manual transaction
//  4) Allocate that asset across both goals
//  5) Verify execution contributions reflect the shared allocation (no zeros/phantoms)
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ExecutionSharedAssetIntegrationTests {
    var modelContainer: ModelContainer
    var planService: MonthlyPlanService
    var executionService: ExecutionTrackingService
    var contributionService: ContributionService
    var allocationService: AllocationService

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

        // Use mock FX for goal calc to avoid network
        let mockFX = MockExchangeRateService()
        let goalCalc = GoalCalculationService(
            exchangeRateService: mockFX,
            tatumService: DIContainer.shared.tatumService,
            modelContext: context
        )

        self.planService = MonthlyPlanService(modelContext: context, goalCalculationService: goalCalc)
        self.executionService = ExecutionTrackingService(modelContext: context)
        self.contributionService = ContributionService(modelContext: context)
        self.allocationService = AllocationService(modelContext: context)
        allocationService.setExecutionTracking(contributionService: contributionService, executionTrackingService: executionService)
    }

    @Test("Shared asset allocation creates execution contributions for both goals")
    func testSharedAssetAllocationUpdatesExecution() async throws {
        let context = modelContainer.mainContext
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        // 1) Create two goals
        let goalA = Goal(
            name: "Shared A",
            currency: "USD",
            targetAmount: 4000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        let goalB = Goal(
            name: "Shared B",
            currency: "USD",
            targetAmount: 3000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(goalA)
        context.insert(goalB)

        // 2) Planning + execution
        let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: [goalA, goalB])
        let record = try executionService.startTracking(for: monthLabel, from: plans, goals: [goalA, goalB])
        #expect(record.status == .executing)

        // 3) Add a shared asset with a manual transaction
        let asset = Asset(currency: "USD")
        let tx = Transaction(amount: 100, asset: asset)
        asset.transactions.append(tx)
        context.insert(asset)

        // 4) Allocate that asset across both goals (60/40 split)
        try allocationService.setAllocation(for: asset, to: goalA, amount: 60)
        try allocationService.setAllocation(for: asset, to: goalB, amount: 40)

        // 5) Verify execution contributions reflect the shared allocation
        let totals = try executionService.getContributionTotals(for: record)
        #expect(totals[goalA.id] == 60, "Goal A should have 60 contributed from shared asset")
        #expect(totals[goalB.id] == 40, "Goal B should have 40 contributed from shared asset")
    }
}
