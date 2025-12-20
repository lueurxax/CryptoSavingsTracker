//
//  ServiceProtocols.swift
//  CryptoSavingsTracker
//
//  Created by user on 13/08/2025.
//

import Foundation

protocol BalanceServiceProtocol {
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool) async throws -> Double
}

protocol ChainServiceProtocol {
    var supportedChains: [TatumChain] { get }
    func predictChain(for symbol: String) -> TatumChain?
    func getChain(by id: String) -> TatumChain?
    func isChainSupported(_ chainId: String) -> Bool
    func getV4ChainName(for chainId: String) -> String?
    func supportsV4API(_ chainId: String) -> Bool
}

protocol CoinGeckoServiceProtocol {
    var coins: [String] { get }
    var coinInfos: [CoinInfo] { get }
    var supportedCurrencies: [String] { get }
    var coinCacheStale: Bool { get }
    var currencyCacheStale: Bool { get }
    func fetchCoins() async
    func fetchSupportedCurrencies() async
    func hasValidConfiguration() -> Bool
    func setOfflineMode(_ offline: Bool)
}

// Default implementations so existing mocks don’t need to implement new flags
extension CoinGeckoServiceProtocol {
    var coinCacheStale: Bool { false }
    var currencyCacheStale: Bool { false }
}

protocol ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String) async throws -> Double
    func hasValidConfiguration() -> Bool
    func setOfflineMode(_ offline: Bool)
}

protocol FlexAdjustmentServiceProtocol {
    func applyFlexAdjustment(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        strategy: RedistributionStrategy
    ) async -> [AdjustedRequirement]

    func calculateOptimalAdjustment(
        requirements: [MonthlyRequirement],
        targetTotal: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        displayCurrency: String
    ) async -> OptimalAdjustmentResult

    func simulateAdjustment(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>
    ) async -> AdjustmentSimulation

    func clearCache()
}

protocol GoalCalculationServiceProtocol {
    // Instance methods (preferred for DI/mocking)
    func getCurrentTotal(for goal: Goal) async -> Double
    func getProgress(for goal: Goal) async -> Double
    func getSuggestedDeposit(for goal: Goal) async -> Double

    // Static helpers (backward compatibility)
    static func getCurrentTotal(for goal: Goal) async -> Double
    static func getProgress(for goal: Goal) async -> Double
    static func getSuggestedDeposit(for goal: Goal) async -> Double
    static func getDaysRemaining(for goal: Goal) -> Int
    static func isReminderEnabled(for goal: Goal) -> Bool
    static func getReminderFrequency(for goal: Goal) -> ReminderFrequency
    static func getReminderDates(for goal: Goal) -> [Date]
    static func getRemainingReminderDates(for goal: Goal) -> [Date]
    static func getNextReminder(for goal: Goal) -> Date?
    static func getManualTotal(for goal: Goal) -> Double
    static func getManualProgress(for goal: Goal) -> Double
}

@MainActor
protocol MonthlyPlanningServiceProtocol {
    var isCalculating: Bool { get }
    var lastCalculationError: Error? { get }
    var needsCacheRefresh: Bool { get }

    func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement]
    func calculateTotalRequired(for goals: [Goal], displayCurrency: String) async -> Double
    func getMonthlyRequirement(for goal: Goal) async -> MonthlyRequirement?
    func clearCache()
}

protocol TatumServiceProtocol {
    var supportedChains: [TatumChain] { get }
    func predictChain(for symbol: String) -> TatumChain?
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool) async throws -> Double
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction]
    func hasValidConfiguration() -> Bool
    func setOfflineMode(_ offline: Bool)
}

protocol TransactionServiceProtocol {
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction]
}
