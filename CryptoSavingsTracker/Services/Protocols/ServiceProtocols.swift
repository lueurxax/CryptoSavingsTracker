//
//  ServiceProtocols.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation

// MARK: - Mock Error Type
enum MockError: Error {
    case calculationFailed
    case notificationFailed
    case networkError
}

// MARK: - Exchange Rate Service Protocol
protocol ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String) async throws -> Double
    func fetchRatesInBatch(from: String, to currencies: [String]) async throws -> [String: Double]
    func getCachedRate(from: String, to: String) -> Double?
}

// MARK: - Balance Service Protocol
protocol BalanceServiceProtocol {
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool) async throws -> Double
}

// MARK: - Transaction Service Protocol
protocol TransactionServiceProtocol {
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction]
}

// MARK: - Tatum Service Protocol
protocol TatumServiceProtocol: BalanceServiceProtocol, TransactionServiceProtocol {
    var supportedChains: [TatumChain] { get }
    func searchChains(query: String) -> [TatumChain]
}

// MARK: - Flex Calculation Result
struct FlexCalculationResult {
    let originalTotal: Double
    let adjustedTotal: Double
    let difference: Double
    let adjustedRequirements: [MonthlyRequirement]
    let impactAnalysis: [ImpactAnalysis]
    
    struct ImpactAnalysis {
        let goalId: UUID
        let estimatedDelay: Int
        let riskLevel: String
    }
}

// MARK: - Monthly Planning Service Protocol
protocol MonthlyPlanningServiceProtocol {
    func calculateMonthlyRequirement(for goal: Goal) async throws -> MonthlyRequirement
    func calculateAllRequirements(for goals: [Goal]) async throws -> [MonthlyRequirement]
    func calculateFlexScenarios(for requirements: [MonthlyRequirement], flexPercentage: Double) async throws -> FlexCalculationResult
}

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func scheduleReminder(for goal: Goal) async throws
    func cancelReminder(for goal: Goal) async throws
    func requestAuthorization() async throws -> Bool
    func checkAuthorizationStatus() async -> Bool
}

// MARK: - Mock Implementations

// Mock Exchange Rate Service
class MockExchangeRateService: ExchangeRateServiceProtocol {
    var mockRates: [String: Double] = [:]
    var shouldThrowError = false
    var fetchRateCallCount = 0
    
    func fetchRate(from: String, to: String) async throws -> Double {
        fetchRateCallCount += 1
        
        if shouldThrowError {
            throw ExchangeRateError.networkError
        }
        
        if from == to {
            return 1.0
        }
        
        let key = "\(from)-\(to)"
        return mockRates[key] ?? 1.5
    }
    
    func fetchRatesInBatch(from: String, to currencies: [String]) async throws -> [String: Double] {
        if shouldThrowError {
            throw ExchangeRateError.networkError
        }
        
        var results: [String: Double] = [:]
        for currency in currencies {
            results[currency] = try await fetchRate(from: from, to: currency)
        }
        return results
    }
    
    func getCachedRate(from: String, to: String) -> Double? {
        if from == to {
            return 1.0
        }
        let key = "\(from)-\(to)"
        return mockRates[key]
    }
}

// Mock Balance Service
class MockBalanceService: BalanceServiceProtocol {
    var mockBalances: [String: Double] = [:]
    var shouldThrowError = false
    var fetchBalanceCallCount = 0
    
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool) async throws -> Double {
        fetchBalanceCallCount += 1
        
        if shouldThrowError {
            throw TatumError.rateLimitExceeded
        }
        
        let key = "\(chainId)-\(address)-\(symbol)"
        return mockBalances[key] ?? 0.0
    }
}

// Mock Transaction Service
class MockTransactionService: TransactionServiceProtocol {
    var mockTransactions: [TatumTransaction] = []
    var shouldThrowError = false
    
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction] {
        if shouldThrowError {
            throw TatumError.rateLimitExceeded
        }
        
        return Array(mockTransactions.prefix(limit))
    }
}

// Mock Tatum Service
class MockTatumService: TatumServiceProtocol {
    let balanceService = MockBalanceService()
    let transactionService = MockTransactionService()
    
    var supportedChains: [TatumChain] = [
        TatumChain(id: "ETH", name: "Ethereum", nativeCurrencySymbol: "ETH", chainType: .evm),
        TatumChain(id: "BTC", name: "Bitcoin", nativeCurrencySymbol: "BTC", chainType: .utxo),
        TatumChain(id: "SOL", name: "Solana", nativeCurrencySymbol: "SOL", chainType: .other)
    ]
    
    func searchChains(query: String) -> [TatumChain] {
        let lowercased = query.lowercased()
        return supportedChains.filter { chain in
            chain.name.lowercased().contains(lowercased) ||
            chain.id.lowercased().contains(lowercased) ||
            chain.nativeCurrencySymbol.lowercased().contains(lowercased)
        }
    }
    
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool) async throws -> Double {
        return try await balanceService.fetchBalance(chainId: chainId, address: address, symbol: symbol, forceRefresh: forceRefresh)
    }
    
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction] {
        return try await transactionService.fetchTransactionHistory(chainId: chainId, address: address, currency: currency, limit: limit, forceRefresh: forceRefresh)
    }
}

// Mock Monthly Planning Service
class MockMonthlyPlanningService: MonthlyPlanningServiceProtocol {
    var mockRequirements: [MonthlyRequirement] = []
    var shouldThrowError = false
    
    func calculateMonthlyRequirement(for goal: Goal) async throws -> MonthlyRequirement {
        if shouldThrowError {
            throw MockError.calculationFailed
        }
        
        let monthsRemaining = max(1, goal.daysRemaining / 30)
        let remainingAmount = max(0, goal.targetAmount - goal.manualTotal)
        let requiredMonthly = remainingAmount / Double(monthsRemaining)
        
        return MonthlyRequirement(
            goalId: goal.id,
            goalName: goal.name,
            currency: goal.currency,
            targetAmount: goal.targetAmount,
            currentTotal: goal.manualTotal,
            remainingAmount: remainingAmount,
            monthsRemaining: monthsRemaining,
            requiredMonthly: requiredMonthly,
            progress: goal.manualProgress,
            deadline: goal.deadline,
            status: .onTrack
        )
    }
    
    func calculateAllRequirements(for goals: [Goal]) async throws -> [MonthlyRequirement] {
        if shouldThrowError {
            throw MockError.calculationFailed
        }
        
        var requirements: [MonthlyRequirement] = []
        for goal in goals {
            requirements.append(try await calculateMonthlyRequirement(for: goal))
        }
        return requirements
    }
    
    func calculateFlexScenarios(for requirements: [MonthlyRequirement], flexPercentage: Double) async throws -> FlexCalculationResult {
        if shouldThrowError {
            throw MockError.calculationFailed
        }
        
        let totalOriginal = requirements.reduce(0) { $0 + $1.requiredMonthly }
        let totalAdjusted = totalOriginal * (flexPercentage / 100)
        
        return FlexCalculationResult(
            originalTotal: totalOriginal,
            adjustedTotal: totalAdjusted,
            difference: totalAdjusted - totalOriginal,
            adjustedRequirements: requirements,
            impactAnalysis: []
        )
    }
}

// Mock Notification Service
class MockNotificationService: NotificationServiceProtocol {
    var authorizationGranted = true
    var scheduledReminders: Set<UUID> = []
    var shouldThrowError = false
    
    func scheduleReminder(for goal: Goal) async throws {
        if shouldThrowError {
            throw MockError.notificationFailed
        }
        scheduledReminders.insert(goal.id)
    }
    
    func cancelReminder(for goal: Goal) async throws {
        if shouldThrowError {
            throw MockError.notificationFailed
        }
        scheduledReminders.remove(goal.id)
    }
    
    func requestAuthorization() async throws -> Bool {
        if shouldThrowError {
            throw MockError.notificationFailed
        }
        return authorizationGranted
    }
    
    func checkAuthorizationStatus() async -> Bool {
        return authorizationGranted
    }
}