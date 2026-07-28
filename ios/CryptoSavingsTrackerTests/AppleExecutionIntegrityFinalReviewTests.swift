import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@Suite("Apple execution integrity final review", .serialized)
@MainActor
struct AppleExecutionIntegrityFinalReviewTests {
    @Test("Roll-forward coalesces every stale draft per active goal and excludes inactive goals")
    func rollForwardUsesCanonicalActiveMembership() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let active = makeGoal(name: "Active")
        let cancelled = makeGoal(name: "Cancelled")
        cancelled.lifecycleStatus = .cancelled

        let june = makePlan(goal: active, month: "2026-06", customAmount: 60)
        june.lastModifiedDate = Date(timeIntervalSince1970: 100)
        let july = makePlan(goal: active, month: "2026-07", customAmount: 70)
        july.lastModifiedDate = Date(timeIntervalSince1970: 200)
        let inactiveJuly = makePlan(goal: cancelled, month: "2026-07", customAmount: 999)

        [active, cancelled].forEach(context.insert)
        [june, july, inactiveJuly].forEach(context.insert)
        try context.save()

        let service = makePlanService(context: context)
        #expect(try await service.rollForwardDraftPlans(to: "2026-08"))

        let target = try service.fetchPlans(for: "2026-08")
        #expect(target.count == 1)
        #expect(target.first?.goalId == active.id)
        #expect(target.first?.customAmount == 70)
        #expect(target.allSatisfy { $0.goalId != cancelled.id })
    }

    @Test("Planning month contract uses UTC storage identity and starts future-month payments in that month")
    func planningMonthContractIsExplicitAtBoundary() throws {
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-31T23:30:00Z")
        )
        let nicosia = try #require(TimeZone(identifier: "Asia/Nicosia"))

        #expect(PlanningMonthContract.storageLabel(for: now) == "2026-07")
        #expect(
            PlanningMonthContract.displayLabel(for: now, timeZone: nicosia) == "2026-08",
            "The local display month can differ, but it must not change the UTC storage identity."
        )

        let reference = try PlanningMonthContract.referenceDate(
            for: "2026-08",
            now: now
        )
        #expect(PlanningMonthContract.storageLabel(for: reference) == "2026-08")

        let deadline = try #require(
            ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")
        )
        #expect(
            try PlanningMonthContract.paymentPeriodsRemaining(
                in: "2026-08",
                paymentDay: 28,
                deadline: deadline,
                now: now
            ) == 2
        )
    }

    @Test("Payment periods include a payment scheduled exactly on the deadline")
    func paymentPeriodsIncludeExactDeadline() throws {
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
        )
        let deadline = try #require(
            ISO8601DateFormatter().date(from: "2026-09-28T00:00:00Z")
        )

        #expect(
            try PlanningMonthContract.paymentPeriodsRemaining(
                in: "2026-08",
                paymentDay: 28,
                deadline: deadline,
                now: now
            ) == 2
        )
    }

    @Test("Future-month day-one payment is included while an elapsed current-month payment is skipped")
    func dayOnePaymentDistinguishesFutureAndCurrentMonth() throws {
        let julyNow = try #require(
            ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
        )
        let augustNow = try #require(
            ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")
        )

        let futurePayment = try PlanningMonthContract.nextPaymentDate(
            in: "2026-08",
            paymentDay: 1,
            now: julyNow
        )
        #expect(
            PlanningMonthContract.storageLabel(for: futurePayment) == "2026-08"
        )

        let elapsedCurrentPayment = try PlanningMonthContract.nextPaymentDate(
            in: "2026-08",
            paymentDay: 1,
            now: augustNow
        )
        #expect(
            PlanningMonthContract.storageLabel(for: elapsedCurrentPayment) == "2026-09"
        )
    }

    @Test("Current planning service counts UTC payment periods inclusively at a local month boundary")
    func currentPlanningServiceUsesUtcPaymentPeriods() async throws {
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-31T23:30:00Z")
        )
        let deadline = try #require(
            ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")
        )
        let settings = MonthlyPlanningSettings.shared
        let originalPaymentDay = settings.paymentDay
        defer { settings.paymentDay = originalPaymentDay }
        settings.paymentDay = 1

        let service = MonthlyPlanningService(
            exchangeRateService: MockExchangeRateService(),
            now: { now }
        )
        let goal = Goal(
            name: "UTC current plan",
            currency: "USD",
            targetAmount: 200,
            deadline: deadline
        )
        let requirement = try #require(
            await service.getMonthlyRequirement(for: goal)
        )

        #expect(requirement.monthsRemaining == 2)
        #expect(requirement.requiredMonthly == 100)
    }

    @Test("Planning settings derive the next payment from the UTC storage month")
    func planningSettingsNextPaymentUsesUtcStorageMonth() throws {
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-31T23:30:00Z")
        )
        let expected = try #require(
            ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
        )
        let settings = MonthlyPlanningSettings()
        settings.paymentDay = 1

        #expect(settings.nextPaymentDate(relativeTo: now) == expected)
        #expect(settings.daysUntilPayment(relativeTo: now) == 1)
        #expect(
            settings.nextPaymentFormatted(
                relativeTo: now,
                locale: Locale(identifier: "en_US_POSIX")
            ) == "Aug 1, 2026"
        )
    }

    @Test("Monthly plan requirements use the selected planning month, not wall-clock month")
    func planRequirementUsesSelectedMonth() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
        )
        let deadline = try #require(
            ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")
        )
        let settings = MonthlyPlanningSettings.shared
        let originalPaymentDay = settings.paymentDay
        defer { settings.paymentDay = originalPaymentDay }
        settings.paymentDay = 28

        let goal = Goal(
            name: "Future plan",
            currency: "USD",
            targetAmount: 200,
            deadline: deadline
        )
        context.insert(goal)
        try context.save()

        let service = makePlanService(context: context, now: { now })
        let plans = try await service.getOrCreatePlans(for: "2026-08", goals: [goal])

        #expect(plans.count == 1)
        #expect(plans.first?.monthsRemaining == 2)
        #expect(plans.first?.requiredMonthly == 100)
    }

    @Test("Budget schedule uses the selected planning month for its first payment")
    func budgetScheduleUsesSelectedMonth() async throws {
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-27T12:00:00Z")
        )
        let deadline = try #require(
            ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")
        )
        let settings = MonthlyPlanningSettings()
        settings.paymentDay = 28
        let service = BudgetCalculatorService(
            exchangeRateService: MockExchangeRateService(),
            settings: settings,
            now: { now }
        )
        let goal = Goal(
            name: "August budget",
            currency: "USD",
            targetAmount: 200,
            deadline: deadline
        )

        let plan = await service.generateSchedule(
            goals: [goal],
            budget: 100,
            currency: "USD",
            planningMonthLabel: "2026-08"
        )

        let firstPayment = try #require(plan.schedule.first)
        #expect(PlanningMonthContract.storageLabel(for: firstPayment.paymentDate) == "2026-08")
        #expect(
            Calendar(identifier: .gregorian).dateComponents(
                in: PlanningMonthContract.storageTimeZone,
                from: firstPayment.paymentDate
            ).day == 28
        )
    }

    @Test("Start persists plan state and execution record in one operation")
    func startFailureRestoresPlanAndDiscardsRecord() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Atomic start")
        let plan = makePlan(goal: goal, month: "2026-08")
        context.insert(goal)
        context.insert(plan)
        try context.save()

        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService(),
            saveChanges: { throw IntegrityTestError.injected }
        )

        #expect(throws: IntegrityTestError.self) {
            _ = try service.startTracking(
                for: "2026-08",
                from: [plan],
                goals: [goal]
            )
        }
        context.processPendingChanges()

        #expect(plan.state == .draft)
        #expect(try context.fetch(FetchDescriptor<MonthlyExecutionRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExecutionSnapshot>()).isEmpty)
    }

    @Test("Start rejects invalid plans without normalizing or saving them")
    func startRejectsInvalidPlansWithoutMutation() throws {
        do {
            let container = try TestContainer.create()
            let context = ModelContext(container)
            let goal = makeGoal(name: "Already completed")
            let plan = makePlan(goal: goal, month: "2026-08")
            context.insert(goal)
            context.insert(plan)
            try context.save()
            plan.state = .completed
            let originalModifiedAt = plan.lastModifiedDate
            var saveCalls = 0
            let service = ExecutionTrackingService(
                modelContext: context,
                exchangeRateService: MockExchangeRateService(),
                saveChanges: {
                    saveCalls += 1
                    try context.save()
                }
            )

            #expect(throws: ExecutionTrackingService.ExecutionError.self) {
                _ = try service.startTracking(
                    for: "2026-08",
                    from: [plan],
                    goals: [goal]
                )
            }

            #expect(saveCalls == 0)
            #expect(plan.state == .completed)
            #expect(plan.isSkipped == false)
            #expect(plan.lastModifiedDate == originalModifiedAt)
            #expect(plan.executionRecord == nil)
            #expect(try context.fetch(FetchDescriptor<MonthlyExecutionRecord>()).isEmpty)
        }

        do {
            let container = try TestContainer.create()
            let context = ModelContext(container)
            let goal = makeGoal(name: "Explicit skip required")
            let plan = makePlan(
                goal: goal,
                month: "2026-08",
                required: 0
            )
            context.insert(goal)
            context.insert(plan)
            try context.save()
            let originalModifiedAt = plan.lastModifiedDate
            var saveCalls = 0
            let service = ExecutionTrackingService(
                modelContext: context,
                exchangeRateService: MockExchangeRateService(),
                saveChanges: {
                    saveCalls += 1
                    try context.save()
                }
            )

            #expect(throws: ExecutionTrackingService.ExecutionError.self) {
                _ = try service.startTracking(
                    for: "2026-08",
                    from: [plan],
                    goals: [goal]
                )
            }

            #expect(saveCalls == 0)
            #expect(plan.state == .draft)
            #expect(plan.isSkipped == false)
            #expect(plan.lastModifiedDate == originalModifiedAt)
            #expect(plan.executionRecord == nil)
            #expect(try context.fetch(FetchDescriptor<MonthlyExecutionRecord>()).isEmpty)
        }
    }

    @Test("Undo start restores both record and plans when persistence fails")
    func undoStartFailureIsAtomic() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Atomic undo")
        let plan = makePlan(goal: goal, month: "2026-08")
        context.insert(goal)
        context.insert(plan)
        try context.save()

        let successful = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try successful.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        let failing = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService(),
            saveChanges: { throw IntegrityTestError.injected }
        )

        #expect(throws: IntegrityTestError.self) {
            try failing.undoStartTracking(record)
        }

        #expect(record.status == .executing)
        #expect(plan.state == .executing)
    }

    @Test("Missing execution FX fails the calculation instead of dropping the contribution")
    func contributionCalculationFailsClosedWhenRateIsMissing() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let goal = Goal(
            name: "USD goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: start.addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        let transaction = Transaction(
            amount: 1,
            asset: asset,
            date: start.addingTimeInterval(60)
        )
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        asset.transactions = [transaction]
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(transaction)
        context.insert(
            AllocationHistory(asset: asset, goal: goal, amount: 1, timestamp: start)
        )
        let record = MonthlyExecutionRecord(monthLabel: "2026-08", goalIds: [goal.id])
        record.statusRawValue = MonthlyExecutionRecord.ExecutionStatus.executing.rawValue
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: AlwaysFailingRateService()
        )

        await #expect(throws: ExecutionProgressCalculator.CalculationError.self) {
            _ = try await calculator.contributionTotalsInGoalCurrency(
                for: record,
                end: start.addingTimeInterval(120)
            )
        }
    }

    @Test("Execution view model exposes unavailable progress instead of stale zero-like totals")
    func executionViewModelFailsClosedWhenRateIsMissing() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Unavailable progress")
        let plan = makePlan(goal: goal, month: "2026-08")
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let successful = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try successful.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        let startedAt = try #require(record.startedAt)
        let transaction = Transaction(
            amount: 1,
            asset: asset,
            date: startedAt.addingTimeInterval(60)
        )
        asset.transactions = [transaction]
        context.insert(transaction)
        try context.save()

        let failing = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: AlwaysFailingRateService(),
            now: { startedAt.addingTimeInterval(120) }
        )
        let viewModel = MonthlyExecutionViewModel(
            modelContext: context,
            executionService: failing
        )
        viewModel.contributedTotals = [goal.id: 99]
        viewModel.overallProgress = 99

        await viewModel.loadCurrentMonth()

        #expect(viewModel.isProgressAvailable == false)
        #expect(viewModel.contributedTotals.isEmpty)
        #expect(viewModel.overallProgress == 0)
        #expect(viewModel.fulfillmentStatus.isEmpty)
        #expect(viewModel.displayTotalPlanned == nil)
        #expect(viewModel.displayTotalRemaining == nil)
    }

    @Test("Active execution UI excludes goals retired after execution started")
    func executionViewModelUsesCanonicalActiveMembership() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let kept = makeGoal(name: "Kept in active execution")
        let retired = makeGoal(name: "Retired during execution")
        let keptPlan = makePlan(goal: kept, month: "2026-08")
        let retiredPlan = makePlan(goal: retired, month: "2026-08")
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: kept, amount: 100)
        asset.allocations = [allocation]
        kept.allocations = [allocation]
        [kept, retired].forEach(context.insert)
        [keptPlan, retiredPlan].forEach(context.insert)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService(),
            now: { currentTime }
        )
        let record = try service.startTracking(
            for: "2026-08",
            from: [keptPlan, retiredPlan],
            goals: [kept, retired]
        )
        let startedAt = try #require(record.startedAt)
        let transaction = Transaction(
            amount: 100,
            asset: asset,
            date: startedAt.addingTimeInterval(60)
        )
        asset.transactions = [transaction]
        context.insert(transaction)
        currentTime = startedAt.addingTimeInterval(120)

        retired.lifecycleStatus = .cancelled
        try context.save()

        let serviceProgress = try await service.calculateProgress(for: record)
        #expect(serviceProgress == 100)

        let viewModel = MonthlyExecutionViewModel(
            modelContext: context,
            executionService: service
        )
        await viewModel.loadCurrentMonth()

        #expect(viewModel.displayGoalSnapshots.map(\.goalId) == [kept.id])
        #expect(viewModel.displayGoalCount == 1)
        #expect(viewModel.overallProgress == 100)
        #expect(viewModel.fulfillmentStatus.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) == [kept.id])
    }

    @Test("Execution start replaces a same-count but incorrect allocation baseline")
    func startRepairsIncorrectAllocationBaseline() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = makeGoal(name: "Exact baseline")
        let plan = makePlan(goal: goal, month: "2026-08")
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 50)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        let incorrect = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 1,
            timestamp: start
        )
        incorrect.monthLabel = "2026-08"

        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        context.insert(incorrect)
        try context.save()

        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService(),
            now: { start }
        )
        _ = try service.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )

        let baseline = try context.fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.monthLabel == "2026-08" && $0.timestamp == start }
        #expect(baseline.count == 1)
        #expect(baseline.first?.assetId == asset.id)
        #expect(baseline.first?.goalId == goal.id)
        #expect(baseline.first?.amount == 50)
    }

    @Test("Mixed-currency overall progress averages per-goal completion ratios")
    func mixedCurrencyProgressIsDimensionless() throws {
        let usdGoal = makeGoal(name: "USD", currency: "USD")
        let btcGoal = makeGoal(name: "BTC", currency: "BTC")
        let usdPlan = makePlan(goal: usdGoal, month: "2026-08", required: 100)
        let btcPlan = makePlan(goal: btcGoal, month: "2026-08", required: 1)
        let snapshot = try ExecutionSnapshot.create(
            from: [usdPlan, btcPlan],
            goals: [usdGoal, btcGoal]
        )

        #expect(snapshot.totalPlanned == 0, "A mixed-currency snapshot must not expose a raw summed amount.")
        #expect(
            snapshot.overallCompletion(
                with: [usdGoal.id: 100, btcGoal.id: 0]
            ) == 50
        )
        #expect(
            ExecutionAmountFormatter.string(amount: 1, currency: "BTC")
                .contains("$") == false
        )
    }

    @Test("Completion excludes a goal retired after start")
    func completionDoesNotResurrectRetiredGoal() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let kept = makeGoal(name: "Kept")
        let retired = makeGoal(name: "Retired")
        let keptPlan = makePlan(goal: kept, month: "2026-08")
        let retiredPlan = makePlan(goal: retired, month: "2026-08")
        [kept, retired].forEach(context.insert)
        [keptPlan, retiredPlan].forEach(context.insert)
        try context.save()

        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try service.startTracking(
            for: "2026-08",
            from: [keptPlan, retiredPlan],
            goals: [kept, retired]
        )

        retired.lifecycleStatus = .cancelled
        try context.save()

        try await service.markComplete(record)

        #expect(record.goalIds == [kept.id])
        #expect(record.snapshot?.goalSnapshots.map(\.goalId) == [kept.id])
        #expect(record.completedExecution?.goalSnapshots.map(\.goalId) == [kept.id])
        #expect(keptPlan.state == .completed)
        #expect(retiredPlan.state != .completed)
    }

    @Test("Completion rolls back record, plans, snapshot, and event when event creation fails")
    func completionEventFailureIsAtomic() async throws {
        let harness = try makeExecutingHarness()
        let service = ExecutionTrackingService(
            modelContext: harness.context,
            exchangeRateService: MockExchangeRateService(),
            makeCompletionEvent: { _, _, _, _ in
                throw IntegrityTestError.injected
            }
        )

        await #expect(throws: IntegrityTestError.self) {
            try await service.markComplete(harness.record)
        }
        harness.context.processPendingChanges()

        #expect(harness.record.status == .executing)
        #expect(harness.record.completedAt == nil)
        #expect(harness.record.completedExecution == nil)
        #expect(harness.plan.state == .executing)
        #expect(try harness.context.fetch(FetchDescriptor<CompletedExecution>()).isEmpty)
        #expect(try harness.context.fetch(FetchDescriptor<CompletionEvent>()).isEmpty)
    }

    @Test("Completion leaves execution open when a required FX rate is unavailable")
    func completionFailsClosedWhenRateIsMissing() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "USD completion")
        let plan = makePlan(goal: goal, month: "2026-08")
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let successful = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try successful.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        let startedAt = try #require(record.startedAt)
        let transaction = Transaction(
            amount: 1,
            asset: asset,
            date: startedAt.addingTimeInterval(60)
        )
        asset.transactions = [transaction]
        context.insert(transaction)
        try context.save()

        let failing = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: AlwaysFailingRateService(),
            now: { startedAt.addingTimeInterval(120) }
        )

        await #expect(
            throws: ExecutionProgressCalculator.CalculationError.self
        ) {
            try await failing.markComplete(record)
        }

        #expect(record.status == .executing)
        #expect(record.completedAt == nil)
        #expect(record.completedExecution == nil)
        #expect(plan.state == .executing)
        #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).isEmpty)
    }

    @Test("Completion rejects active membership changed while FX is loading")
    func completionRejectsMembershipChangedDuringRateFetch() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Retired during completion")
        let plan = makePlan(goal: goal, month: "2026-08")
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(plan)
        context.insert(asset)
        context.insert(allocation)
        try context.save()

        let successful = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try successful.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        let startedAt = try #require(record.startedAt)
        let transaction = Transaction(
            amount: 1,
            asset: asset,
            date: startedAt.addingTimeInterval(60)
        )
        asset.transactions = [transaction]
        context.insert(transaction)
        try context.save()

        let changingRateService = MembershipChangingRateService {
            goal.lifecycleStatus = .cancelled
            try context.save()
        }
        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: changingRateService,
            now: { startedAt.addingTimeInterval(120) }
        )

        await #expect(throws: ExecutionTrackingService.ExecutionError.self) {
            try await service.markComplete(record)
        }

        #expect(record.status == .executing)
        #expect(record.goalIds == [goal.id])
        #expect(record.snapshot?.goalSnapshots.map(\.goalId) == [goal.id])
        #expect(plan.state == .executing)
        #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).isEmpty)
    }

    @Test("Completion and undo completion restore every in-memory mutation when save fails")
    func completionSaveAndUndoFailuresAreAtomic() async throws {
        do {
            let harness = try makeExecutingHarness()
            let failing = ExecutionTrackingService(
                modelContext: harness.context,
                exchangeRateService: MockExchangeRateService(),
                saveChanges: { throw IntegrityTestError.injected }
            )

            await #expect(throws: IntegrityTestError.self) {
                try await failing.markComplete(harness.record)
            }

            #expect(harness.record.status == .executing)
            #expect(harness.record.completedAt == nil)
            #expect(harness.record.completedExecution == nil)
            #expect(harness.plan.state == .executing)
        }

        do {
            let harness = try makeExecutingHarness()
            let successful = ExecutionTrackingService(
                modelContext: harness.context,
                exchangeRateService: MockExchangeRateService()
            )
            try await successful.markComplete(harness.record)
            let event = try #require(harness.record.completionEvents?.first)
            let failing = ExecutionTrackingService(
                modelContext: harness.context,
                exchangeRateService: MockExchangeRateService(),
                saveChanges: { throw IntegrityTestError.injected }
            )

            #expect(throws: IntegrityTestError.self) {
                try failing.undoCompletion(harness.record)
            }

            #expect(harness.record.status == .closed)
            #expect(harness.plan.state == .completed)
            #expect(event.undoneAt == nil)
            #expect(event.undoReason == nil)
        }
    }

    private func makeGoal(
        name: String,
        currency: String = "USD"
    ) -> Goal {
        Goal(
            name: name,
            currency: currency,
            targetAmount: currency == "BTC" ? 1 : 100,
            deadline: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makePlan(
        goal: Goal,
        month: String,
        required: Double = 100,
        customAmount: Double? = nil
    ) -> MonthlyPlan {
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: month,
            requiredMonthly: required,
            remainingAmount: required,
            monthsRemaining: 1,
            currency: goal.currency
        )
        plan.customAmount = customAmount
        return plan
    }

    private func makePlanService(
        context: ModelContext,
        now: @escaping () -> Date = Date.init
    ) -> MonthlyPlanService {
        MonthlyPlanService(
            modelContext: context,
            goalCalculationService: GoalCalculationService(
                exchangeRateService: MockExchangeRateService(),
                tatumService: IntegrityTatumService(),
                modelContext: context
            ),
            now: now
        )
    }

    private func makeExecutingHarness() throws -> (
        context: ModelContext,
        goal: Goal,
        plan: MonthlyPlan,
        record: MonthlyExecutionRecord
    ) {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Completion")
        let plan = makePlan(goal: goal, month: "2026-08")
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let service = ExecutionTrackingService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let record = try service.startTracking(
            for: "2026-08",
            from: [plan],
            goals: [goal]
        )
        return (context, goal, plan, record)
    }
}

private enum IntegrityTestError: Error {
    case injected
}

private final class AlwaysFailingRateService: ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String) async throws -> Double {
        throw IntegrityTestError.injected
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

private final class MembershipChangingRateService: ExchangeRateServiceProtocol {
    private let changeMembership: @MainActor () throws -> Void

    init(changeMembership: @escaping @MainActor () throws -> Void) {
        self.changeMembership = changeMembership
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        try await MainActor.run {
            try changeMembership()
        }
        return 1
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

private final class IntegrityTatumService: TatumServiceProtocol {
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

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
}
