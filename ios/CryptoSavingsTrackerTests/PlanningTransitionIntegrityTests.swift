import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Planning transition integrity", .serialized)
@MainActor
struct PlanningTransitionIntegrityTests {
    @Test("Changing budget currency invalidates the old preview synchronously")
    func currencyChangeInvalidatesPreviewSynchronously() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            settings: settings,
            configureObservers: false
        )
        let usdAmount = MoneyQuantizer.normalize(1_000, currency: "USD", mode: .halfUp)
        let plan = makeBudgetPlan(
            contributions: [],
            currency: "USD",
            timestamp: Date()
        )
        viewModel.budgetComputationResult = makeReadySnapshot(
            amount: usdAmount,
            plan: plan,
            timestamp: plan.rateSnapshotTimestamp
        )
        viewModel.budgetPreviewPlan = plan
        viewModel.budgetPreviewTimeline = [
            ScheduledGoalBlock(
                goalId: UUID(),
                goalName: "Old USD preview",
                emoji: nil,
                startPaymentNumber: 1,
                endPaymentNumber: 1,
                startDate: Date(),
                endDate: Date(),
                totalAmount: 1_000,
                paymentCount: 1,
                isComplete: false
            )
        ]

        let eurAmount = MoneyQuantizer.normalize(1_000, currency: "EUR", mode: .halfUp)

        #expect(viewModel.isBudgetSnapshotCurrent(for: eurAmount) == false)
        viewModel.invalidateBudgetPreviewForInputChange()
        #expect(viewModel.budgetComputationResult == nil)
        #expect(viewModel.budgetPreviewPlan == nil)
        #expect(viewModel.budgetPreviewTimeline.isEmpty)
        #expect(viewModel.budgetSaveDisabledReason != nil)
    }

    @Test("A failed reload clears a previously healthy financial snapshot")
    func failedReloadClearsPreviouslyHealthyState() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [1])
        let tatum = TransitionTatumService()
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "ETH"
        settings.monthlyBudget = nil

        let goal = makeTrackedGoal(
            name: "Reload Goal",
            address: "reload-address",
            currency: "ETH",
            targetAmount: 100
        )
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
        let budgetService = BudgetCalculatorService(exchangeRateService: rates, settings: settings)
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            budgetCalculatorService: budgetService,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")
        #expect(viewModel.error == nil)
        #expect(viewModel.monthlyRequirements.count == 1)
        #expect(viewModel.totalRequired > 0)

        settings.monthlyBudget = 1_000
        settings.budgetCurrency = "ETH"
        settings.budgetAppliedMonthLabel = "2026-08"
        let amount = MoneyQuantizer.normalize(1_000, currency: "ETH", mode: .halfUp)
        let preview = makeBudgetPlan(
            contributions: [],
            currency: "ETH",
            timestamp: Date()
        )
        viewModel.budgetFeasibility = FeasibilityResult(
            isFeasible: true,
            minimumRequired: 100,
            currency: "ETH",
            infeasibleGoals: [],
            suggestions: []
        )
        viewModel.budgetComputationResult = makeReadySnapshot(
            amount: amount,
            plan: preview,
            timestamp: preview.rateSnapshotTimestamp
        )
        viewModel.budgetPreviewPlan = preview
        viewModel.budgetRateLastUpdated = preview.rateSnapshotTimestamp
        viewModel.budgetHasStaleRates = false
        viewModel.showBudgetRecalculationPrompt = false
        #expect(viewModel.budgetHealthState == .healthy)

        tatum.shouldFail = true
        await viewModel.loadMonthlyRequirements(for: "2026-08")

        #expect(viewModel.error is PlanError)
        #expect(viewModel.monthlyRequirements.isEmpty)
        #expect(viewModel.totalRequired == 0)
        #expect(viewModel.budgetFeasibility.isAvailable == false)
        #expect(viewModel.budgetComputationResult == nil)
        #expect(viewModel.budgetPreviewPlan == nil)
        #expect(viewModel.budgetRateLastUpdated == nil)
        #expect(viewModel.budgetHealthState != .healthy)
    }

    @Test(
        "Only the latest overlapping planning month may publish",
        arguments: [false, true]
    )
    func overlappingPlanningLoadsKeepLatestMonth(
        olderRequestFails: Bool
    ) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = SuspendedTransitionExchangeRateService()
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil

        let goal = Goal(
            name: "Overlapping month goal",
            currency: "EUR",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(365 * 86_400)
        )
        let olderPlan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 10,
            remainingAmount: 1_000,
            monthsRemaining: 10,
            currency: "EUR",
            state: .completed
        )
        let newerPlan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-09",
            requiredMonthly: 20,
            remainingAmount: 1_000,
            monthsRemaining: 9,
            currency: "EUR",
            state: .completed
        )
        context.insert(goal)
        context.insert(olderPlan)
        context.insert(newerPlan)
        try context.save()

        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: GoalCalculationService(
                exchangeRateService: rates,
                tatumService: TransitionTatumService(),
                modelContext: context
            )
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )

        let olderTask = Task {
            await viewModel.loadMonthlyRequirements(for: "2026-08")
        }
        await rates.waitForRequestCount(1)
        let newerTask = Task {
            await viewModel.loadMonthlyRequirements(for: "2026-09")
        }
        await rates.waitForRequestCount(2)

        rates.resumeRequest(at: 1, with: .success(3))
        await newerTask.value
        if olderRequestFails {
            rates.resumeRequest(
                at: 0,
                with: .failure(TransitionInjectedError.rateUnavailable)
            )
        } else {
            rates.resumeRequest(at: 0, with: .success(1))
        }
        await olderTask.value

        #expect(viewModel.planningMonthLabel == "2026-09")
        #expect(viewModel.monthlyRequirements.count == 1)
        #expect(viewModel.monthlyRequirements.first?.requiredMonthly == 20)
        #expect(viewModel.totalRequired == 60)
        #expect(viewModel.error == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("Same-month reload supersedes an older suspended budget preview")
    func sameMonthReloadSupersedesSuspendedBudgetPreview() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = SuspendedTransitionExchangeRateService()
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "EUR"
        settings.monthlyBudget = nil
        settings.budgetCurrency = "USD"
        settings.budgetAppliedMonthLabel = "2026-08"
        settings.budgetAppliedSignature = nil

        let goal = Goal(
            name: "Same-month source goal",
            currency: "EUR",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(365 * 86_400)
        )
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: 10,
            remainingAmount: 100,
            monthsRemaining: 10,
            currency: "EUR",
            state: .completed
        )
        context.insert(goal)
        context.insert(plan)
        try context.save()

        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: GoalCalculationService(
                exchangeRateService: rates,
                tatumService: TransitionTatumService(),
                modelContext: context
            )
        )
        let budgetService = BudgetCalculatorService(
            exchangeRateService: rates,
            settings: settings
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            budgetCalculatorService: budgetService,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")
        settings.monthlyBudget = 1_000

        await viewModel.previewBudget(amount: 100, currency: "USD")
        await rates.waitForRequestCount(1)

        let reloadTask = Task {
            await viewModel.loadMonthlyRequirements(for: "2026-08")
        }
        await rates.waitForRequestCount(2)
        rates.resumeRequest(at: 1, with: .success(2))
        await reloadTask.value

        let currentBudget = MoneyQuantizer.normalize(
            1_000,
            currency: "USD",
            mode: .halfUp
        )
        #expect(
            viewModel.budgetComputationResult?
                .enteredBudgetCanonical == currentBudget
        )

        rates.resumeRequest(at: 0, with: .success(1))
        await rates.waitForCompletedRequestCount(2)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(
            viewModel.budgetComputationResult?
                .enteredBudgetCanonical == currentBudget
        )
        #expect(viewModel.budgetPreviewPlan?.monthlyBudget == 1_000)
        #expect(viewModel.isBudgetSnapshotCurrent(for: currentBudget))
        #expect(viewModel.budgetSaveDisabledReason == nil)
    }

    @Test("Asset refresh recalculates drafts once and commits one batch")
    func assetRefreshRecalculatesDraftsOnceInOneBatch() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [1])
        let tatum = TransitionTatumService()
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "ETH"
        settings.monthlyBudget = nil

        let draftGoal = makeTrackedGoal(name: "Draft", address: "draft-address")
        let executingGoal = makeTrackedGoal(name: "Executing", address: "executing-address")
        let completedGoal = makeTrackedGoal(name: "Completed", address: "completed-address")
        for goal in [draftGoal, executingGoal, completedGoal] {
            insertGraph(for: goal, into: context)
        }
        let draftPlan = makeMonthlyPlan(goal: draftGoal, requiredMonthly: 10)
        let executingPlan = makeMonthlyPlan(goal: executingGoal, requiredMonthly: 20, state: .executing)
        let completedPlan = makeMonthlyPlan(goal: completedGoal, requiredMonthly: 30, state: .completed)
        context.insert(draftPlan)
        context.insert(executingPlan)
        context.insert(completedPlan)
        try context.saveWithRelationships()

        let saves = TransitionSaveGate(shouldFail: false)
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: tatum,
            modelContext: context
        )
        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saves.attemptCount += 1
                try context.save()
            }
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )
        viewModel.planningMonthLabel = "2026-08"

        await viewModel.handlePlanningAssetUpdate()

        #expect(tatum.callCount(for: "draft-address") == 1)
        #expect(tatum.callCount(for: "executing-address") == 0)
        #expect(tatum.callCount(for: "completed-address") == 0)
        #expect(saves.attemptCount == 1)
        #expect(draftPlan.requiredMonthly == 100)
        #expect(executingPlan.requiredMonthly == 20)
        #expect(completedPlan.requiredMonthly == 30)
    }

    @Test("Asset refresh writes nothing when any draft calculation fails")
    func assetRefreshFailureWritesNothing() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [1])
        let tatum = TransitionTatumService()
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "ETH"
        settings.monthlyBudget = nil

        let firstGoal = makeTrackedGoal(name: "First", address: "first-address")
        let secondGoal = makeTrackedGoal(name: "Second", address: "second-address")
        for goal in [firstGoal, secondGoal] {
            insertGraph(for: goal, into: context)
        }
        let firstPlan = makeMonthlyPlan(goal: firstGoal, requiredMonthly: 11)
        let secondPlan = makeMonthlyPlan(goal: secondGoal, requiredMonthly: 22)
        context.insert(firstPlan)
        context.insert(secondPlan)
        try context.saveWithRelationships()

        let saves = TransitionSaveGate(shouldFail: false)
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: tatum,
            modelContext: context
        )
        let planService = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saves.attemptCount += 1
                try context.save()
            }
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")
        firstPlan.requiredMonthly = 11
        secondPlan.requiredMonthly = 22
        try context.save()
        saves.attemptCount = 0
        tatum.reset(failOnCalls: [2])

        await viewModel.handlePlanningAssetUpdate()

        #expect(saves.attemptCount == 0)
        #expect(firstPlan.requiredMonthly == 11)
        #expect(secondPlan.requiredMonthly == 22)
        #expect(viewModel.error != nil)
    }

    @Test("Preview freshness expires at TTL and displays its exact snapshot timestamp")
    func previewFreshnessExpiresAndRefreshes() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let clock = TransitionClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let rates = TransitionSequenceExchangeRateService(rates: [2, 3])
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        let budgetService = BudgetCalculatorService(
            exchangeRateService: rates,
            settings: settings,
            now: { clock.now },
            rateSnapshotTTL: 300
        )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            exchangeRateService: rates,
            budgetCalculatorService: budgetService,
            settings: settings,
            configureObservers: false
        )
        viewModel.goals = [
            Goal(
                name: "EUR Goal",
                currency: "EUR",
                targetAmount: 100,
                deadline: Date().addingTimeInterval(86_400)
            )
        ]
        let amount = MoneyQuantizer.normalize(1_000, currency: "USD", mode: .halfUp)

        await viewModel.previewBudget(amount: amount, currency: "USD")
        try await Task.sleep(nanoseconds: 450_000_000)

        let firstSnapshot = try #require(viewModel.budgetComputationResult)
        #expect(firstSnapshot.rateSnapshotTimestamp == clock.now)
        #expect(viewModel.budgetRateLastUpdated == firstSnapshot.rateSnapshotTimestamp)
        #expect(viewModel.isBudgetSnapshotFresh)

        clock.advance(by: 301)
        #expect(viewModel.isBudgetSnapshotFresh == false)

        await viewModel.previewBudget(
            amount: amount,
            currency: "USD",
            forceRateRefresh: true
        )
        try await Task.sleep(nanoseconds: 450_000_000)

        let refreshed = try #require(viewModel.budgetComputationResult)
        #expect(refreshed.rateSnapshotTimestamp == clock.now)
        #expect(viewModel.budgetRateLastUpdated == refreshed.rateSnapshotTimestamp)
        #expect(viewModel.isBudgetSnapshotFresh)
        #expect(rates.fetchRateCallCount == 2)
    }

    @Test("Budget Apply uses the immutable preview rate once for every matching plan")
    func budgetApplyUsesPreviewRateSnapshot() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let clock = TransitionClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let rates = TransitionSequenceExchangeRateService(rates: [2, 4, 8])
        let firstGoal = Goal(
            name: "First EUR",
            currency: "EUR",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(400 * 86_400)
        )
        let secondGoal = Goal(
            name: "Second EUR",
            currency: "EUR",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(400 * 86_400)
        )
        let firstPlan = makeMonthlyPlan(goal: firstGoal, requiredMonthly: 100)
        let secondPlan = makeMonthlyPlan(goal: secondGoal, requiredMonthly: 100)
        context.insert(firstGoal)
        context.insert(secondGoal)
        context.insert(firstPlan)
        context.insert(secondPlan)
        try context.save()

        let calculator = BudgetCalculatorService(
            exchangeRateService: rates,
            now: { clock.now },
            rateSnapshotTTL: 300
        )
        let amount = MoneyQuantizer.normalize(1_000, currency: "USD", mode: .halfUp)
        let snapshot = await calculator.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [firstGoal, secondGoal],
            enteredBudget: amount,
            goalsSignature: "two-eur-goals",
            rateSnapshotId: nil
        )
        let previewPlan = try #require(snapshot.plan)
        #expect(rates.fetchRateCallCount == 1)

        let mutation = PlanningMutationService(
            modelContext: context,
            exchangeRateService: rates,
            accessGuard: TransitionAllowAllAccessGuard(),
            now: { clock.now },
            rateSnapshotTTL: 300
        )
        try await mutation.applyBudgetPlan(
            previewPlan,
            currentPlans: [firstPlan, secondPlan],
            budgetCurrency: "USD"
        )

        #expect(rates.fetchRateCallCount == 1)
        #expect(firstPlan.customAmount == 100)
        #expect(secondPlan.customAmount == 100)
    }

    @Test("Budget Apply rejects an expired preview snapshot")
    func budgetApplyRejectsExpiredSnapshot() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = TestDataFactory.createSampleGoal(name: "Expired", currency: "USD")
        let monthlyPlan = makeMonthlyPlan(goal: goal, requiredMonthly: 100)
        context.insert(goal)
        context.insert(monthlyPlan)
        try context.save()
        let plan = makeBudgetPlan(
            contributions: [
                GoalContribution(
                    goalId: goal.id,
                    goalName: goal.name,
                    amount: 100,
                    runningTotal: 100
                )
            ],
            currency: "USD",
            timestamp: now.addingTimeInterval(-301)
        )
        let mutation = PlanningMutationService(
            modelContext: context,
            exchangeRateService: TransitionSequenceExchangeRateService(rates: [1]),
            accessGuard: TransitionAllowAllAccessGuard(),
            now: { now },
            rateSnapshotTTL: 300
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await mutation.applyBudgetPlan(
                plan,
                currentPlans: [monthlyPlan],
                budgetCurrency: "USD"
            )
        }
        #expect(monthlyPlan.customAmount == nil)
    }

    @Test("Budget Apply rejects a currency that does not match the preview")
    func budgetApplyRejectsCurrencyMismatch() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = TestDataFactory.createSampleGoal(name: "Mismatch", currency: "EUR")
        let monthlyPlan = makeMonthlyPlan(goal: goal, requiredMonthly: 100)
        context.insert(goal)
        context.insert(monthlyPlan)
        try context.save()
        let plan = makeBudgetPlan(
            contributions: [
                GoalContribution(
                    goalId: goal.id,
                    goalName: goal.name,
                    amount: 100,
                    runningTotal: 100
                )
            ],
            currency: "USD",
            timestamp: now
        )
        let mutation = PlanningMutationService(
            modelContext: context,
            exchangeRateService: TransitionSequenceExchangeRateService(rates: [1]),
            accessGuard: TransitionAllowAllAccessGuard(),
            now: { now },
            rateSnapshotTTL: 300
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await mutation.applyBudgetPlan(
                plan,
                currentPlans: [monthlyPlan],
                budgetCurrency: "EUR"
            )
        }
        #expect(monthlyPlan.customAmount == nil)
    }

    @Test("Monthly total fetches one immutable rate per currency pair")
    func monthlyTotalUsesOneRatePerPair() async {
        let rates = TransitionSequenceExchangeRateService(rates: [2, 3])
        let service = MonthlyPlanningService(exchangeRateService: rates)
        let deadline = Date().addingTimeInterval(86_400)
        let goals = [
            Goal(
                name: "First EUR",
                currency: "EUR",
                targetAmount: 100,
                deadline: deadline
            ),
            Goal(
                name: "Second EUR",
                currency: "EUR",
                targetAmount: 100,
                deadline: deadline
            )
        ]

        let total = await service.calculateTotalRequired(
            for: goals,
            displayCurrency: "USD"
        )

        #expect(rates.fetchRateCallCount == 1)
        #expect(total == 400)
        #expect(service.lastCalculationError == nil)
    }

    @Test("Flex total uses persisted effective amounts and converts before summing")
    func flexTotalUsesEffectiveConvertedAmounts() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [2, 2, 2])
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        let deadline = Date().addingTimeInterval(86_400)
        let usdGoal = Goal(
            name: "USD Goal",
            currency: "USD",
            targetAmount: 100,
            deadline: deadline
        )
        let eurGoal = Goal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 100,
            deadline: deadline
        )
        let usdPlan = makeMonthlyPlan(goal: usdGoal, requiredMonthly: 100)
        let eurPlan = makeMonthlyPlan(goal: eurGoal, requiredMonthly: 100)
        context.insert(usdGoal)
        context.insert(eurGoal)
        context.insert(usdPlan)
        context.insert(eurPlan)
        try context.save()

        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: TransitionTatumService(),
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
        await viewModel.applyFlexAdjustment(0.5)

        #expect(usdPlan.customAmount == 50)
        #expect(eurPlan.customAmount == 50)
        #expect(viewModel.totalRequired == 150)
        #expect(viewModel.adjustedTotal == 150)
    }

    @Test("Bulk flex transitions clear conflicting persisted flags")
    func bulkFlexTransitionsPersistCanonicalFlags() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makePlanService(context: context)
        let flexibleGoal = TestDataFactory.createSampleGoal(name: "Flexible")
        let protectedGoal = TestDataFactory.createSampleGoal(name: "Protected")
        let skippedGoal = TestDataFactory.createSampleGoal(name: "Skipped")
        let flexiblePlan = makeMonthlyPlan(goal: flexibleGoal, requiredMonthly: 100)
        let protectedPlan = makeMonthlyPlan(goal: protectedGoal, requiredMonthly: 100)
        let skippedPlan = makeMonthlyPlan(goal: skippedGoal, requiredMonthly: 100)
        flexiblePlan.skipThisMonth(true)
        protectedPlan.skipThisMonth(true)
        skippedPlan.toggleProtection()
        for goal in [flexibleGoal, protectedGoal, skippedGoal] {
            context.insert(goal)
        }
        for plan in [flexiblePlan, protectedPlan, skippedPlan] {
            context.insert(plan)
        }
        try context.save()

        try await service.applyBulkFlexAdjustment(
            plans: [flexiblePlan, protectedPlan, skippedPlan],
            adjustment: 1,
            protectedGoalIds: [protectedGoal.id],
            skippedGoalIds: [skippedGoal.id]
        )

        let verificationContext = ModelContext(container)
        let persisted = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        let flexible = try #require(persisted.first { $0.goalId == flexibleGoal.id })
        let protected = try #require(persisted.first { $0.goalId == protectedGoal.id })
        let skipped = try #require(persisted.first { $0.goalId == skippedGoal.id })

        #expect(flexible.flexState == .flexible)
        #expect(flexible.isSkipped == false)
        #expect(flexible.isProtected == false)
        #expect(protected.flexState == .protected)
        #expect(protected.isProtected)
        #expect(protected.isSkipped == false)
        #expect(skipped.flexState == .skipped)
        #expect(skipped.isSkipped)
        #expect(skipped.isProtected == false)
    }

    @Test("Quick actions persist percentages and reset clears the override")
    func quickActionsPersistExplicitFlexPercentages() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [1])
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        let goal = Goal(
            name: "Quick Action",
            currency: "USD",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(86_400)
        )
        let plan = makeMonthlyPlan(goal: goal, requiredMonthly: 100)
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: TransitionTatumService(),
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

        await viewModel.applyQuickAction(.payHalf)
        #expect(viewModel.flexAdjustment == 0.5)
        #expect(plan.customAmount == 50)

        await viewModel.applyQuickAction(.payExact)
        #expect(viewModel.flexAdjustment == 1)
        #expect(plan.customAmount == 100)

        await viewModel.applyQuickAction(.reset)
        #expect(viewModel.flexAdjustment == 1)
        #expect(plan.customAmount == nil)
        #expect(plan.effectiveAmount == 100)
        #expect(plan.flexState == .flexible)
        #expect(plan.isProtected == false)
        #expect(plan.isSkipped == false)
    }

    @Test("A custom amount remains protected after a fresh reload")
    func customAmountPersistsProtection() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = TransitionSequenceExchangeRateService(rates: [1])
        let settings = MonthlyPlanningSettings()
        let defaults = TransitionDefaultsSnapshot(settings)
        defer { defaults.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        let goal = Goal(
            name: "Custom",
            currency: "USD",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(86_400)
        )
        let plan = makeMonthlyPlan(goal: goal, requiredMonthly: 100)
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let calculationService = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: TransitionTatumService(),
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

        viewModel.setCustomAmount(for: goal.id, amount: 75)

        #expect(plan.customAmount == 75)
        #expect(plan.flexState == .protected)
        #expect(plan.isProtected)
        #expect(plan.isSkipped == false)

        let verificationContext = ModelContext(container)
        let persisted = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        let reloaded = try #require(persisted.first { $0.goalId == goal.id })
        #expect(reloaded.customAmount == 75)
        #expect(reloaded.flexState == .protected)
        #expect(reloaded.isProtected)
        #expect(reloaded.isSkipped == false)
    }

    @Test("Bulk flex save failure restores only touched plans and retry notifies once")
    func bulkFlexSaveFailureRestoresOwnedStateAndRetries() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestDataFactory.createSampleGoal(name: "First")
        let secondGoal = TestDataFactory.createSampleGoal(name: "Second")
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Unrelated")
        let firstPlan = makeMonthlyPlan(goal: firstGoal, requiredMonthly: 100)
        let secondPlan = makeMonthlyPlan(goal: secondGoal, requiredMonthly: 200)
        context.insert(firstGoal)
        context.insert(secondGoal)
        context.insert(unrelatedGoal)
        context.insert(firstPlan)
        context.insert(secondPlan)
        try context.save()
        let firstModified = firstPlan.lastModifiedDate
        let secondModified = secondPlan.lastModifiedDate
        unrelatedGoal.name = "Unrelated dirty edit"

        let saveGate = TransitionSaveGate(shouldFail: true)
        let calculationService = GoalCalculationService(
            exchangeRateService: TransitionSequenceExchangeRateService(rates: [1]),
            tatumService: TransitionTatumService(),
            modelContext: context
        )
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: {
                saveGate.attemptCount += 1
                if saveGate.shouldFail {
                    throw TransitionInjectedError.saveFailed
                }
                try context.save()
            }
        )
        let notifications = TransitionNotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await #expect(throws: PersistenceMutationError.self) {
            try await service.applyBulkFlexAdjustment(
                plans: [firstPlan, secondPlan],
                adjustment: 0.5,
                protectedGoalIds: [],
                skippedGoalIds: []
            )
        }

        #expect(firstPlan.customAmount == nil)
        #expect(secondPlan.customAmount == nil)
        #expect(firstPlan.flexState == .flexible)
        #expect(secondPlan.flexState == .flexible)
        #expect(firstPlan.lastModifiedDate == firstModified)
        #expect(secondPlan.lastModifiedDate == secondModified)
        #expect(unrelatedGoal.name == "Unrelated dirty edit")
        #expect(notifications.count == 0)
        #expect(saveGate.attemptCount == 0)

        let preflightVerificationContext = ModelContext(container)
        let preflightGoals = try preflightVerificationContext.fetch(FetchDescriptor<Goal>())
        #expect(preflightGoals.first { $0.id == unrelatedGoal.id }?.name == "Unrelated")

        context.rollback()
        #expect(context.insertedModelsArray.isEmpty)
        #expect(context.changedModelsArray.isEmpty)
        #expect(context.deletedModelsArray.isEmpty)

        await #expect(throws: TransitionInjectedError.self) {
            try await service.applyBulkFlexAdjustment(
                plans: [firstPlan, secondPlan],
                adjustment: 0.5,
                protectedGoalIds: [],
                skippedGoalIds: []
            )
        }
        #expect(firstPlan.customAmount == nil)
        #expect(secondPlan.customAmount == nil)
        #expect(saveGate.attemptCount == 1)
        #expect(notifications.count == 0)

        saveGate.shouldFail = false
        try await service.applyBulkFlexAdjustment(
            plans: [firstPlan, secondPlan],
            adjustment: 0.5,
            protectedGoalIds: [],
            skippedGoalIds: []
        )

        #expect(firstPlan.customAmount == 50)
        #expect(secondPlan.customAmount == 100)
        #expect(saveGate.attemptCount == 2)
        #expect(notifications.count == 1)

        let verificationContext = ModelContext(container)
        let persistedPlans = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        let persistedGoals = try verificationContext.fetch(FetchDescriptor<Goal>())
        #expect(persistedPlans.first { $0.goalId == firstGoal.id }?.customAmount == 50)
        #expect(persistedPlans.first { $0.goalId == secondGoal.id }?.customAmount == 100)
        #expect(persistedGoals.first { $0.id == unrelatedGoal.id }?.name == "Unrelated")
    }

    private func makeBudgetPlan(
        contributions: [GoalContribution],
        currency: String,
        timestamp: Date?
    ) -> BudgetCalculatorPlan {
        BudgetCalculatorPlan(
            monthlyBudget: 1_000,
            currency: currency,
            schedule: [
                ScheduledPayment(
                    paymentDate: Date(),
                    paymentNumber: 1,
                    contributions: contributions
                )
            ],
            isLeveled: false,
            minimumRequired: 100,
            rateSnapshotId: "transition-snapshot",
            rateSnapshotTimestamp: timestamp,
            applicationRatesByPair: [:]
        )
    }

    private func makeReadySnapshot(
        amount: MoneyAmount,
        plan: BudgetCalculatorPlan,
        timestamp: Date?
    ) -> BudgetComputationResult {
        let minimum = MoneyQuantizer.normalize(100, currency: amount.currency, mode: .up)
        let zero = MoneyQuantizer.normalize(0, currency: amount.currency, mode: .halfUp)
        return BudgetComputationResult(
            requestId: UUID(),
            enteredBudgetCanonical: amount,
            minimumRequiredCanonical: minimum,
            shortfallCanonical: zero,
            isFeasible: true,
            plan: plan,
            timeline: [],
            rateSnapshotTimestamp: timestamp,
            rateSnapshotId: plan.rateSnapshotId,
            state: .readyFeasible,
            infeasibleGoals: [],
            suggestions: [],
            affectedCurrencies: []
        )
    }

    private func makeTrackedGoal(
        name: String,
        address: String,
        currency: String = "ETH",
        targetAmount: Double = 100
    ) -> Goal {
        let goal = Goal(
            name: name,
            currency: currency,
            targetAmount: targetAmount,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: currency, address: address, chainId: "ETH")
        let transaction = Transaction(amount: 0, asset: asset)
        asset.transactions = [transaction]
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: targetAmount)
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

    private func makeMonthlyPlan(
        goal: Goal,
        requiredMonthly: Double,
        state: MonthlyPlan.PlanState = .draft
    ) -> MonthlyPlan {
        MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-08",
            requiredMonthly: requiredMonthly,
            remainingAmount: goal.targetAmount,
            monthsRemaining: 1,
            currency: goal.currency,
            state: state
        )
    }

    private func makePlanService(context: ModelContext) -> MonthlyPlanService {
        MonthlyPlanService(
            modelContext: context,
            goalCalculationService: GoalCalculationService(
                exchangeRateService: TransitionSequenceExchangeRateService(rates: [1]),
                tatumService: TransitionTatumService(),
                modelContext: context
            )
        )
    }
}

@MainActor
private final class TransitionTatumService: TatumServiceProtocol {
    var shouldFail = false
    private var fetchCount = 0
    private var failOnCalls: Set<Int> = []
    private var callsByAddress: [String: Int] = [:]

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
        fetchCount += 1
        callsByAddress[address, default: 0] += 1
        if shouldFail || failOnCalls.contains(fetchCount) {
            throw TransitionInjectedError.balanceUnavailable
        }
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

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}

    func callCount(for address: String) -> Int {
        callsByAddress[address, default: 0]
    }

    func reset(failOnCalls: Set<Int> = []) {
        fetchCount = 0
        callsByAddress = [:]
        self.failOnCalls = failOnCalls
        shouldFail = false
    }
}

@MainActor
private final class TransitionSequenceExchangeRateService: ExchangeRateServiceProtocol {
    private let rates: [Double]
    private var nextIndex = 0
    private(set) var fetchRateCallCount = 0

    init(rates: [Double]) {
        self.rates = rates
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        if from.uppercased() == to.uppercased() {
            return 1
        }
        fetchRateCallCount += 1
        guard !rates.isEmpty else {
            throw TransitionInjectedError.rateUnavailable
        }
        let index = min(nextIndex, rates.count - 1)
        nextIndex += 1
        return rates[index]
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

@MainActor
private final class SuspendedTransitionExchangeRateService:
    ExchangeRateServiceProtocol {
    private var continuations: [
        CheckedContinuation<Double, any Error>?
    ] = []
    private var completedRequestCount = 0

    func fetchRate(from: String, to: String) async throws -> Double {
        if from.uppercased() == to.uppercased() {
            return 1
        }
        let rate = try await withCheckedThrowingContinuation {
            continuation in
            continuations.append(continuation)
        }
        completedRequestCount += 1
        return rate
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}

    func waitForRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func waitForCompletedRequestCount(_ expectedCount: Int) async {
        while completedRequestCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(
        at index: Int,
        with result: Result<Double, any Error>
    ) {
        let continuation = continuations[index]
        continuations[index] = nil
        continuation?.resume(with: result)
    }
}

@MainActor
private final class TransitionClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class TransitionSaveGate {
    var shouldFail: Bool
    var attemptCount = 0

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }
}

private final class TransitionNotificationCounter: @unchecked Sendable {
    var count = 0
}

private enum TransitionInjectedError: Error {
    case balanceUnavailable
    case rateUnavailable
    case saveFailed
}

@MainActor
private final class TransitionAllowAllAccessGuard: FamilyShareAccessChecking {
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
private struct TransitionDefaultsSnapshot {
    private let displayCurrency: String
    private let monthlyBudget: Double?
    private let budgetCurrency: String
    private let budgetAppliedMonthLabel: String?
    private let budgetAppliedSignature: String?
    private let protectedGoals: Any?
    private let skippedGoals: Any?
    private let flexAdjustment: Any?

    init(_ settings: MonthlyPlanningSettings) {
        displayCurrency = settings.displayCurrency
        monthlyBudget = settings.monthlyBudget
        budgetCurrency = settings.budgetCurrency
        budgetAppliedMonthLabel = settings.budgetAppliedMonthLabel
        budgetAppliedSignature = settings.budgetAppliedSignature
        protectedGoals = UserDefaults.standard.object(forKey: "MonthlyPlanning.ProtectedGoals")
        skippedGoals = UserDefaults.standard.object(forKey: "MonthlyPlanning.SkippedGoals")
        flexAdjustment = UserDefaults.standard.object(forKey: "MonthlyPlanning.FlexAdjustment")
    }

    func restore(to settings: MonthlyPlanningSettings) {
        settings.displayCurrency = displayCurrency
        settings.monthlyBudget = monthlyBudget
        settings.budgetCurrency = budgetCurrency
        settings.budgetAppliedMonthLabel = budgetAppliedMonthLabel
        settings.budgetAppliedSignature = budgetAppliedSignature
        restore(protectedGoals, forKey: "MonthlyPlanning.ProtectedGoals")
        restore(skippedGoals, forKey: "MonthlyPlanning.SkippedGoals")
        restore(flexAdjustment, forKey: "MonthlyPlanning.FlexAdjustment")
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
