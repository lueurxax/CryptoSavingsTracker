//
//  ServiceProtocols.swift
//  CryptoSavingsTracker
//
//  Created by user on 13/08/2025.
//

import Foundation

enum ProviderRefreshCommitOutcome<Value> {
    case committed(Value)
    case superseded
}

struct ProviderRefreshGenerationToken: @unchecked Sendable {
    fileprivate let gate: ProviderRefreshGenerationGate
    fileprivate let routeKey: String
    fileprivate let generation: UInt64
}

/// Linearizes publication for provider requests that target the same canonical
/// route. A response may perform durable/cache/UI publication only while its
/// token is still the latest generation for that route.
final class ProviderRefreshGenerationGate: @unchecked Sendable {
    static let shared = ProviderRefreshGenerationGate()

    private let lock = NSLock()
    private var generationsByRoute: [String: UInt64] = [:]
    private var committedGenerationsByRoute: [String: UInt64] = [:]

    func begin(routeKey: String) -> ProviderRefreshGenerationToken {
        lock.lock()
        defer { lock.unlock() }

        var generation = (generationsByRoute[routeKey] ?? 0) &+ 1
        if generation == 0 {
            generation = 1
        }
        generationsByRoute[routeKey] = generation
        // The latest generation is now in flight. A value committed by an
        // earlier generation must not masquerade as this request's result.
        committedGenerationsByRoute.removeValue(forKey: routeKey)
        return ProviderRefreshGenerationToken(
            gate: self,
            routeKey: routeKey,
            generation: generation
        )
    }

    func performIfCurrent<Value>(
        _ token: ProviderRefreshGenerationToken,
        _ operation: () throws -> Value
    ) rethrows -> ProviderRefreshCommitOutcome<Value> {
        lock.lock()
        defer { lock.unlock() }

        guard token.gate === self,
              generationsByRoute[token.routeKey] == token.generation
        else {
            return .superseded
        }
        let value = try operation()
        committedGenerationsByRoute[token.routeKey] = token.generation
        return .committed(value)
    }

    /// Resolves a superseded request only when the route's latest generation
    /// has already committed. The operation runs under the same lock as
    /// publication, so a newly-started generation cannot make an older cache
    /// entry look authoritative between the check and the read.
    func performIfLatestGenerationCommitted<Value>(
        after token: ProviderRefreshGenerationToken,
        _ operation: () throws -> Value
    ) rethrows -> ProviderRefreshCommitOutcome<Value> {
        lock.lock()
        defer { lock.unlock() }

        guard token.gate === self,
              let latestGeneration = generationsByRoute[token.routeKey],
              latestGeneration != token.generation,
              committedGenerationsByRoute[token.routeKey] == latestGeneration
        else {
            return .superseded
        }
        return .committed(try operation())
    }
}

struct ProviderTransactionHistoryBatch {
    let transactions: [TatumTransaction]
    let publicationToken: ProviderRefreshGenerationToken?

    init(
        transactions: [TatumTransaction],
        publicationToken: ProviderRefreshGenerationToken? = nil
    ) {
        self.transactions = transactions
        self.publicationToken = publicationToken
    }

    func commitIfCurrent<Value>(
        _ operation: () throws -> Value
    ) rethrows -> ProviderRefreshCommitOutcome<Value> {
        guard let publicationToken else {
            return .committed(try operation())
        }
        return try publicationToken.gate.performIfCurrent(
            publicationToken,
            operation
        )
    }
}

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

/// Exact, synchronous evidence for a rate that is already authoritative in a service.
/// Reading this evidence must never trigger a provider request.
struct ExchangeRateSnapshotEvidence: Equatable, Sendable {
    let from: String
    let to: String
    let rate: UInt64
    let timestamp: UInt64?

    init(from: String, to: String, rate: Double, timestamp: Date?) {
        self.from = from.uppercased()
        self.to = to.uppercased()
        self.rate = rate.bitPattern
        self.timestamp = timestamp?.timeIntervalSinceReferenceDate.bitPattern
    }
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
    func rateSnapshotTimestamp(for pairs: Set<String>) -> Date?

    /// Returns current in-memory evidence without fetching or refreshing a rate.
    func rateSnapshotEvidence(from: String, to: String) -> ExchangeRateSnapshotEvidence?
}

extension ExchangeRateServiceProtocol {
    func rateSnapshotTimestamp(for pairs: Set<String>) -> Date? { nil }
    func rateSnapshotEvidence(from: String, to: String) -> ExchangeRateSnapshotEvidence? { nil }
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
    func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult
    func getCurrentTotal(for goal: Goal) async -> Double
    func getProgress(for goal: Goal) async -> Double
    func getSuggestedDeposit(for goal: Goal) async -> Double

    // Static helpers (backward compatibility)
    static func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult
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
    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch
    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    )
    func hasValidConfiguration() -> Bool
    func setOfflineMode(_ offline: Bool)
}

protocol TransactionServiceProtocol {
    func fetchTransactionHistory(chainId: String, address: String, currency: String?, limit: Int, forceRefresh: Bool) async throws -> [TatumTransaction]
    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch
    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    )
}

extension TatumServiceProtocol {
    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch {
        ProviderTransactionHistoryBatch(
            transactions: try await fetchTransactionHistory(
                chainId: chainId,
                address: address,
                currency: currency,
                limit: limit,
                forceRefresh: forceRefresh
            )
        )
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {}
}

extension TransactionServiceProtocol {
    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch {
        ProviderTransactionHistoryBatch(
            transactions: try await fetchTransactionHistory(
                chainId: chainId,
                address: address,
                currency: currency,
                limit: limit,
                forceRefresh: forceRefresh
            )
        )
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {}
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
        date: Date,
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
        budgetCurrency: String,
        validateBeforeCommit: @MainActor () -> Bool
    ) async throws
}

extension PlanningMutationServiceProtocol {
    func applyBudgetPlan(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan],
        budgetCurrency: String
    ) async throws {
        try await applyBudgetPlan(
            plan,
            currentPlans: currentPlans,
            budgetCurrency: budgetCurrency,
            validateBeforeCommit: { true }
        )
    }
}

@MainActor
protocol OnboardingMutationServiceProtocol {
    func createGoalFromTemplate(
        _ template: GoalTemplate,
        userProfile: UserProfile,
        selectedAssetCurrencies: Set<String>
    ) async throws
}

extension OnboardingMutationServiceProtocol {
    func createGoalFromTemplate(
        _ template: GoalTemplate,
        userProfile: UserProfile
    ) async throws {
        try await createGoalFromTemplate(
            template,
            userProfile: userProfile,
            selectedAssetCurrencies: Set(template.recommendedAssets.map(\.currency))
        )
    }
}
