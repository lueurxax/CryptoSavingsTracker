import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Planning third-review integrity", .serialized)
@MainActor
struct PlanningThirdReviewTests {
    @Test("Get-or-create restores recalculated drafts and discards only operation inserts before retry")
    func getOrCreateFailureIsAtomicAndRetrySafe() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let existingGoal = makeGoal(name: "Existing", target: 100)
        let missingGoal = makeGoal(name: "Missing", target: 200)
        let existingPlan = makePlan(goal: existingGoal, required: 10)
        existingPlan.remainingAmount = 40
        existingPlan.monthsRemaining = 4
        existingPlan.status = .critical

        context.insert(existingGoal)
        context.insert(missingGoal)
        context.insert(existingPlan)
        try context.save()

        let before = ThirdPlanSnapshot(existingPlan)
        let saveGate = ThirdSaveGate(context: context, shouldFail: true)
        let service = makePlanService(context: context, saveGate: saveGate)

        do {
            _ = try await service.getOrCreatePlans(for: "2026-08", goals: [existingGoal, missingGoal])
            Issue.record("Expected injected save failure")
        } catch {}

        context.processPendingChanges()
        #expect(ThirdPlanSnapshot(existingPlan) == before)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).map(\.goalId) == [existingGoal.id])

        saveGate.shouldFail = false
        let retried = try await service.getOrCreatePlans(
            for: "2026-08",
            goals: [existingGoal, missingGoal]
        )

        #expect(saveGate.attempts == 2)
        #expect(retried.count == 2)
        #expect(Set(retried.map(\.goalId)) == [existingGoal.id, missingGoal.id])
        let persisted = try ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>())
        #expect(persisted.count == 2)
        #expect(Set(persisted.map(\.goalId)) == [existingGoal.id, missingGoal.id])
    }

    @Test("Planning mutation transitions rollback only their operation and retry once")
    func planningMutationTransitionsAreAtomic() throws {
        for operation in ThirdPlanningMutationOperation.allCases {
            try verifyPlanningMutationTransition(operation)
        }
    }

    @Test("Monthly plan service transitions rollback only their operation and retry once")
    func monthlyPlanTransitionsAreAtomic() async throws {
        for operation in ThirdMonthlyPlanOperation.allCases {
            try await verifyMonthlyPlanTransition(operation)
        }
    }

    @Test("Budget Apply rejects every stale source-state dimension")
    func budgetApplyRejectsStaleSourceState() async throws {
        for change in ThirdSourceChange.allCases {
            let harness = try await makeBudgetHarness()
            let preview = try #require(harness.viewModel.budgetPreviewPlan)

            switch change {
            case .target:
                harness.goal.targetAmount += 50
            case .deadline:
                harness.goal.deadline = harness.goal.deadline.addingTimeInterval(86_400)
            case .allocation:
                harness.allocation.updateAmount(10)
            case .balance:
                harness.transaction.amount = 5
            }

            let applied = await harness.viewModel.applyBudgetPlan(
                plan: preview,
                amount: 1_000,
                currency: "USD"
            )

            #expect(applied == false, "Expected stale \(change) preview to be rejected")
            #expect(harness.plan.customAmount == nil)
            harness.restoreSettings()
        }
    }

    @Test("Budget Apply compares immutable plan contents, not only the plan id")
    func budgetApplyRejectsSameIdWithChangedContents() async throws {
        let harness = try await makeBudgetHarness()
        let preview = try #require(harness.viewModel.budgetPreviewPlan)
        let originalPayment = try #require(preview.schedule.first)
        let originalContribution = try #require(originalPayment.contributions.first)
        let changedContribution = GoalContribution(
            id: originalContribution.id,
            goalId: originalContribution.goalId,
            goalName: originalContribution.goalName,
            amount: originalContribution.amount + 1,
            isGoalStart: originalContribution.isGoalStart,
            isGoalComplete: originalContribution.isGoalComplete,
            runningTotal: originalContribution.runningTotal + 1
        )
        let changedPlan = BudgetCalculatorPlan(
            id: preview.id,
            createdAt: preview.createdAt,
            monthlyBudget: preview.monthlyBudget,
            currency: preview.currency,
            schedule: [
                ScheduledPayment(
                    id: originalPayment.id,
                    paymentDate: originalPayment.paymentDate,
                    paymentNumber: originalPayment.paymentNumber,
                    contributions: [changedContribution]
                )
            ],
            isLeveled: preview.isLeveled,
            minimumRequired: preview.minimumRequired,
            goalRemainingById: preview.goalRemainingById,
            rateSnapshotId: preview.rateSnapshotId,
            rateSnapshotTimestamp: preview.rateSnapshotTimestamp,
            applicationRatesByPair: preview.applicationRatesByPair,
            sourceStateSignature: preview.sourceStateSignature
        )

        let applied = await harness.viewModel.applyBudgetPlan(
            plan: changedPlan,
            amount: 1_000,
            currency: "USD"
        )

        #expect(applied == false)
        #expect(harness.plan.customAmount == nil)
        harness.restoreSettings()
    }

    @Test("A superseded budget intent cannot be stamped after Apply resumes")
    func budgetApplyRejectsIntentSupersededDuringMutationAwait() async throws {
        let mutation = ThirdSuspendingPlanningMutationService()
        let harness = try await makeBudgetHarness(
            planningMutationService: mutation
        )
        let originalPreview = try #require(harness.viewModel.budgetPreviewPlan)

        let application = Task { @MainActor in
            await harness.viewModel.applyBudgetPlan(
                plan: originalPreview,
                amount: 1_000,
                currency: "USD"
            )
        }
        await mutation.waitUntilSuspended()

        harness.viewModel.invalidateBudgetPreviewForInputChange()
        await harness.viewModel.previewBudget(amount: 900, currency: "USD")
        try await Task.sleep(nanoseconds: 450_000_000)
        let replacementPreview = try #require(
            harness.viewModel.budgetPreviewPlan
        )
        #expect(replacementPreview != originalPreview)

        mutation.resume()
        let applied = await application.value

        #expect(applied == false)
        #expect(mutation.didCommit == false)
        #expect(harness.settings.monthlyBudget == nil)
        #expect(harness.settings.budgetAppliedMonthLabel == nil)
        #expect(harness.settings.budgetAppliedSignature == nil)
        #expect(harness.plan.customAmount == nil)
        harness.restoreSettings()
    }

    @Test("Editing an applied budget amount or currency invalidates its application identity")
    func appliedBudgetIdentityIncludesAmountAndCurrency() async throws {
        for edit in ThirdBudgetEdit.allCases {
            let harness = try await makeBudgetHarness()
            let preview = try #require(harness.viewModel.budgetPreviewPlan)
            #expect(
                await harness.viewModel.applyBudgetPlan(
                    plan: preview,
                    amount: 1_000,
                    currency: "USD"
                )
            )
            #expect(harness.settings.budgetAppliedSignature != nil)

            switch edit {
            case .amount:
                harness.settings.monthlyBudget = 900
            case .currency:
                harness.settings.budgetCurrency = "EUR"
            }

            #expect(harness.settings.budgetAppliedSignature == nil)
            await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)
            #expect(harness.viewModel.budgetHealthState == .needsRecalculation)
            harness.restoreSettings()
        }
    }

    @Test("Changed remaining balance invalidates the applied budget identity")
    func appliedBudgetIdentityIncludesRemainingState() async throws {
        let harness = try await makeBudgetHarness()
        let preview = try #require(harness.viewModel.budgetPreviewPlan)
        #expect(
            await harness.viewModel.applyBudgetPlan(
                plan: preview,
                amount: 1_000,
                currency: "USD"
            )
        )
        let appliedSignature = try #require(harness.settings.budgetAppliedSignature)

        harness.transaction.amount = 5
        await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)

        #expect(harness.settings.budgetAppliedSignature == appliedSignature)
        #expect(harness.viewModel.showBudgetRecalculationPrompt)
        #expect(harness.viewModel.budgetHealthState == .needsRecalculation)
        harness.restoreSettings()
    }

    @Test("Applied budget identity includes persisted flex outputs")
    func appliedBudgetIdentityIncludesPersistedFlexOutputs() async throws {
        let harness = try await makeBudgetHarness()
        let preview = try #require(harness.viewModel.budgetPreviewPlan)
        #expect(
            await harness.viewModel.applyBudgetPlan(
                plan: preview,
                amount: 1_000,
                currency: "USD"
            )
        )
        let appliedSignature = try #require(harness.settings.budgetAppliedSignature)
        #expect(harness.viewModel.budgetHealthState == .healthy)

        await harness.viewModel.applyFlexAdjustment(0.5)
        await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)

        #expect(harness.settings.budgetAppliedSignature == appliedSignature)
        #expect(harness.viewModel.showBudgetRecalculationPrompt)
        #expect(harness.viewModel.budgetHealthState == .needsRecalculation)
        harness.restoreSettings()
    }

    @Test("Applied budget identity includes the payment day")
    func appliedBudgetIdentityIncludesPaymentDay() async throws {
        let harness = try await makeBudgetHarness()
        let preview = try #require(harness.viewModel.budgetPreviewPlan)
        #expect(
            await harness.viewModel.applyBudgetPlan(
                plan: preview,
                amount: 1_000,
                currency: "USD"
            )
        )
        let appliedSignature = try #require(harness.settings.budgetAppliedSignature)
        #expect(harness.viewModel.budgetHealthState == .healthy)

        harness.settings.paymentDay = harness.settings.paymentDay == 15 ? 16 : 15
        await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)

        #expect(harness.settings.budgetAppliedSignature == appliedSignature)
        #expect(harness.viewModel.showBudgetRecalculationPrompt)
        #expect(harness.viewModel.budgetHealthState == .needsRecalculation)
        harness.restoreSettings()
    }

    @Test("Applied budget identity includes the exact FX allocation inputs")
    func appliedBudgetIdentityIncludesExactFXInputs() async throws {
        let harness = try await makeBudgetHarness(goalCurrency: "EUR", exchangeRate: 2)
        let preview = try #require(harness.viewModel.budgetPreviewPlan)
        #expect(
            await harness.viewModel.applyBudgetPlan(
                plan: preview,
                amount: 1_000,
                currency: "USD"
            )
        )
        let appliedSignature = try #require(harness.settings.budgetAppliedSignature)
        #expect(harness.viewModel.budgetHealthState == .healthy)

        harness.rates.rate = 4
        harness.budgetService.invalidateRateSnapshots()
        await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)

        #expect(harness.settings.budgetAppliedSignature == appliedSignature)
        #expect(harness.viewModel.showBudgetRecalculationPrompt)
        #expect(harness.viewModel.budgetHealthState == .needsRecalculation)
        harness.restoreSettings()
    }

    @Test("Reset clears custom amount so recalculation returns to the automatic baseline")
    func resetClearsCustomAmountAndTracksRecalculation() async throws {
        let harness = try await makeFlexHarness()
        harness.viewModel.setCustomAmount(for: harness.goal.id, amount: 75)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(harness.plan.customAmount == 75)

        await harness.viewModel.applyQuickAction(.reset)

        #expect(harness.plan.customAmount == nil)
        #expect(harness.plan.isProtected == false)
        #expect(harness.plan.isSkipped == false)
        harness.goal.targetAmount = 80
        // Planning recalculation owns the plan write, not an unsaved goal-edit
        // draft. Persist the source edit as the real goal-edit flow does.
        try harness.context.save()
        await harness.viewModel.loadMonthlyRequirements(for: harness.monthLabel)
        #expect(harness.plan.requiredMonthly == 80)
        #expect(harness.plan.effectiveAmount == 80)
        harness.restoreSettings()
    }

    @Test("Clearing a custom amount also clears its automatic protection")
    func clearingCustomAmountClearsAutoProtection() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Clear Custom", target: 100)
        let plan = makePlan(goal: goal, required: 100)
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let service = makePlanService(context: context)

        try service.setCustomAmount(75, for: plan)
        #expect(plan.isProtected)
        try service.setCustomAmount(nil, for: plan)

        #expect(plan.customAmount == nil)
        #expect(plan.isProtected == false)
        #expect(plan.flexState == .flexible)
    }

    @Test("Requirement adapters keep the automatic baseline separate from effective flex amount")
    func requirementAdapterKeepsBaseAndEffectiveAmountsSeparate() async throws {
        let harness = try await makeFlexHarness()

        await harness.viewModel.applyFlexAdjustment(0.5)

        #expect(harness.viewModel.monthlyRequirements.first?.requiredMonthly == 100)
        #expect(harness.plan.requiredMonthly == 100)
        #expect(harness.plan.effectiveAmount == 50)
        #expect(harness.viewModel.getEffectiveAmount(for: harness.goal.id) == 50)
        harness.restoreSettings()
    }

    @Test("Failed toggle leaves DB, VM and defaults unchanged; retry commits once")
    func togglePersistencePrecedesViewModelAndDefaults() async throws {
        let defaults = ThirdFlexDefaultsSnapshot()
        defer { defaults.restore() }
        defaults.clear()
        let harness = try await makeFlexHarness()
        harness.saveGate.shouldFail = true
        harness.saveGate.attempts = 0

        await harness.viewModel.toggleProtection(for: harness.goal.id)
        try await Task.sleep(nanoseconds: 350_000_000)

        #expect(harness.plan.isProtected == false)
        #expect(harness.viewModel.protectedGoalIds.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: ThirdFlexDefaultsSnapshot.protectedKey) == nil)

        harness.saveGate.shouldFail = false
        await harness.viewModel.toggleProtection(for: harness.goal.id)
        try await Task.sleep(nanoseconds: 350_000_000)

        #expect(harness.saveGate.attempts == 2)
        #expect(harness.plan.isProtected)
        #expect(harness.viewModel.protectedGoalIds == [harness.goal.id])
        #expect(
            UserDefaults.standard.stringArray(forKey: ThirdFlexDefaultsSnapshot.protectedKey)
                == [harness.goal.id.uuidString]
        )
        harness.restoreSettings()
    }

    @Test("Failed quick action preserves persisted flex preference; retry and relaunch use the saved value")
    func quickActionAndSliderPreferencesAreTransactional() async throws {
        let defaults = ThirdFlexDefaultsSnapshot()
        defer { defaults.restore() }
        defaults.clear()
        let harness = try await makeFlexHarness()
        harness.saveGate.shouldFail = true
        harness.saveGate.attempts = 0

        await harness.viewModel.applyQuickAction(.payHalf)

        #expect(harness.plan.customAmount == nil)
        #expect(harness.viewModel.flexAdjustment == 1)
        #expect(UserDefaults.standard.object(forKey: ThirdFlexDefaultsSnapshot.adjustmentKey) == nil)

        harness.saveGate.shouldFail = false
        await harness.viewModel.applyQuickAction(.payHalf)
        #expect(harness.plan.customAmount == 50)
        #expect(harness.viewModel.flexAdjustment == 0.5)
        #expect(UserDefaults.standard.double(forKey: ThirdFlexDefaultsSnapshot.adjustmentKey) == 0.5)

        await harness.viewModel.applyFlexAdjustment(0.7)
        #expect(harness.plan.customAmount == 70)
        #expect(UserDefaults.standard.double(forKey: ThirdFlexDefaultsSnapshot.adjustmentKey) == 0.7)

        let relaunched = MonthlyPlanningViewModel(
            modelContext: harness.context,
            planService: harness.planService,
            exchangeRateService: harness.rates,
            settings: harness.settings,
            configureObservers: true
        )
        #expect(relaunched.flexAdjustment == 0.7)
        harness.restoreSettings()
    }

    @Test("Get-or-create aborts before saving when a prior goal source changes during a later await")
    func getOrCreateRejectsFinancialSourceDriftAcrossAwait() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestHelpers.createGoal(
            name: "First",
            currency: "USD",
            targetAmount: 100,
            currentTotal: 20,
            deadline: Date().addingTimeInterval(90 * 86_400)
        )
        let secondGoal = makeGoal(name: "Second", target: 200)
        insertGraph(for: firstGoal, into: context)
        insertGraph(for: secondGoal, into: context)
        try context.saveWithRelationships()

        let firstTransaction = try #require(
            firstGoal.allocations?.first?.asset?.transactions?.first
        )
        let calculationService = ThirdSuspendingGoalCalculationService(
            suspendOnGoalID: secondGoal.id
        )
        let saveGate = ThirdSaveGate(context: context, shouldFail: false)
        let service = MonthlyPlanService(
            modelContext: context,
            goalCalculationService: calculationService,
            saveChanges: saveGate.save
        )

        let operation = Task { @MainActor in
            _ = try await service.getOrCreatePlans(
                for: "2026-08",
                goals: [firstGoal, secondGoal]
            )
        }
        await calculationService.waitUntilSuspended()
        firstTransaction.amount = 80
        try context.save()
        calculationService.resume()

        do {
            _ = try await operation.value
            Issue.record("Expected source-drift validation to abort plan creation")
        } catch {
            #expect(error is PlanError)
        }

        #expect(saveGate.attempts == 0)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<MonthlyPlan>()).isEmpty)
    }

    @Test("Get-or-create returns plans only for active goals")
    func getOrCreateReturnsOnlyActiveGoalPlans() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let activeGoal = makeGoal(name: "Active", target: 100)
        let cancelledGoal = makeGoal(name: "Cancelled", target: 200)
        let finishedGoal = makeGoal(name: "Finished", target: 300)
        let deletedGoal = makeGoal(name: "Deleted", target: 400)
        cancelledGoal.lifecycleStatus = .cancelled
        finishedGoal.lifecycleStatus = .finished
        deletedGoal.lifecycleStatus = .deleted
        let goals = [activeGoal, cancelledGoal, finishedGoal, deletedGoal]
        let plans = goals.enumerated().map { index, goal in
            makePlan(goal: goal, required: Double((index + 1) * 100))
        }
        goals.forEach(context.insert)
        plans.forEach(context.insert)
        try context.save()
        let service = makePlanService(context: context)

        let returned = try await service.getOrCreatePlans(
            for: "2026-08",
            goals: goals
        )

        #expect(returned.map(\.goalId) == [activeGoal.id])
    }

    @Test("Planning view model excludes inactive plans from the published total")
    func planningViewModelDoesNotSumInactiveGoalPlans() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let activeGoal = makeGoal(name: "Active Total", target: 100)
        let cancelledGoal = makeGoal(name: "Cancelled Total", target: 900)
        cancelledGoal.lifecycleStatus = .cancelled
        let activePlan = makePlan(goal: activeGoal, required: 100)
        let cancelledPlan = makePlan(goal: cancelledGoal, required: 900)
        context.insert(activeGoal)
        context.insert(cancelledGoal)
        context.insert(activePlan)
        context.insert(cancelledPlan)
        try context.save()

        let settings = MonthlyPlanningSettings()
        let settingsSnapshot = ThirdSettingsSnapshot(settings)
        defer { settingsSnapshot.restore(to: settings) }
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        let rates = ThirdExchangeRateService()
        let planService = makePlanService(context: context)
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )

        await viewModel.loadMonthlyRequirements(for: "2026-08")

        #expect(viewModel.error == nil)
        #expect(viewModel.monthlyRequirements.map(\.goalId) == [activeGoal.id])
        #expect(viewModel.totalRequired == activePlan.effectiveAmount)
    }

    @Test("Cancelling a goal after planning prevents both plan and record execution")
    func cancelAfterPlanBeforeStartDoesNotExecute() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Cancel Before Start", target: 100)
        context.insert(goal)
        try context.save()
        let planService = makePlanService(context: context)
        let plans = try await planService.getOrCreatePlans(
            for: "2026-08",
            goals: [goal]
        )
        let plan = try #require(plans.first)

        goal.lifecycleStatus = .cancelled
        try context.save()

        try planService.startExecution(for: plans)
        #expect(plan.state == .draft)

        let executionService = ExecutionTrackingService(modelContext: context)
        do {
            _ = try executionService.startTracking(
                for: "2026-08",
                from: plans,
                goals: [goal]
            )
            Issue.record("Expected execution tracking to reject a cancelled goal")
        } catch {
            #expect(error is ExecutionTrackingService.ExecutionError)
        }
        #expect(try context.fetch(FetchDescriptor<MonthlyExecutionRecord>()).isEmpty)
    }

    @Test("Execution records contain exactly the active supplied goal membership")
    func executionTrackingFiltersInactiveMembership() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let activeGoal = makeGoal(name: "Tracked", target: 100)
        let cancelledGoal = makeGoal(name: "Not Tracked", target: 100)
        cancelledGoal.lifecycleStatus = .cancelled
        let activePlan = makePlan(goal: activeGoal, required: 100)
        let cancelledPlan = makePlan(goal: cancelledGoal, required: 100)
        context.insert(activeGoal)
        context.insert(cancelledGoal)
        context.insert(activePlan)
        context.insert(cancelledPlan)
        try context.save()

        let record = try ExecutionTrackingService(modelContext: context).startTracking(
            for: "2026-08",
            from: [activePlan, cancelledPlan],
            goals: [activeGoal, cancelledGoal]
        )

        #expect(Set(record.goalIds) == [activeGoal.id])
        #expect(record.snapshot?.goalSnapshots.map(\.goalId) == [activeGoal.id])
    }

    private func verifyPlanningMutationTransition(
        _ operation: ThirdPlanningMutationOperation
    ) throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Target \(operation)", target: 100)
        let plan = makePlan(goal: goal, required: operation == .prepare ? 0 : 100)
        if operation == .prepare || operation == .reset {
            plan.state = .executing
        }
        context.insert(goal)
        context.insert(plan)
        try context.save()

        let beforePlan = ThirdPlanSnapshot(plan)
        let beforeTarget = goal.targetAmount
        let beforeDeadline = goal.deadline

        let saveGate = ThirdSaveGate(context: context, shouldFail: true)
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: ThirdExchangeRateService(),
            accessGuard: ThirdAllowAllAccessGuard(),
            saveChanges: saveGate.save
        )
        let notifications = ThirdNotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in notifications.count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        do {
            try invokePlanningMutation(operation, service: service, plan: plan, goal: goal)
            Issue.record("Expected injected save failure for \(operation)")
        } catch {}

        context.processPendingChanges()
        #expect(ThirdPlanSnapshot(plan) == beforePlan)
        #expect(goal.targetAmount == beforeTarget)
        #expect(goal.deadline == beforeDeadline)
        if operation == .delete {
            #expect(
                context.deletedModelsArray.contains {
                    ($0 as? MonthlyPlan)?.id == plan.id
                } == false
            )
        }
        #expect(notifications.count == 0)

        saveGate.shouldFail = false
        try invokePlanningMutation(operation, service: service, plan: plan, goal: goal)
        #expect(saveGate.attempts == 2)
        #expect(notifications.count == 1)

        switch operation {
        case .markCompleted:
            #expect(plan.state == .completed)
            #expect(plan.isSkipped == false)
        case .markSkipped:
            #expect(plan.state == .completed)
            #expect(plan.isSkipped)
        case .delete:
            let remainingPlans = try ModelContext(container).fetch(
                FetchDescriptor<MonthlyPlan>()
            )
            #expect(
                remainingPlans.isEmpty,
                "Unexpected persisted plans: \(remainingPlans.map(\.id))"
            )
        case .prepare:
            #expect(plan.state == .draft)
            #expect(plan.isSkipped)
        case .reset:
            #expect(plan.state == .draft)
        case .reduceTarget:
            #expect(goal.targetAmount == 50)
        case .extendDeadline:
            #expect(goal.deadline > beforeDeadline)
        }
    }

    private func invokePlanningMutation(
        _ operation: ThirdPlanningMutationOperation,
        service: PlanningMutationService,
        plan: MonthlyPlan,
        goal: Goal
    ) throws {
        switch operation {
        case .markCompleted:
            try service.markPlanCompleted(plan)
        case .markSkipped:
            try service.markPlanSkipped(plan)
        case .delete:
            try service.deletePlan(plan)
        case .prepare:
            try service.preparePlansForExecution([plan])
        case .reset:
            try service.resetPlansToDraft([plan])
        case .reduceTarget:
            _ = try service.applyFeasibilitySuggestion(
                .reduceTarget(
                    goalId: goal.id,
                    goalName: goal.name,
                    to: 50,
                    currency: goal.currency
                ),
                goals: [goal]
            )
        case .extendDeadline:
            _ = try service.applyFeasibilitySuggestion(
                .extendDeadline(
                    goalId: goal.id,
                    goalName: goal.name,
                    byMonths: 1
                ),
                goals: [goal]
            )
        }
    }

    private func verifyMonthlyPlanTransition(
        _ operation: ThirdMonthlyPlanOperation
    ) async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Target \(operation)", target: 100)
        let plan = makePlan(goal: goal, required: 100)
        if operation == .complete {
            plan.state = .executing
        }
        if operation == .rollForward {
            plan.monthLabel = "2025-01"
        }
        context.insert(goal)
        context.insert(plan)
        try context.save()

        let before = ThirdPlanSnapshot(plan)
        let saveGate = ThirdSaveGate(context: context, shouldFail: true)
        let service = makePlanService(context: context, saveGate: saveGate)
        let notifications = ThirdNotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in notifications.count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        do {
            try await invokeMonthlyPlanMutation(operation, service: service, plan: plan)
            Issue.record("Expected injected save failure for \(operation)")
        } catch {}

        context.processPendingChanges()
        #expect(ThirdPlanSnapshot(plan) == before)
        if operation == .delete {
            #expect(
                context.deletedModelsArray.contains {
                    ($0 as? MonthlyPlan)?.id == plan.id
                } == false
            )
        }
        #expect(notifications.count == 0)

        saveGate.shouldFail = false
        try await invokeMonthlyPlanMutation(operation, service: service, plan: plan)
        #expect(saveGate.attempts == 2)
        #expect(notifications.count == 1)

        switch operation {
        case .rollForward:
            #expect(plan.monthLabel == "2026-08")
        case .toggle:
            #expect(plan.isProtected)
            #expect(plan.flexState == .protected)
        case .skip:
            #expect(plan.isSkipped)
            #expect(plan.flexState == .skipped)
        case .start:
            #expect(plan.state == .executing)
        case .complete:
            #expect(plan.state == .completed)
        case .delete:
            let remainingPlans = try ModelContext(container).fetch(
                FetchDescriptor<MonthlyPlan>()
            )
            #expect(
                remainingPlans.isEmpty,
                "Unexpected persisted plans: \(remainingPlans.map(\.id))"
            )
        }
    }

    private func invokeMonthlyPlanMutation(
        _ operation: ThirdMonthlyPlanOperation,
        service: MonthlyPlanService,
        plan: MonthlyPlan
    ) async throws {
        switch operation {
        case .rollForward:
            _ = try await service.rollForwardDraftPlans(to: "2026-08")
        case .toggle:
            try service.toggleProtection(for: plan)
        case .skip:
            try service.skipPlan(plan)
        case .start:
            try service.startExecution(for: [plan])
        case .complete:
            try service.completePlans(for: [plan])
        case .delete:
            try service.deletePlan(plan)
        }
    }

    private func makeBudgetHarness(
        goalCurrency: String = "USD",
        exchangeRate: Double = 1,
        planningMutationService: PlanningMutationServiceProtocol? = nil
    ) async throws -> ThirdBudgetHarness {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let settings = MonthlyPlanningSettings()
        let settingsSnapshot = ThirdSettingsSnapshot(settings)
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        settings.budgetCurrency = "USD"
        settings.budgetAppliedMonthLabel = nil
        settings.budgetAppliedSignature = nil

        let goal = TestHelpers.createGoal(
            name: "Budget Source",
            currency: goalCurrency,
            targetAmount: 100,
            currentTotal: 20,
            deadline: Date().addingTimeInterval(400 * 86_400)
        )
        insertGraph(for: goal, into: context)
        let allocation = try #require(goal.allocations?.first)
        let transaction = try #require(allocation.asset?.transactions?.first)
        let rates = ThirdExchangeRateService(rate: exchangeRate)
        let planService = makePlanService(context: context)
        let monthLabel = planService.currentMonthLabel()
        let plan = makePlan(goal: goal, required: 80, monthLabel: monthLabel)
        context.insert(plan)
        try context.saveWithRelationships()
        let budgetService = BudgetCalculatorService(
            exchangeRateService: rates,
            settings: settings
        )
        let mutation = planningMutationService
            ?? PlanningMutationService(
                modelContext: context,
                exchangeRateService: rates,
                accessGuard: ThirdAllowAllAccessGuard()
            )
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            budgetCalculatorService: budgetService,
            planningMutationService: mutation,
            settings: settings,
            configureObservers: false
        )
        await viewModel.loadMonthlyRequirements(for: monthLabel)
        await viewModel.previewBudget(amount: 1_000, currency: "USD")
        try await Task.sleep(nanoseconds: 450_000_000)
        _ = try #require(viewModel.budgetPreviewPlan)

        return ThirdBudgetHarness(
            context: context,
            settings: settings,
            settingsSnapshot: settingsSnapshot,
            goal: goal,
            allocation: allocation,
            transaction: transaction,
            plan: plan,
            planService: planService,
            rates: rates,
            budgetService: budgetService,
            viewModel: viewModel,
            monthLabel: monthLabel
        )
    }

    private func makeFlexHarness() async throws -> ThirdFlexHarness {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let settings = MonthlyPlanningSettings()
        let settingsSnapshot = ThirdSettingsSnapshot(settings)
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        let goal = makeGoal(name: "Flex", target: 100)
        let rates = ThirdExchangeRateService()
        let saveGate = ThirdSaveGate(context: context, shouldFail: false)
        let planService = makePlanService(context: context, saveGate: saveGate)
        let monthLabel = planService.currentMonthLabel()
        let plan = makePlan(goal: goal, required: 100, monthLabel: monthLabel)
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let viewModel = MonthlyPlanningViewModel(
            modelContext: context,
            planService: planService,
            exchangeRateService: rates,
            settings: settings,
            configureObservers: false
        )
        await viewModel.loadMonthlyRequirements(for: monthLabel)
        saveGate.attempts = 0

        return ThirdFlexHarness(
            context: context,
            settings: settings,
            settingsSnapshot: settingsSnapshot,
            goal: goal,
            plan: plan,
            planService: planService,
            rates: rates,
            saveGate: saveGate,
            viewModel: viewModel,
            monthLabel: monthLabel
        )
    }

    private func makePlanService(
        context: ModelContext,
        saveGate: ThirdSaveGate? = nil
    ) -> MonthlyPlanService {
        MonthlyPlanService(
            modelContext: context,
            goalCalculationService: GoalCalculationService(
                exchangeRateService: ThirdExchangeRateService(),
                tatumService: ThirdTatumService(),
                modelContext: context
            ),
            saveChanges: saveGate?.save
        )
    }

    private func makeGoal(name: String, target: Double) -> Goal {
        Goal(
            name: name,
            currency: "USD",
            targetAmount: target,
            deadline: Date().addingTimeInterval(86_400)
        )
    }

    private func makePlan(
        goal: Goal,
        required: Double,
        monthLabel: String = "2026-08"
    ) -> MonthlyPlan {
        MonthlyPlan(
            goalId: goal.id,
            monthLabel: monthLabel,
            requiredMonthly: required,
            remainingAmount: goal.targetAmount,
            monthsRemaining: 1,
            currency: goal.currency
        )
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
}

private enum ThirdPlanningMutationOperation: String, CaseIterable, CustomStringConvertible {
    case markCompleted
    case markSkipped
    case delete
    case prepare
    case reset
    case reduceTarget
    case extendDeadline

    var description: String { rawValue }
}

private enum ThirdMonthlyPlanOperation: String, CaseIterable, CustomStringConvertible {
    case rollForward
    case toggle
    case skip
    case start
    case complete
    case delete

    var description: String { rawValue }
}

private enum ThirdSourceChange: String, CaseIterable, CustomStringConvertible {
    case target
    case deadline
    case allocation
    case balance

    var description: String { rawValue }
}

private enum ThirdBudgetEdit: CaseIterable {
    case amount
    case currency
}

@MainActor
private final class ThirdSaveGate {
    let context: ModelContext
    var shouldFail: Bool
    var attempts = 0

    init(context: ModelContext, shouldFail: Bool) {
        self.context = context
        self.shouldFail = shouldFail
    }

    func save() throws {
        attempts += 1
        if shouldFail {
            throw ThirdInjectedError.saveFailed
        }
        try context.save()
    }
}

private enum ThirdInjectedError: Error {
    case saveFailed
}

@MainActor
private final class ThirdExchangeRateService: ExchangeRateServiceProtocol {
    var rate: Double

    init(rate: Double = 1) {
        self.rate = rate
    }

    func fetchRate(from: String, to: String) async throws -> Double { rate }
    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

@MainActor
private final class ThirdTatumService: TatumServiceProtocol {
    var supportedChains: [TatumChain] { [] }
    func predictChain(for symbol: String) -> TatumChain? { nil }
    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double { 0 }
    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] { [] }
    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
}

@MainActor
private final class ThirdSuspendingGoalCalculationService: GoalCalculationService {
    private let suspendOnGoalID: UUID
    private var isSuspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(suspendOnGoalID: UUID) {
        self.suspendOnGoalID = suspendOnGoalID
        super.init(
            exchangeRateService: ThirdExchangeRateService(),
            tatumService: ThirdTatumService()
        )
    }

    override func getCurrentTotalResult(for goal: Goal) async -> GoalCurrentTotalResult {
        if goal.id == suspendOnGoalID {
            isSuspended = true
            suspensionWaiter?.resume()
            suspensionWaiter = nil
            await withCheckedContinuation { continuation in
                resumeContinuation = continuation
            }
        }
        return GoalCurrentTotalResult(total: goal.manualTotal, error: nil)
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiter = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
private final class ThirdSuspendingPlanningMutationService:
    PlanningMutationServiceProtocol
{
    private var isSuspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private(set) var didCommit = false

    func markPlanCompleted(_ plan: MonthlyPlan) throws {}
    func markPlanSkipped(_ plan: MonthlyPlan) throws {}
    func deletePlan(_ plan: MonthlyPlan) throws {}
    func preparePlansForExecution(_ plans: [MonthlyPlan]) throws {}
    func resetPlansToDraft(_ plans: [MonthlyPlan]) throws {}

    func applyFeasibilitySuggestion(
        _ suggestion: FeasibilitySuggestion,
        goals: [Goal]
    ) throws -> Bool {
        false
    }

    func applyBudgetPlan(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan],
        budgetCurrency: String,
        validateBeforeCommit: @MainActor () -> Bool
    ) async throws {
        isSuspended = true
        suspensionWaiter?.resume()
        suspensionWaiter = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        didCommit = validateBeforeCommit()
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiter = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
private final class ThirdAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

private final class ThirdNotificationCounter: @unchecked Sendable {
    var count = 0
}

private struct ThirdPlanSnapshot: Equatable {
    let monthLabel: String
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let lastCalculated: Date
    let stateRawValue: String
    let flexStateRawValue: String
    let customAmount: Double?
    let isProtected: Bool
    let isSkipped: Bool
    let lastModifiedDate: Date

    init(_ plan: MonthlyPlan) {
        monthLabel = plan.monthLabel
        requiredMonthly = plan.requiredMonthly
        remainingAmount = plan.remainingAmount
        monthsRemaining = plan.monthsRemaining
        currency = plan.currency
        statusRawValue = plan.statusRawValue
        lastCalculated = plan.lastCalculated
        stateRawValue = plan.stateRawValue
        flexStateRawValue = plan.flexStateRawValue
        customAmount = plan.customAmount
        isProtected = plan.isProtected
        isSkipped = plan.isSkipped
        lastModifiedDate = plan.lastModifiedDate
    }
}

@MainActor
private struct ThirdSettingsSnapshot {
    let displayCurrency: String
    let paymentDay: Int
    let monthlyBudget: Double?
    let budgetCurrency: String
    let budgetAppliedMonthLabel: String?
    let budgetAppliedSignature: String?

    init(_ settings: MonthlyPlanningSettings) {
        displayCurrency = settings.displayCurrency
        paymentDay = settings.paymentDay
        monthlyBudget = settings.monthlyBudget
        budgetCurrency = settings.budgetCurrency
        budgetAppliedMonthLabel = settings.budgetAppliedMonthLabel
        budgetAppliedSignature = settings.budgetAppliedSignature
    }

    func restore(to settings: MonthlyPlanningSettings) {
        settings.displayCurrency = displayCurrency
        settings.paymentDay = paymentDay
        settings.monthlyBudget = monthlyBudget
        settings.budgetCurrency = budgetCurrency
        settings.budgetAppliedMonthLabel = budgetAppliedMonthLabel
        settings.budgetAppliedSignature = budgetAppliedSignature
    }
}

@MainActor
private struct ThirdBudgetHarness {
    let context: ModelContext
    let settings: MonthlyPlanningSettings
    let settingsSnapshot: ThirdSettingsSnapshot
    let goal: Goal
    let allocation: AssetAllocation
    let transaction: Transaction
    let plan: MonthlyPlan
    let planService: MonthlyPlanService
    let rates: ThirdExchangeRateService
    let budgetService: BudgetCalculatorService
    let viewModel: MonthlyPlanningViewModel
    let monthLabel: String

    func restoreSettings() {
        settingsSnapshot.restore(to: settings)
    }
}

@MainActor
private struct ThirdFlexHarness {
    let context: ModelContext
    let settings: MonthlyPlanningSettings
    let settingsSnapshot: ThirdSettingsSnapshot
    let goal: Goal
    let plan: MonthlyPlan
    let planService: MonthlyPlanService
    let rates: ThirdExchangeRateService
    let saveGate: ThirdSaveGate
    let viewModel: MonthlyPlanningViewModel
    let monthLabel: String

    func restoreSettings() {
        settingsSnapshot.restore(to: settings)
    }
}

private struct ThirdFlexDefaultsSnapshot {
    static let protectedKey = "MonthlyPlanning.ProtectedGoals"
    static let skippedKey = "MonthlyPlanning.SkippedGoals"
    static let adjustmentKey = "MonthlyPlanning.FlexAdjustment"

    private let protectedGoals = UserDefaults.standard.object(forKey: protectedKey)
    private let skippedGoals = UserDefaults.standard.object(forKey: skippedKey)
    private let adjustment = UserDefaults.standard.object(forKey: adjustmentKey)

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.protectedKey)
        UserDefaults.standard.removeObject(forKey: Self.skippedKey)
        UserDefaults.standard.removeObject(forKey: Self.adjustmentKey)
    }

    func restore() {
        restore(protectedGoals, forKey: Self.protectedKey)
        restore(skippedGoals, forKey: Self.skippedKey)
        restore(adjustment, forKey: Self.adjustmentKey)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
