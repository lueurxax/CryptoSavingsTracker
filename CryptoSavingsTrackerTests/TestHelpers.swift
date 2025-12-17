//
//  TestHelpers.swift
//  CryptoSavingsTrackerTests
//
//  Created by user on 27/07/2025.
//

import Foundation
import SwiftData
@testable import CryptoSavingsTracker

// MARK: - SwiftData Relationship Helpers

extension ModelContext {
    /// Helper to properly establish relationships and save in tests
    func saveWithRelationships() throws {
        self.processPendingChanges()
        try self.save()
        self.processPendingChanges()
    }
}

// MARK: - Test Data Factory

struct TestDataFactory {
    
    static func createSampleGoal(
        name: String = "Sample Goal",
        currency: String = "USD",
        targetAmount: Double = 1000,
        daysFromNow: Int = 30,
        frequency: ReminderFrequency = .weekly
    ) -> Goal {
        let deadline = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return Goal(
            name: name,
            currency: currency,
            targetAmount: targetAmount,
            deadline: deadline,
            frequency: frequency
        )
    }
    
    static func createSampleAsset(
        currency: String = "BTC",
        goal: Goal? = nil,
        amount: Double = 0
    ) -> Asset {
        let asset = Asset(currency: currency)
        if let goal {
            let allocation = AssetAllocation(asset: asset, goal: goal, amount: amount)
            goal.allocations.append(allocation)
            asset.allocations.append(allocation)
        }
        return asset
    }
    
    static func createSampleTransaction(
        amount: Double = 100,
        asset: Asset
    ) -> Transaction {
        return Transaction(amount: amount, asset: asset)
    }
    
    static func createCompleteTestData(in context: ModelContext) throws -> (Goal, [Asset], [Transaction]) {
        let goal = createSampleGoal(name: "Complete Test Goal", targetAmount: 5000)
        
        let btcAsset = createSampleAsset(currency: "BTC", goal: goal)
        let ethAsset = createSampleAsset(currency: "ETH", goal: goal)
        let usdAsset = createSampleAsset(currency: "USD", goal: goal)
        
        context.insert(goal)
        context.insert(btcAsset)
        context.insert(ethAsset)
        context.insert(usdAsset)
        
        let btcTransaction1 = createSampleTransaction(amount: 0.1, asset: btcAsset)
        let btcTransaction2 = createSampleTransaction(amount: 0.05, asset: btcAsset)
        let ethTransaction = createSampleTransaction(amount: 2.0, asset: ethAsset)
        let usdTransaction1 = createSampleTransaction(amount: 1000, asset: usdAsset)
        let usdTransaction2 = createSampleTransaction(amount: 500, asset: usdAsset)
        
        let transactions = [btcTransaction1, btcTransaction2, ethTransaction, usdTransaction1, usdTransaction2]
        
        for transaction in transactions {
            context.insert(transaction)
        }
        
        try context.save()
        
        return (goal, [btcAsset, ethAsset, usdAsset], transactions)
    }
}

// MARK: - Test Container Helper

struct TestContainer {
    /// Creates an in-memory ModelContainer with the full app schema.
    /// Use this for all SwiftData tests to ensure relationship consistency.
    /// Each call creates a unique store to avoid conflicts in parallel test execution.
    static func create() throws -> ModelContainer {
        let schema = Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            AllocationHistory.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            ExecutionSnapshot.self
        ])
        // Use UUID to ensure unique store name for parallel test execution
        let storeName = "testStore-\(UUID().uuidString)"
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func createWithSampleData() throws -> (ModelContainer, ModelContext) {
        let container = try create()
        let context = ModelContext(container)

        // Create some sample data
        let _ = try TestDataFactory.createCompleteTestData(in: context)

        return (container, context)
    }
}

// MARK: - Shared Mock Exchange Rate Service

class MockExchangeRateService: ExchangeRateServiceProtocol {
    private var rates: [String: Double] = [:]
    var shouldFail = false

    func setRate(from: String, to: String, rate: Double) {
        rates["\(from)-\(to)"] = rate
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        if shouldFail { throw ExchangeRateError.networkError }
        if from == to { return 1.0 }
        return rates["\(from)-\(to)"] ?? 1.0
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
}

// MARK: - Lightweight Goal/Asset helpers for tests

struct TestHelpers {
    static func createGoal(
        name: String,
        currency: String,
        targetAmount: Double,
        currentTotal: Double,
        deadline: Date
    ) -> Goal {
        let goal = Goal(
            name: name,
            currency: currency,
            targetAmount: targetAmount,
            deadline: deadline
        )
        if currentTotal != 0 {
            let asset = Asset(currency: currency)
            // Add transaction to give the asset a balance
            let tx = Transaction(amount: currentTotal, asset: asset)
            asset.transactions.append(tx)
            // Create allocation that references the asset balance
            let allocation = AssetAllocation(asset: asset, goal: goal, amount: abs(currentTotal))
            goal.allocations.append(allocation)
            asset.allocations.append(allocation)
        }
        return goal
    }

    static func createGoalWithAsset(
        name: String,
        currency: String,
        target: Double,
        current: Double,
        months: Int,
        context: ModelContext
    ) -> Goal {
        let deadline = Calendar.current.date(byAdding: .month, value: months, to: Date())!
        let goal = Goal(name: name, currency: currency, targetAmount: target, deadline: deadline)
        let asset = Asset(currency: currency)
        // Add transaction to give the asset a balance
        if current != 0 {
            let tx = Transaction(amount: current, asset: asset)
            asset.transactions.append(tx)
            context.insert(tx)
        }
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: abs(current))
        goal.allocations.append(allocation)
        asset.allocations.append(allocation)
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        return goal
    }

    static func createAsset(currency: String, currentAmount: Double) -> Asset {
        let asset = Asset(currency: currency)
        if currentAmount != 0 {
            let tx = Transaction(amount: currentAmount, asset: asset)
            asset.transactions.append(tx)
        }
        return asset
    }
}

// MARK: - Test-only compatibility helpers for legacy tests

extension Goal {
    /// Computed helper to mimic legacy goal.assets access in tests.
    var assets: [Asset] {
        get { allocations.compactMap { $0.asset } }
        set {
            allocations.removeAll()
            for asset in newValue {
                let allocation = AssetAllocation(asset: asset, goal: self, amount: asset.currentAmount)
                allocations.append(allocation)
                asset.allocations.append(allocation)
            }
        }
    }
}

extension Asset {
    /// Convenience init for tests to attach an asset to a goal with an optional starting balance.
    convenience init(currency: String, goal: Goal, address: String? = nil, chainId: String? = nil, balance: Double = 0) {
        self.init(currency: currency, address: address, chainId: chainId)
        let allocation = AssetAllocation(asset: self, goal: goal, amount: balance)
        goal.allocations.append(allocation)
        allocations.append(allocation)
        if balance != 0 {
            let tx = Transaction(amount: balance, asset: self)
            transactions.append(tx)
        }
    }
}

extension MonthlyPlan {
    /// Convenience init for tests defaulting monthLabel to current month.
    convenience init(
        goalId: UUID,
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        currency: String,
        status: RequirementStatus = .onTrack,
        flexState: FlexState = .flexible,
        state: PlanState = .draft
    ) {
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        self.init(
            goalId: goalId,
            monthLabel: monthLabel,
            requiredMonthly: requiredMonthly,
            remainingAmount: remainingAmount,
            monthsRemaining: monthsRemaining,
            currency: currency,
            status: status,
            flexState: flexState,
            state: state
        )
    }
}

// MARK: - Assertion Helpers

struct TestAssertions {
    
    static func assertGoalIsValid(_ goal: Goal) {
        assert(!goal.name.isEmpty, "Goal name should not be empty")
        assert(goal.targetAmount > 0, "Target amount should be positive")
        assert(goal.deadline > Date().addingTimeInterval(-86400), "Deadline should not be in the past by more than a day")
        assert(!goal.currency.isEmpty, "Currency should not be empty")
    }
    
    static func assertAssetIsValid(_ asset: Asset) {
        assert(!asset.currency.isEmpty, "Asset currency should not be empty")
        assert(asset.currentAmount >= 0, "Asset amount should not be negative (unless withdrawals are supported)")
    }
    
    static func assertTransactionIsValid(_ transaction: Transaction) {
        assert(transaction.amount != 0, "Transaction amount should not be zero")
        assert(transaction.date <= Date().addingTimeInterval(60), "Transaction date should not be in the future")
    }
    
    static func assertProgressIsValid(_ progress: Double) {
        assert(progress >= 0, "Progress should not be negative")
        assert(progress <= 1.0, "Progress should not exceed 100%")
    }
}

// MARK: - Test Configuration

struct TestConfiguration {
    static var isUITesting: Bool {
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
    }
    
    static var shouldUseMockServices: Bool {
        return ProcessInfo.processInfo.arguments.contains("--mock-services")
    }
    
    static func configureForTesting() {
        if isUITesting {
            // Clear any existing user defaults or persistent data
            // This would be called from the app delegate when running UI tests
        }
    }
}

// MARK: - Performance Testing Helpers

struct PerformanceTestHelper {
    
    static func measureTime<T>(_ operation: () throws -> T) rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try operation()
        let endTime = Date()
        return (result, endTime.timeIntervalSince(startTime))
    }
    
    static func measureAsyncTime<T>(_ operation: () async throws -> T) async rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try await operation()
        let endTime = Date()
        return (result, endTime.timeIntervalSince(startTime))
    }
    
    static func createLargeDataSet(goalCount: Int = 10, assetsPerGoal: Int = 5, transactionsPerAsset: Int = 10) throws -> ModelContainer {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        
        for goalIndex in 0..<goalCount {
            let goal = TestDataFactory.createSampleGoal(
                name: "Performance Goal \(goalIndex)",
                targetAmount: Double(1000 * (goalIndex + 1))
            )
            context.insert(goal)
            
            for assetIndex in 0..<assetsPerGoal {
                let asset = TestDataFactory.createSampleAsset(
                    currency: "ASSET\(goalIndex)_\(assetIndex)",
                    goal: goal
                )
                context.insert(asset)
                
                for transactionIndex in 0..<transactionsPerAsset {
                    let transaction = TestDataFactory.createSampleTransaction(
                        amount: Double(transactionIndex + 1) * 10.0,
                        asset: asset
                    )
                    context.insert(transaction)
                }
            }
        }
        
        try context.save()
        return container
    }
}
