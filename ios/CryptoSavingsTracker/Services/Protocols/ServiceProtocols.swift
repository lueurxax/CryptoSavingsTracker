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

    /// Triggers a rate fetch if any tracked currency pair's cache has expired (5-minute TTL).
    /// No-op if all rates are still fresh. Posts `exchangeRatesDidRefresh` on successful fetch.
    /// Used by `FamilyShareForegroundRateRefreshDriver` to proactively keep rates current.
    func refreshRatesIfStale() async

    /// Returns the conservative snapshot timestamp for the supplied rate pairs.
    /// For mixed-age batches this is the oldest available pair timestamp.
    func rateSnapshotTimestamp(for pairs: Set<CurrencyPair>) -> Date?
}

extension ExchangeRateServiceProtocol {
    func rateSnapshotTimestamp(for pairs: Set<CurrencyPair>) -> Date? { nil }
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

enum PersistenceMutationError: LocalizedError {
    case validationFailed(String)
    case objectNotFound(String)
    case saveFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        case .objectNotFound(let message):
            return message
        case .saveFailed(let context, let underlying):
            return "\(context): \(underlying.localizedDescription)"
        }
    }
}

@MainActor
protocol GoalMutationServiceProtocol {
    func createGoal(_ goal: Goal) async throws
    func saveGoal(_ goal: Goal) async throws
    func archiveGoal(_ goal: Goal) async throws
    func restoreGoal(_ goal: Goal) async throws
    func resumeGoal(_ goal: Goal) async throws
}

@MainActor
protocol AssetMutationServiceProtocol {
    @discardableResult
    func createAsset(
        currency: String,
        address: String?,
        chainId: String?,
        goal: Goal
    ) async throws -> Asset
    func allocateAllUnallocated(of asset: Asset, to goal: Goal, bestKnownBalance: Double) throws
    func deleteAsset(_ asset: Asset) throws
    func deleteAssets(_ assets: [Asset]) throws
}

@MainActor
protocol TransactionMutationServiceProtocol {
    @discardableResult
    func createTransaction(
        for asset: Asset,
        amount: Double,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction
    func deleteTransaction(_ transaction: Transaction) throws
}

@MainActor
protocol PlanningMutationServiceProtocol {
    func markPlanCompleted(_ plan: MonthlyPlan) throws
    func markPlanSkipped(_ plan: MonthlyPlan) throws
    func deletePlan(_ plan: MonthlyPlan) throws
    func preparePlansForExecution(_ plans: [MonthlyPlan]) throws
    func resetPlansToDraft(_ plans: [MonthlyPlan]) throws
    func applyFeasibilitySuggestion(_ suggestion: FeasibilitySuggestion, goals: [Goal]) throws -> Bool
    func applyBudgetPlan(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan],
        budgetCurrency: String
    ) async throws
}

@MainActor
protocol OnboardingMutationServiceProtocol {
    func createGoalFromTemplate(_ template: GoalTemplate, userProfile: UserProfile) async throws
}
