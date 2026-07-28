import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Apple financial input races", .serialized)
@MainActor
struct AppleFinancialInputRaceTests {
    @Test(
        "Completion rejects financial inputs changed while FX is suspended",
        arguments: AppleCompletionInputDrift.allCases
    )
    func completionRejectsFinancialInputDrift(
        _ drift: AppleCompletionInputDrift
    ) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = Goal(
            name: "Race-safe completion",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 100,
            remainingAmount: 1_000,
            monthsRemaining: 10,
            currency: "USD"
        )
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(
            asset: asset,
            goal: goal,
            amount: 1
        )
        goal.allocations = [allocation]
        asset.allocations = [allocation]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let startService = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: ImmediateRaceExchangeRateService()
        )
        let record = try startService.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        let startedAt = try #require(record.startedAt)
        let initialTransaction = Transaction(
            amount: 1,
            asset: asset,
            date: startedAt.addingTimeInterval(60)
        )
        asset.transactions = [initialTransaction]
        context.insert(initialTransaction)
        try context.save()

        let rateService = SuspendedRaceExchangeRateService()
        let saveCounter = RaceSaveCounter()
        let completionService = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: rateService,
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            },
            now: { startedAt.addingTimeInterval(180) }
        )

        let completion = Task { @MainActor in
            try await completionService.markComplete(record)
        }
        await rateService.waitUntilFetchIsSuspended()

        switch drift {
        case .transactionAdded:
            let added = Transaction(
                amount: 0.25,
                asset: asset,
                date: startedAt.addingTimeInterval(120)
            )
            asset.transactions = (asset.transactions ?? []) + [added]
            context.insert(added)
        case .transactionDeleted:
            context.delete(initialTransaction)
        case .allocationChanged:
            allocation.updateAmount(2)
            let history = AllocationHistory(
                asset: asset,
                goal: goal,
                amount: 2,
                timestamp: startedAt.addingTimeInterval(120)
            )
            context.insert(history)
        case .planAmountChanged:
            plan.setCustomAmount(250)
        case .planStateChanged:
            plan.state = .draft
        }
        try context.save()

        await rateService.resume(with: 10)

        do {
            try await completion.value
            Issue.record("Completion must reject \(drift) after financial derivation began")
        } catch let error as ExecutionTrackingService.ExecutionError {
            guard case .executionInputsChanged = error else {
                Issue.record("Expected executionInputsChanged, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected ExecutionError, got \(error)")
        }

        context.processPendingChanges()
        #expect(saveCounter.attempts == 0)
        #expect(record.status == .executing)
        #expect(record.completedAt == nil)
        #expect(record.completedExecution == nil)
        #expect(
            try context.fetch(FetchDescriptor<CompletedExecution>()).isEmpty
        )
        #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).isEmpty)
        if drift != .planStateChanged {
            #expect(plan.state == .executing)
        }
    }

    @Test(
        "Budget apply rejects durable source drift while totals are suspended",
        arguments: AppleBudgetSourceDrift.allCases
    )
    func budgetApplyRejectsSourceDrift(
        _ drift: AppleBudgetSourceDrift
    ) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = Goal(
            name: "Race-safe budget",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 100,
            remainingAmount: 900,
            monthsRemaining: 9,
            currency: "USD"
        )
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(
            asset: asset,
            goal: goal,
            amount: 200
        )
        let initialTransaction = Transaction(
            amount: 100,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        goal.allocations = [allocation]
        asset.allocations = [allocation]
        asset.transactions = [initialTransaction]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        context.insert(initialTransaction)
        try context.save()

        let expectedTarget: Double
        let expectedRemaining: Double
        switch drift {
        case .balanceChanged:
            expectedTarget = 1_000
            expectedRemaining = 850
        case .allocationChanged:
            expectedTarget = 1_000
            expectedRemaining = 950
        case .targetChanged:
            expectedTarget = 1_200
            expectedRemaining = 1_100
        case .lifecycleChanged:
            expectedTarget = 1_000
            expectedRemaining = 900
        }
        goal.targetAmount = expectedTarget
        let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: [goal],
            remainingByGoal: [goal.id: expectedRemaining]
        )
        goal.targetAmount = 1_000
        try context.save()

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let budgetPlan = BudgetCalculatorPlan(
            createdAt: now,
            monthlyBudget: 25,
            currency: "USD",
            schedule: [
                ScheduledPayment(
                    paymentDate: now,
                    paymentNumber: 1,
                    contributions: [
                        GoalContribution(
                            goalId: goal.id,
                            goalName: goal.name,
                            amount: 25,
                            runningTotal: 25
                        )
                    ]
                )
            ],
            isLeveled: false,
            minimumRequired: 25,
            rateSnapshotId: "race-safe-budget-rates",
            rateSnapshotTimestamp: now,
            sourceStateSignature: sourceStateSignature
        )
        let totalProvider = SuspendedGoalTotalProvider()
        let saveCounter = RaceSaveCounter()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: ImmediateRaceExchangeRateService(),
            accessGuard: RaceAllowAllAccessGuard(),
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            },
            now: { now },
            currentTotalResult: { goal in
                await totalProvider.result(for: goal)
            }
        )

        let applying = Task { @MainActor in
            try await service.applyBudgetPlan(
                budgetPlan,
                currentPlans: [plan],
                budgetCurrency: "USD"
            )
        }
        await totalProvider.waitUntilSuspended()

        switch drift {
        case .balanceChanged:
            let added = Transaction(
                amount: 50,
                asset: asset,
                date: now
            )
            asset.transactions = (asset.transactions ?? []) + [added]
            context.insert(added)
        case .allocationChanged:
            allocation.updateAmount(50)
        case .targetChanged:
            goal.targetAmount = 1_200
        case .lifecycleChanged:
            goal.lifecycleStatus = .cancelled
            goal.lifecycleStatusChangedAt = now
        }
        try context.save()
        totalProvider.resume()

        do {
            try await applying.value
            Issue.record("Budget apply must reject \(drift) during total derivation")
        } catch let error as PersistenceMutationError {
            guard case .validationFailed = error else {
                Issue.record("Expected validationFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PersistenceMutationError, got \(error)")
        }

        context.processPendingChanges()
        #expect(saveCounter.attempts == 0)
        #expect(plan.customAmount == nil)
        #expect(plan.state == .draft)
    }

    @Test("Budget apply rejects on-chain cache drift while totals are suspended")
    func budgetApplyRejectsOnChainBalanceCacheDrift() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x0000000000000000000000000000000000000f31"
        let goal = Goal(
            name: "Race-safe on-chain budget",
            currency: "ETH",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 100,
            remainingAmount: 900,
            monthsRemaining: 9,
            currency: "ETH"
        )
        let asset = Asset(
            currency: "ETH",
            address: trackedAddress,
            chainId: "ETH"
        )
        let allocation = AssetAllocation(
            asset: asset,
            goal: goal,
            amount: 100
        )
        goal.allocations = [allocation]
        asset.allocations = [allocation]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "ETH"
        )
        BalanceCacheManager.shared.cacheBalance(100, for: cacheKey)
        #expect(asset.currentAmount == 100)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: [goal],
            remainingByGoal: [goal.id: 900]
        )
        let budgetPlan = BudgetCalculatorPlan(
            createdAt: now,
            monthlyBudget: 25,
            currency: "ETH",
            schedule: [
                ScheduledPayment(
                    paymentDate: now,
                    paymentNumber: 1,
                    contributions: [
                        GoalContribution(
                            goalId: goal.id,
                            goalName: goal.name,
                            amount: 25,
                            runningTotal: 25
                        )
                    ]
                )
            ],
            isLeveled: false,
            minimumRequired: 25,
            rateSnapshotId: "race-safe-on-chain-budget-rates",
            rateSnapshotTimestamp: now,
            sourceStateSignature: sourceStateSignature
        )
        let totalProvider = SuspendedGoalTotalProvider(totalOverride: 100)
        let saveCounter = RaceSaveCounter()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: ImmediateRaceExchangeRateService(),
            accessGuard: RaceAllowAllAccessGuard(),
            saveChanges: {
                saveCounter.attempts += 1
                try context.save()
            },
            now: { now },
            currentTotalResult: { goal in
                await totalProvider.result(for: goal)
            }
        )

        let applying = Task { @MainActor in
            try await service.applyBudgetPlan(
                budgetPlan,
                currentPlans: [plan],
                budgetCurrency: "ETH"
            )
        }
        await totalProvider.waitUntilSuspended()

        BalanceCacheManager.shared.cacheBalance(150, for: cacheKey)
        #expect(asset.currentAmount == 150)
        totalProvider.resume()

        do {
            try await applying.value
            Issue.record(
                "Budget apply must reject an on-chain balance cache change during total derivation"
            )
        } catch let error as PersistenceMutationError {
            guard case .validationFailed = error else {
                Issue.record("Expected validationFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected PersistenceMutationError, got \(error)")
        }

        context.processPendingChanges()
        #expect(saveCounter.attempts == 0)
        #expect(plan.customAmount == nil)
        #expect(plan.state == .draft)
    }
}

enum AppleCompletionInputDrift: String, CaseIterable, Sendable {
    case transactionAdded
    case transactionDeleted
    case allocationChanged
    case planAmountChanged
    case planStateChanged
}

enum AppleBudgetSourceDrift: String, CaseIterable, Sendable {
    case balanceChanged
    case allocationChanged
    case targetChanged
    case lifecycleChanged
}

@MainActor
private final class RaceSaveCounter {
    var attempts = 0
}

@MainActor
private final class RaceAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

@MainActor
private final class SuspendedGoalTotalProvider {
    private var hasSuspended = false
    private var calculationContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private let totalOverride: Double?

    init(totalOverride: Double? = nil) {
        self.totalOverride = totalOverride
    }

    func result(for goal: Goal) async -> GoalCurrentTotalResult {
        if !hasSuspended {
            hasSuspended = true
            await withCheckedContinuation { continuation in
                calculationContinuation = continuation
                let waiters = suspensionWaiters
                suspensionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        return GoalCurrentTotalResult(
            total: totalOverride ?? goal.manualTotal,
            error: nil
        )
    }

    func waitUntilSuspended() async {
        if calculationContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        let continuation = calculationContinuation
        calculationContinuation = nil
        continuation?.resume()
    }
}

private final class ImmediateRaceExchangeRateService:
    ExchangeRateServiceProtocol,
    @unchecked Sendable
{
    func fetchRate(from: String, to: String) async throws -> Double { 1 }
    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

private final class SuspendedRaceExchangeRateService:
    ExchangeRateServiceProtocol,
    @unchecked Sendable
{
    private let gate = SuspendedRaceRateGate()

    func fetchRate(from: String, to: String) async throws -> Double {
        await gate.fetch()
    }

    func waitUntilFetchIsSuspended() async {
        await gate.waitUntilFetchIsSuspended()
    }

    func resume(with rate: Double) async {
        await gate.resume(with: rate)
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

private actor SuspendedRaceRateGate {
    private var fetchContinuation: CheckedContinuation<Double, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func fetch() async -> Double {
        await withCheckedContinuation { continuation in
            fetchContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilFetchIsSuspended() async {
        if fetchContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume(with rate: Double) {
        let continuation = fetchContinuation
        fetchContinuation = nil
        continuation?.resume(returning: rate)
    }
}
