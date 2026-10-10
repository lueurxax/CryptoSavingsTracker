import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Monthly plan financial input races", .serialized)
@MainActor
struct MonthlyPlanFinancialInputRaceTests {
    @Test("Get-or-create rejects authoritative on-chain balance drift across a later await")
    func getOrCreateRejectsAuthoritativeOnChainBalanceDriftAcrossLaterAwait() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let tracked = makeOnChainGoal(name: "Tracked on-chain goal")
        let laterGoal = makeEmptyGoal(name: "Later goal")
        insertGraph(for: tracked.goal, into: context)
        insertGraph(for: laterGoal, into: context)
        try context.save()

        let cacheKey = tracked.cacheKey
        BalanceCacheManager.shared.cacheBalance(100, for: cacheKey)
        #expect(tracked.asset.currentAmount == 100)

        let rates = MonthlyPlanRaceExchangeRateService()
        let balances = MonthlyPlanRaceTatumService()
        let calculationService = MonthlyPlanSuspendingCalculationService(
            suspensionPoint: .before(goalID: laterGoal.id),
            exchangeRateService: rates,
            tatumService: balances,
            modelContext: context
        )
        let saveCounter = MonthlyPlanRaceSaveCounter()
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            }
        )

        let operation = Task { @MainActor in
            _ = try await service.getOrCreatePlans(
                for: "2026-08",
                goals: [tracked.goal, laterGoal]
            )
        }
        await calculationService.waitUntilSuspended()

        BalanceCacheManager.shared.cacheBalance(150, for: cacheKey)
        #expect(tracked.asset.currentAmount == 150)
        calculationService.resume()

        do {
            _ = try await operation.value
            Issue.record(
                "Expected get-or-create to reject an authoritative on-chain balance change"
            )
        } catch let error as PlanError {
            guard case .sourceDataChanged = error else {
                Issue.record("Expected sourceDataChanged, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PlanError.sourceDataChanged, got \(error)")
        }

        context.processPendingChanges()
        #expect(balances.fetchBalanceCalls == 1)
        #expect(saveCounter.attempts == 0)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
    }

    @Test("Get-or-create rejects exchange-rate evidence drift across a later await")
    func getOrCreateRejectsExchangeRateEvidenceDriftAcrossLaterAwait() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let convertedGoal = makeManualGoalRequiringFX(name: "Converted goal")
        let laterGoal = makeEmptyGoal(name: "Later goal")
        insertGraph(for: convertedGoal, into: context)
        insertGraph(for: laterGoal, into: context)
        try context.save()

        let initialSnapshotTime = Date(timeIntervalSince1970: 1_800_000_000)
        let rates = MonthlyPlanRaceExchangeRateService(
            rate: 2,
            snapshotTimestamp: initialSnapshotTime
        )
        let balances = MonthlyPlanRaceTatumService()
        let calculationService = MonthlyPlanSuspendingCalculationService(
            suspensionPoint: .before(goalID: laterGoal.id),
            exchangeRateService: rates,
            tatumService: balances,
            modelContext: context
        )
        let saveCounter = MonthlyPlanRaceSaveCounter()
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            }
        )

        let operation = Task { @MainActor in
            _ = try await service.getOrCreatePlans(
                for: "2026-08",
                goals: [convertedGoal, laterGoal]
            )
        }
        await calculationService.waitUntilSuspended()

        rates.replaceAuthoritativeSnapshot(
            rate: 3,
            timestamp: initialSnapshotTime.addingTimeInterval(60)
        )
        calculationService.resume()

        do {
            _ = try await operation.value
            Issue.record(
                "Expected get-or-create to reject changed exchange-rate evidence"
            )
        } catch let error as PlanError {
            guard case .sourceDataChanged = error else {
                Issue.record("Expected sourceDataChanged, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PlanError.sourceDataChanged, got \(error)")
        }

        context.processPendingChanges()
        #expect(rates.fetchRateCalls == 1)
        #expect(saveCounter.attempts == 0)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
    }

    @Test("Public update rejects authoritative on-chain balance drift after total derivation")
    func updatePlanRejectsAuthoritativeOnChainBalanceDriftAfterAwait() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let tracked = makeOnChainGoal(name: "Update on-chain goal")
        let plan = MonthlyPlan(
            goalId: tracked.goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 17,
            remainingAmount: 83,
            monthsRemaining: 5,
            currency: tracked.goal.currency,
            status: .critical
        )
        insertGraph(for: tracked.goal, into: context)
        context.insert(plan)
        try context.save()

        let cacheKey = tracked.cacheKey
        BalanceCacheManager.shared.cacheBalance(100, for: cacheKey)
        #expect(tracked.asset.currentAmount == 100)

        let originalPlan = MonthlyPlanRaceSnapshot(plan)
        let rates = MonthlyPlanRaceExchangeRateService()
        let balances = MonthlyPlanRaceTatumService()
        let calculationService = MonthlyPlanSuspendingCalculationService(
            suspensionPoint: .after(goalID: tracked.goal.id),
            exchangeRateService: rates,
            tatumService: balances,
            modelContext: context
        )
        let saveCounter = MonthlyPlanRaceSaveCounter()
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            }
        )

        let operation = Task { @MainActor in
            try await service.updatePlan(plan, withGoal: tracked.goal)
        }
        await calculationService.waitUntilSuspended()

        BalanceCacheManager.shared.cacheBalance(150, for: cacheKey)
        #expect(tracked.asset.currentAmount == 150)
        calculationService.resume()

        do {
            try await operation.value
            Issue.record(
                "Expected public updatePlan to reject a post-calculation balance change"
            )
        } catch let error as PlanError {
            guard case .sourceDataChanged = error else {
                Issue.record("Expected sourceDataChanged, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PlanError.sourceDataChanged, got \(error)")
        }

        context.processPendingChanges()
        #expect(balances.fetchBalanceCalls == 1)
        #expect(saveCounter.attempts == 0)
        #expect(MonthlyPlanRaceSnapshot(plan) == originalPlan)
        let durablePlan = try #require(
            ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>()).first
        )
        #expect(durablePlan.requiredMonthly == originalPlan.requiredMonthly)
    }

    @Test(
        "Get-or-create rejects a same-value cache refresh while the goal's FX conversion is suspended",
        arguments: [false, true]
    )
    func getOrCreateRejectsCacheFreshnessDriftDuringConversion(
        restoresBalanceAfterIntermediateChange: Bool
    ) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let tracked = makeOnChainGoal(name: "Suspended conversion goal")
        tracked.goal.currency = "USD"
        insertGraph(for: tracked.goal, into: context)
        try context.save()

        let originalTimestamp = Date()
        let expiresAt = originalTimestamp.addingTimeInterval(3_600)
        BalanceCacheManager.shared.cacheBalance(
            100,
            for: tracked.cacheKey,
            timestamp: originalTimestamp,
            expiresAt: expiresAt
        )
        let rates = MonthlyPlanSuspendingExchangeRateService()
        let balances = MonthlyPlanRaceTatumService()
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: balances,
            modelContext: context
        )
        let saveCounter = MonthlyPlanRaceSaveCounter()
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            }
        )

        let operation = Task { @MainActor in
            _ = try await service.getOrCreatePlans(for: "2026-08", goals: [tracked.goal])
        }
        await rates.waitUntilSuspended()
        if restoresBalanceAfterIntermediateChange {
            BalanceCacheManager.shared.cacheBalance(
                150,
                for: tracked.cacheKey,
                timestamp: originalTimestamp.addingTimeInterval(30),
                expiresAt: expiresAt
            )
        }
        BalanceCacheManager.shared.cacheBalance(
            100,
            for: tracked.cacheKey,
            timestamp: originalTimestamp.addingTimeInterval(60),
            expiresAt: expiresAt
        )
        rates.resume()

        do {
            _ = try await operation.value
            Issue.record("A balance receipt must retain the cache entry consumed before the FX await.")
        } catch let error as PlanError {
            guard case .sourceDataChanged = error else {
                Issue.record("Expected sourceDataChanged, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PlanError.sourceDataChanged, got \(error)")
        }

        #expect(tracked.asset.currentAmount == 100)
        #expect(balances.fetchBalanceCalls == 1)
        #expect(rates.fetchRateCalls == 1)
        #expect(saveCounter.attempts == 0)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
    }

    private func makeEmptyGoal(name: String) -> Goal {
        Goal(
            name: name,
            currency: "USD",
            targetAmount: 500,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    private func makeOnChainGoal(
        name: String
    ) -> (goal: Goal, asset: Asset, cacheKey: String) {
        let address = "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let goal = Goal(
            name: name,
            currency: "ETH",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let asset = Asset(currency: "ETH", address: address, chainId: "ETH")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 500)
        goal.allocations = [allocation]
        asset.allocations = [allocation]
        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: address,
            symbol: "ETH"
        )
        return (goal, asset, cacheKey)
    }

    private func makeManualGoalRequiringFX(name: String) -> Goal {
        let goal = Goal(
            name: name,
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let asset = Asset(currency: "BTC")
        let transaction = Transaction(amount: 100, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 100)
        asset.transactions = [transaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        return goal
    }

    private func insertGraph(for goal: Goal, into context: ModelContext) {
        context.insert(goal)
        for allocation in goal.allocations ?? [] {
            context.insert(allocation)
            guard let asset = allocation.asset else { continue }
            context.insert(asset)
            for transaction in asset.transactions ?? [] {
                context.insert(transaction)
            }
        }
    }
}

@MainActor
private final class MonthlyPlanSuspendingCalculationService: GoalCalculationService {
    enum SuspensionPoint {
        case before(goalID: UUID)
        case after(goalID: UUID)
    }

    private let suspensionPoint: SuspensionPoint
    private var hasSuspended = false
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(
        suspensionPoint: SuspensionPoint,
        exchangeRateService: ExchangeRateServiceProtocol,
        tatumService: TatumServiceProtocol,
        modelContext: ModelContext
    ) {
        self.suspensionPoint = suspensionPoint
        super.init(
            exchangeRateService: exchangeRateService,
            tatumService: tatumService,
            modelContext: modelContext
        )
    }

    override func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult {
        if case .before(let goalID) = suspensionPoint, goal.id == goalID {
            await suspend()
        }

        let result = await super.getCurrentTotalResult(for: goal)

        if case .after(let goalID) = suspensionPoint, goal.id == goalID {
            await suspend()
        }
        return result
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    private func suspend() async {
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
            hasSuspended = true
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}

@MainActor
private final class MonthlyPlanRaceExchangeRateService: ExchangeRateServiceProtocol {
    private(set) var fetchRateCalls = 0
    private var rate: Double
    private var snapshotTimestamp: Date

    init(
        rate: Double = 1,
        snapshotTimestamp: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) {
        self.rate = rate
        self.snapshotTimestamp = snapshotTimestamp
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        fetchRateCalls += 1
        return rate
    }

    func replaceAuthoritativeSnapshot(rate: Double, timestamp: Date) {
        self.rate = rate
        snapshotTimestamp = timestamp
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
    func rateSnapshotTimestamp(for pairs: Set<String>) -> Date? {
        pairs.isEmpty ? nil : snapshotTimestamp
    }
    func rateSnapshotEvidence(from: String, to: String) -> ExchangeRateSnapshotEvidence? {
        ExchangeRateSnapshotEvidence(
            from: from,
            to: to,
            rate: rate,
            timestamp: snapshotTimestamp
        )
    }
}

@MainActor
private final class MonthlyPlanSuspendingExchangeRateService: ExchangeRateServiceProtocol {
    private(set) var fetchRateCalls = 0
    private var hasSuspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func fetchRate(from: String, to: String) async throws -> Double {
        fetchRateCalls += 1
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
            hasSuspended = true
            suspensionWaiter?.resume()
            suspensionWaiter = nil
        }
        return 2
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiter = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

@MainActor
private final class MonthlyPlanRaceTatumService: TatumServiceProtocol {
    private(set) var fetchBalanceCalls = 0

    var supportedChains: [TatumChain] { [] }
    func predictChain(for symbol: String) -> TatumChain? { nil }

    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double {
        fetchBalanceCalls += 1
        let key = BalanceCacheManager.balanceCacheKey(
            chainId: chainId,
            address: address,
            symbol: symbol
        )
        return BalanceCacheManager.shared.getCachedBalance(for: key) ?? 0
    }

    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] {
        []
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
}

@MainActor
private final class MonthlyPlanRaceSaveCounter {
    var attempts = 0
}

private struct MonthlyPlanRaceSnapshot: Equatable {
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let statusRawValue: String
    let lastCalculated: Date
    let lastModifiedDate: Date

    init(_ plan: MonthlyPlan) {
        requiredMonthly = plan.requiredMonthly
        remainingAmount = plan.remainingAmount
        monthsRemaining = plan.monthsRemaining
        statusRawValue = plan.statusRawValue
        lastCalculated = plan.lastCalculated
        lastModifiedDate = plan.lastModifiedDate
    }
}
