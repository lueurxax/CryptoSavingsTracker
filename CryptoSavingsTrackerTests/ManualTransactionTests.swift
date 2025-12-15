//
//  ManualTransactionTests.swift
//  CryptoSavingsTrackerTests
//
//  Minimal placeholder covering manual transaction sanity.
//

import Testing
import Foundation
import SwiftData
@testable import CryptoSavingsTracker

@MainActor
struct ManualTransactionTests {
    @Test("Manual transaction creates a contribution record")
    func testManualTransactionCreatesContribution() async throws {
        let goal = Goal(
            name: "Manual Tx Goal",
            currency: "USD",
            targetAmount: 500,
            deadline: Date().addingTimeInterval(86400)
        )
        let asset = Asset(currency: "USD")
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            Contribution.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            ExecutionSnapshot.self,
            configurations: config
        )
        let context = container.mainContext
        context.insert(goal)
        context.insert(asset)
        let service = ContributionService(modelContext: context)
        let c = try service.recordDeposit(amount: 50, assetAmount: 50, to: goal, from: asset, exchangeRate: 1.0)
        #expect(c.amount == 50)
        #expect(c.goal != nil)
    }
}
