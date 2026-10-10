import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Planning financial completeness", .serialized)
@MainActor
struct PlanningFinancialCompletenessTests {
    @Test("Monthly plan creation writes nothing for a degraded total and retry persists the exact plan")
    func monthlyPlanCreationBlocksDegradedTotalAndRetriesExactly() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: PlanningNoOpTatumService(),
            modelContext: context
        )
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService
        )
        let goal = makeMixedCurrencyGoal(
            deadline: try PlanningMonthContract.startDate(for: "2026-09").addingTimeInterval(-1)
        )
        insertGraph(for: goal, into: context)
        try context.saveWithRelationships()

        do {
            _ = try await service.getOrCreatePlans(for: "2026-08", goals: [goal])
            Issue.record("A degraded goal total must block monthly plan creation.")
        } catch {
            // Expected: the partial total is unavailable for financial planning.
        }

        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)

        rates.shouldFail = false
        rates.setRate(from: "EUR", to: "USD", rate: 2)

        let plans = try await service.getOrCreatePlans(for: "2026-08", goals: [goal])

        #expect(plans.count == 1)
        #expect(plans[0].remainingAmount == 800)
        #expect(plans[0].requiredMonthly == 800)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).count == 1)
    }

    @Test("Budget snapshot withholds a schedule when an asset balance is unavailable")
    func budgetSnapshotBlocksDegradedGoalTotal() async {
        let rates = MockExchangeRateService()
        let service = BudgetCalculatorService(exchangeRateService: rates)
        let goal = makeGoalWithUnavailableOnChainBalance()
        let entered = MoneyQuantizer.normalize(1_000, currency: "USD", mode: .halfUp)

        let snapshot = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "degraded-balance",
            rateSnapshotId: nil
        )

        #expect(snapshot.plan == nil)
        #expect(snapshot.timeline.isEmpty)
        #expect(snapshot.isFeasible == false)
        #expect(service.lastError != nil)
    }

    @Test("Monthly requirements are unavailable when an asset balance is unavailable")
    func monthlyRequirementsBlockDegradedGoalTotal() async {
        let service = MonthlyPlanningService(exchangeRateService: MockExchangeRateService())
        let goal = makeGoalWithUnavailableOnChainBalance()

        let requirements = await service.calculateMonthlyRequirements(for: [goal])

        #expect(requirements.isEmpty)
        #expect(service.lastCalculationError != nil)
    }

    @Test("Monthly total is unavailable instead of treating a missing FX rate as one-to-one")
    func monthlyTotalBlocksMissingExchangeRate() async {
        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let service = MonthlyPlanningService(exchangeRateService: rates)
        let goal = TestHelpers.createGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 500,
            currentTotal: 100,
            deadline: Date().addingTimeInterval(86_400)
        )

        let total = await service.calculateTotalRequired(for: [goal], displayCurrency: "USD")

        #expect(total == 0)
        #expect(service.lastCalculationError != nil)
    }

    @Test("Budget apply preflights its immutable FX snapshot before mutation and retry persists exact amounts")
    func budgetApplyBlocksPartialMutationAndRetriesExactly() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: rates,
            accessGuard: PlanningAllowAllAccessGuard()
        )
        let usdGoal = TestDataFactory.createSampleGoal(name: "USD Goal", currency: "USD")
        let eurGoal = TestDataFactory.createSampleGoal(name: "EUR Goal", currency: "EUR")
        let usdPlan = makePlan(goal: usdGoal, currency: "USD")
        let eurPlan = makePlan(goal: eurGoal, currency: "EUR")
        context.insert(usdGoal)
        context.insert(eurGoal)
        context.insert(usdPlan)
        context.insert(eurPlan)
        try context.save()

        let snapshotTimestamp = Date()
        let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: [usdGoal, eurGoal],
            remainingByGoal: [
                usdGoal.id: usdGoal.targetAmount,
                eurGoal.id: eurGoal.targetAmount
            ]
        )
        let missingRatePlan = BudgetCalculatorPlan(
            monthlyBudget: 300,
            currency: "USD",
            schedule: [
                ScheduledPayment(
                    paymentDate: Date(),
                    paymentNumber: 1,
                    contributions: [
                        GoalContribution(
                            goalId: usdGoal.id,
                            goalName: usdGoal.name,
                            amount: 100,
                            runningTotal: 100
                        ),
                        GoalContribution(
                            goalId: eurGoal.id,
                            goalName: eurGoal.name,
                            amount: 200,
                            runningTotal: 200
                        )
                    ]
                )
            ],
            isLeveled: false,
            minimumRequired: 300,
            rateSnapshotId: "missing-rate-snapshot",
            rateSnapshotTimestamp: snapshotTimestamp,
            applicationRatesByPair: [:],
            sourceStateSignature: sourceStateSignature
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.applyBudgetPlan(
                missingRatePlan,
                currentPlans: [usdPlan, eurPlan],
                budgetCurrency: "USD"
            )
        }

        #expect(usdPlan.customAmount == nil)
        #expect(eurPlan.customAmount == nil)

        let budgetPlan = BudgetCalculatorPlan(
            monthlyBudget: missingRatePlan.monthlyBudget,
            currency: missingRatePlan.currency,
            schedule: missingRatePlan.schedule,
            isLeveled: missingRatePlan.isLeveled,
            minimumRequired: missingRatePlan.minimumRequired,
            rateSnapshotId: "complete-rate-snapshot",
            rateSnapshotTimestamp: snapshotTimestamp,
            applicationRatesByPair: ["USD->EUR": 0.5],
            sourceStateSignature: sourceStateSignature
        )
        try await service.applyBudgetPlan(
            budgetPlan,
            currentPlans: [usdPlan, eurPlan],
            budgetCurrency: "USD"
        )

        #expect(usdPlan.customAmount == 100)
        #expect(eurPlan.customAmount == 100)

        let verificationContext = ModelContext(container)
        let persisted = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        #expect(persisted.first(where: { $0.goalId == usdGoal.id })?.customAmount == 100)
        #expect(persisted.first(where: { $0.goalId == eurGoal.id })?.customAmount == 100)
    }

    @Test("Planning view model publishes no partial total when one FX conversion fails")
    func planningViewModelBlocksPartialConvertedTotal() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let settings = MonthlyPlanningSettings()
        let originalSettings = PlanningSettingsSnapshot(settings)
        defer { originalSettings.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil

        let usdGoal = TestDataFactory.createSampleGoal(
            name: "USD Goal",
            currency: "USD",
            targetAmount: 100,
            daysFromNow: 30
        )
        let eurGoal = TestDataFactory.createSampleGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 200,
            daysFromNow: 30
        )
        context.insert(usdGoal)
        context.insert(eurGoal)
        try context.save()

        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: PlanningNoOpTatumService(),
            modelContext: context
        )
        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")

        #expect(viewModel.error != nil)
        #expect(viewModel.totalRequired == 0)
        #expect(viewModel.monthlyRequirements.isEmpty)
    }

    @Test("Planning load calculates each goal exactly once")
    func planningViewModelAvoidsRedundantDraftRefresh() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = MockExchangeRateService()
        let tatum = PlanningCountingTatumService()
        let settings = MonthlyPlanningSettings()
        let originalSettings = PlanningSettingsSnapshot(settings)
        defer { originalSettings.restore(to: settings) }
        settings.displayCurrency = "ETH"
        settings.monthlyBudget = nil

        let goal = TestDataFactory.createSampleGoal(
            name: "On-chain Goal",
            currency: "ETH",
            targetAmount: 10,
            daysFromNow: 30
        )
        let asset = Asset(
            currency: "ETH",
            address: "0xplanning-count",
            chainId: "ETH"
        )
        let transaction = Transaction(amount: 1, asset: asset)
        asset.transactions = [transaction]
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        insertGraph(for: goal, into: context)
        try context.saveWithRelationships()

        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: tatum,
            modelContext: context
        )
        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")

        #expect(viewModel.error == nil)
        #expect(tatum.fetchBalanceCallCount == 1)
        #expect(viewModel.monthlyRequirements.count == 1)
    }

    @Test("Unavailable balances never produce a healthy saved-budget state")
    func unavailableFeasibilityIsNotHealthy() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let settings = MonthlyPlanningSettings()
        let originalSettings = PlanningSettingsSnapshot(settings)
        defer { originalSettings.restore(to: settings) }
        settings.monthlyBudget = 1_000
        settings.budgetCurrency = "USD"
        settings.budgetAppliedMonthLabel = "2026-08"
        settings.budgetAppliedSignature = nil

        let service = BudgetCalculatorService(exchangeRateService: MockExchangeRateService())
        let result = await service.checkFeasibility(
            goals: [makeGoalWithUnavailableOnChainBalance()],
            budget: 1_000,
            currency: "USD"
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            budgetCalculatorService: service,
            settings: settings,
            configureObservers: false
        )
        viewModel.planningMonthLabel = "2026-08"
        viewModel.budgetFeasibility = result

        #expect(result.isFeasible == false)
        #expect(viewModel.budgetHealthState != .healthy)
    }

    @Test("Budget FX snapshots reuse only within TTL and explicit refresh invalidates them")
    func budgetRateSnapshotsHonorTTLAndExplicitRefresh() async {
        let rates = PlanningCountingExchangeRateService(rate: 1)
        let clock = PlanningTestClock(
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let service = BudgetCalculatorService(
            exchangeRateService: rates,
            now: { clock.now },
            rateSnapshotTTL: 300
        )
        let goal = TestDataFactory.createSampleGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 100,
            daysFromNow: 60
        )
        let entered = MoneyQuantizer.normalize(1_000, currency: "USD", mode: .halfUp)

        let first = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "ttl-goal",
            rateSnapshotId: nil
        )
        #expect(rates.fetchRateCallCount == 1)
        #expect(first.rateSnapshotTimestamp == clock.now)

        rates.rate = 2
        clock.advance(by: 299)
        let withinTTL = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "ttl-goal",
            rateSnapshotId: first.rateSnapshotId
        )
        #expect(rates.fetchRateCallCount == 1)
        #expect(withinTTL.rateSnapshotTimestamp == first.rateSnapshotTimestamp)
        #expect(withinTTL.minimumRequiredCanonical == first.minimumRequiredCanonical)

        clock.advance(by: 2)
        let expired = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "ttl-goal",
            rateSnapshotId: first.rateSnapshotId
        )
        #expect(rates.fetchRateCallCount == 2)
        #expect(expired.rateSnapshotTimestamp == clock.now)
        #expect(
            MoneyQuantizer.compare(
                expired.minimumRequiredCanonical,
                first.minimumRequiredCanonical
            ) == .orderedDescending
        )

        rates.rate = 3
        service.invalidateRateSnapshots()
        let explicitRefresh = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "ttl-goal",
            rateSnapshotId: expired.rateSnapshotId
        )
        #expect(rates.fetchRateCallCount == 3)
        #expect(
            MoneyQuantizer.compare(
                explicitRefresh.minimumRequiredCanonical,
                expired.minimumRequiredCanonical
            ) == .orderedDescending
        )
    }

    @Test("Schedule cache keys budget by exact canonical minor units")
    func budgetScheduleCacheDistinguishesKWDMinorUnits() async {
        let service = BudgetCalculatorService(exchangeRateService: MockExchangeRateService())
        let goal = TestDataFactory.createSampleGoal(
            name: "KWD Goal",
            currency: "KWD",
            targetAmount: 10,
            daysFromNow: 400
        )

        let first = await service.generateSchedule(
            goals: [goal],
            budget: 1.000,
            currency: "KWD"
        )
        let second = await service.generateSchedule(
            goals: [goal],
            budget: 1.005,
            currency: "KWD"
        )

        #expect(first.id != second.id)
        #expect(
            MoneyQuantizer.minorUnitValue(
                for: Decimal(second.monthlyBudget),
                currency: "KWD"
            ) == 1_005
        )
    }

    @Test("Budget apply restores only its plans after save failure and retry emits once")
    func budgetApplyRestoresOwnedMutationsAfterSaveFailure() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = MockExchangeRateService()
        rates.setRate(from: "USD", to: "EUR", rate: 0.5)
        let usdGoal = TestDataFactory.createSampleGoal(name: "USD Goal", currency: "USD")
        let eurGoal = TestDataFactory.createSampleGoal(name: "EUR Goal", currency: "EUR")
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Unrelated Goal", currency: "USD")
        unrelatedGoal.lifecycleStatus = .cancelled
        let usdPlan = makePlan(goal: usdGoal, currency: "USD")
        let eurPlan = makePlan(goal: eurGoal, currency: "EUR")
        context.insert(usdGoal)
        context.insert(eurGoal)
        context.insert(unrelatedGoal)
        context.insert(usdPlan)
        context.insert(eurPlan)
        try context.save()

        let usdLastModified = usdPlan.lastModifiedDate
        let eurLastModified = eurPlan.lastModifiedDate
        unrelatedGoal.name = "Unrelated dirty edit"

        let saveGate = PlanningSaveGate()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: rates,
            accessGuard: PlanningAllowAllAccessGuard(),
            saveChanges: {
                saveGate.attemptCount += 1
                if saveGate.shouldFail {
                    throw PlanningInjectedSaveError.failed
                }
                try context.save()
            }
        )
        let notifications = PlanningNotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let sourceStateSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: [usdGoal, eurGoal],
            remainingByGoal: [
                usdGoal.id: usdGoal.targetAmount,
                eurGoal.id: eurGoal.targetAmount
            ]
        )
        let budgetPlan = BudgetCalculatorPlan(
            monthlyBudget: 300,
            currency: "USD",
            schedule: [
                ScheduledPayment(
                    paymentDate: Date(),
                    paymentNumber: 1,
                    contributions: [
                        GoalContribution(
                            goalId: usdGoal.id,
                            goalName: usdGoal.name,
                            amount: 100,
                            runningTotal: 100
                        ),
                        GoalContribution(
                            goalId: eurGoal.id,
                            goalName: eurGoal.name,
                            amount: 200,
                            runningTotal: 200
                        )
                    ]
                )
            ],
            isLeveled: false,
            minimumRequired: 300,
            rateSnapshotId: "save-failure-snapshot",
            rateSnapshotTimestamp: Date(),
            applicationRatesByPair: ["USD->EUR": 0.5],
            sourceStateSignature: sourceStateSignature
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.applyBudgetPlan(
                budgetPlan,
                currentPlans: [usdPlan, eurPlan],
                budgetCurrency: "USD"
            )
        }

        #expect(usdPlan.customAmount == nil)
        #expect(eurPlan.customAmount == nil)
        #expect(usdPlan.lastModifiedDate == usdLastModified)
        #expect(eurPlan.lastModifiedDate == eurLastModified)
        #expect(unrelatedGoal.name == "Unrelated dirty edit")
        #expect(notifications.count == 0)
        #expect(saveGate.attemptCount == 0)

        let preflightVerificationContext = ModelContext(container)
        let preflightGoals = try preflightVerificationContext.fetch(FetchDescriptor<Goal>())
        #expect(
            preflightGoals.first(where: { $0.id == unrelatedGoal.id })?.name
                == "Unrelated Goal"
        )

        context.rollback()
        #expect(context.insertedModelsArray.isEmpty)
        #expect(context.changedModelsArray.isEmpty)
        #expect(context.deletedModelsArray.isEmpty)

        await #expect(throws: PersistenceMutationError.self) {
            try await service.applyBudgetPlan(
                budgetPlan,
                currentPlans: [usdPlan, eurPlan],
                budgetCurrency: "USD"
            )
        }
        #expect(usdPlan.customAmount == nil)
        #expect(eurPlan.customAmount == nil)
        #expect(saveGate.attemptCount == 1)
        #expect(notifications.count == 0)

        saveGate.shouldFail = false
        try await service.applyBudgetPlan(
            budgetPlan,
            currentPlans: [usdPlan, eurPlan],
            budgetCurrency: "USD"
        )

        #expect(usdPlan.customAmount == 100)
        #expect(eurPlan.customAmount == 100)
        #expect(saveGate.attemptCount == 2)
        #expect(notifications.count == 1)

        let verificationContext = ModelContext(container)
        let persistedPlans = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        let persistedGoals = try verificationContext.fetch(FetchDescriptor<Goal>())
        #expect(persistedPlans.first(where: { $0.goalId == usdGoal.id })?.customAmount == 100)
        #expect(persistedPlans.first(where: { $0.goalId == eurGoal.id })?.customAmount == 100)
        #expect(persistedGoals.first(where: { $0.id == unrelatedGoal.id })?.name == "Unrelated Goal")
    }

    private func makeMixedCurrencyGoal(deadline: Date) -> Goal {
        let goal = Goal(
            name: "Mixed Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: deadline
        )
        let usdAsset = Asset(currency: "USD")
        let eurAsset = Asset(currency: "EUR")
        let usdTransaction = Transaction(amount: 100, asset: usdAsset)
        let eurTransaction = Transaction(amount: 50, asset: eurAsset)
        usdAsset.transactions = [usdTransaction]
        eurAsset.transactions = [eurTransaction]

        let usdAllocation = AssetAllocation(asset: usdAsset, goal: goal, amount: 100)
        let eurAllocation = AssetAllocation(asset: eurAsset, goal: goal, amount: 50)
        goal.allocations = [usdAllocation, eurAllocation]
        usdAsset.allocations = [usdAllocation]
        eurAsset.allocations = [eurAllocation]
        return goal
    }

    private func makeGoalWithUnavailableOnChainBalance() -> Goal {
        let goal = Goal(
            name: "Unavailable Balance Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(
            currency: "USD",
            address: "test-address",
            chainId: "unsupported-test-chain"
        )
        let transaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [transaction]
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 100)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        return goal
    }

    private func insertGraph(for goal: Goal, into context: ModelContext) {
        context.insert(goal)
        for allocation in goal.allocations ?? [] {
            context.insert(allocation)
            if let asset = allocation.asset {
                context.insert(asset)
                for transaction in asset.transactions ?? [] {
                    context.insert(transaction)
                }
            }
        }
    }

    private func makePlan(goal: Goal, currency: String) -> MonthlyPlan {
        MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 100,
            remainingAmount: 500,
            monthsRemaining: 5,
            currency: currency,
            state: .draft
        )
    }
}

@MainActor
private final class PlanningCountingTatumService: TatumServiceProtocol {
    private(set) var fetchBalanceCallCount = 0

    var supportedChains: [TatumChain] { [] }

    func predictChain(for symbol: String) -> TatumChain? {
        nil
    }

    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double {
        fetchBalanceCallCount += 1
        return 0
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

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {}
}

@MainActor
private final class PlanningCountingExchangeRateService: ExchangeRateServiceProtocol {
    var rate: Double
    private(set) var fetchRateCallCount = 0

    init(rate: Double) {
        self.rate = rate
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        fetchRateCallCount += 1
        return from.uppercased() == to.uppercased() ? 1 : rate
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

@MainActor
private final class PlanningTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private struct PlanningSettingsSnapshot {
    let displayCurrency: String
    let monthlyBudget: Double?
    let budgetCurrency: String
    let budgetAppliedMonthLabel: String?
    let budgetAppliedSignature: String?

    init(_ settings: MonthlyPlanningSettings) {
        displayCurrency = settings.displayCurrency
        monthlyBudget = settings.monthlyBudget
        budgetCurrency = settings.budgetCurrency
        budgetAppliedMonthLabel = settings.budgetAppliedMonthLabel
        budgetAppliedSignature = settings.budgetAppliedSignature
    }

    func restore(to settings: MonthlyPlanningSettings) {
        settings.displayCurrency = displayCurrency
        settings.monthlyBudget = monthlyBudget
        settings.budgetCurrency = budgetCurrency
        settings.budgetAppliedMonthLabel = budgetAppliedMonthLabel
        settings.budgetAppliedSignature = budgetAppliedSignature
    }
}

@MainActor
private final class PlanningSaveGate {
    var shouldFail = true
    var attemptCount = 0
}

private enum PlanningInjectedSaveError: Error {
    case failed
}

private final class PlanningNotificationCounter: @unchecked Sendable {
    var count = 0
}

private struct PlanningNoOpTatumService: TatumServiceProtocol {
    var supportedChains: [TatumChain] { [] }

    func predictChain(for symbol: String) -> TatumChain? {
        nil
    }

    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double {
        0
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

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {}
}

@MainActor
private final class PlanningAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}
