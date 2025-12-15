//
//  ContributionExecutionTests.swift
//  CryptoSavingsTrackerTests
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Tests for ContributionService execution tracking features
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct ContributionExecutionTests {

    var modelContainer: ModelContainer
    var contributionService: ContributionService

    init() async throws {
        // Create in-memory model container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self,
            Asset.self,
            Contribution.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            configurations: config
        )

        let context = modelContainer.mainContext
        self.contributionService = ContributionService(modelContext: context)
    }

    // MARK: - Execution Tracking Tests

    @Test("Link contribution to execution record")
    func testLinkToExecutionRecord() async throws {
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

        let contribution = Contribution(
            amount: 500,
            goal: goal,
            asset: asset,
            source: .manualDeposit
        )
        context.insert(contribution)
        try context.save()

        let recordId = UUID()

        // When
        try contributionService.linkToExecutionRecord(contribution, recordId: recordId)

        // Then
        #expect(contribution.executionRecordId == recordId)
        #expect(contribution.isPlanned == true)
    }

    @Test("Get contributions for specific goal and month")
    func testGetContributionsForGoalAndMonth() async throws {
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

        let monthLabel = "2025-09"
        let recordId = UUID()

        // Create contributions for this month
        let contribution1 = Contribution(amount: 300, goal: goal, asset: asset, source: .manualDeposit)
        contribution1.executionRecordId = recordId
        context.insert(contribution1)

        let contribution2 = Contribution(amount: 200, goal: goal, asset: asset, source: .manualDeposit)
        contribution2.executionRecordId = recordId
        context.insert(contribution2)

        // Create contribution for different month
        let contribution3 = Contribution(amount: 100, goal: goal, asset: asset, source: .manualDeposit)
        context.insert(contribution3)

        try context.save()

        // When
        let contributions = try contributionService.getContributions(
            for: goal.id,
            monthLabel: monthLabel,
            executionRecordId: recordId
        )

        // Then
        #expect(contributions.count == 2)
        #expect(contributions.contains { $0.id == contribution1.id })
        #expect(contributions.contains { $0.id == contribution2.id })
    }

    @Test("Get all contributions for execution record")
    func testGetContributionsForExecutionRecord() async throws {
        // Given
        let context = modelContainer.mainContext
        let goal1 = TestHelpers.createGoal(
            name: "Goal 1",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
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

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)

        let recordId = UUID()

        // Create contributions for different goals but same record
        let contribution1 = Contribution(amount: 300, goal: goal1, asset: asset, source: .manualDeposit)
        contribution1.executionRecordId = recordId
        context.insert(contribution1)

        let contribution2 = Contribution(amount: 200, goal: goal2, asset: asset, source: .manualDeposit)
        contribution2.executionRecordId = recordId
        context.insert(contribution2)

        // Create contribution for different record
        let contribution3 = Contribution(amount: 100, goal: goal1, asset: asset, source: .manualDeposit)
        contribution3.executionRecordId = UUID()
        context.insert(contribution3)

        try context.save()

        // When
        let contributions = try contributionService.getContributions(for: recordId)

        // Then
        #expect(contributions.count == 2)
        #expect(contributions.contains { $0.id == contribution1.id })
        #expect(contributions.contains { $0.id == contribution2.id })
    }

    @Test("Record deposit with execution tracking")
    func testRecordDepositWithTracking() async throws {
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
        try context.save()

        // When
        let contribution = try contributionService.recordDeposit(
            amount: 500,
            assetAmount: 0.01,
            to: goal,
            from: asset,
            exchangeRate: 50000,
            exchangeRateProvider: "CoinGecko",
            notes: "Test deposit"
        )

        // Then
        #expect(contribution.amount == 500)
        #expect(contribution.assetAmount == 0.01)
        #expect(contribution.goal?.id == goal.id)
        #expect(contribution.asset?.id == asset.id)
        #expect(contribution.sourceType == .manualDeposit)
        #expect(contribution.exchangeRateSnapshot == 50000)
        #expect(contribution.currencyCode == "USD")
        #expect(contribution.assetSymbol == "BTC")
    }

    @Test("Record reallocation between goals")
    func testRecordReallocation() async throws {
        // Given
        let context = modelContainer.mainContext
        let fromGoal = TestHelpers.createGoal(
            name: "From Goal",
            currency: "USD",
            targetAmount: 10000,
            currentTotal: 6000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        context.insert(fromGoal)

        let toGoal = TestHelpers.createGoal(
            name: "To Goal",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 2000,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        context.insert(toGoal)

        let asset = TestHelpers.createAsset(currency: "BTC", currentAmount: 1.0)
        context.insert(asset)
        try context.save()

        // When
        let (withdrawal, deposit) = try contributionService.recordReallocation(
            fiatAmount: 1000,
            assetAmount: 0.02,
            from: fromGoal,
            to: toGoal,
            asset: asset,
            exchangeRate: 50000
        )

        // Then
        // Withdrawal
        #expect(withdrawal.amount == -1000)
        #expect(withdrawal.assetAmount == -0.02)
        #expect(withdrawal.goal?.id == fromGoal.id)
        #expect(withdrawal.sourceType == .assetReallocation)

        // Deposit
        #expect(deposit.amount == 1000)
        #expect(deposit.assetAmount == 0.02)
        #expect(deposit.goal?.id == toGoal.id)
        #expect(deposit.sourceType == .assetReallocation)
    }

    @Test("Get contribution statistics")
    func testGetStatistics() async throws {
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
        try context.save()

        // Create various contributions
        _ = try contributionService.recordDeposit(
            amount: 500,
            assetAmount: 0.01,
            to: goal,
            from: asset,
            exchangeRate: 50000
        )

        _ = try contributionService.recordDeposit(
            amount: 300,
            assetAmount: 0.006,
            to: goal,
            from: asset,
            exchangeRate: 50000
        )

        // When
        let stats = contributionService.getStatistics(for: goal)

        // Then
        #expect(stats.totalContributions == 2)
        #expect(stats.totalAmount == 800)
        #expect(stats.totalDeposited == 800)
        #expect(stats.averageContribution == 400)
    }
}
