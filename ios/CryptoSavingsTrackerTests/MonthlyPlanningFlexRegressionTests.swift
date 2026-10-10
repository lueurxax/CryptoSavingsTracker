import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct MonthlyPlanningFlexRegressionTests {
    @Test("Planning header uses the saved effective amount once")
    func adjustedTotalDoesNotReapplyFlex() throws {
        let container = try TestContainer.create()
        let viewModel = MonthlyPlanningViewModel(modelContext: ModelContext(container))
        let goalID = UUID()
        viewModel.monthlyRequirements = [requirement(goalID: goalID, amount: 50, currency: "USD")]
        viewModel.totalRequired = 50
        viewModel.flexAdjustment = 0.5
        viewModel.protectedGoalIds = []
        viewModel.skippedGoalIds = []

        #expect(viewModel.adjustedTotal == 50)
    }

    @Test("Planning header preserves currency conversion for protected and flexible goals")
    func adjustedTotalPreservesConvertedEffectiveTotal() throws {
        let container = try TestContainer.create()
        let viewModel = MonthlyPlanningViewModel(modelContext: ModelContext(container))
        let flexibleID = UUID()
        let protectedID = UUID()
        let skippedID = UUID()
        viewModel.monthlyRequirements = [
            requirement(goalID: flexibleID, amount: 50, currency: "USD"),
            requirement(goalID: protectedID, amount: 100, currency: "EUR"),
            requirement(goalID: skippedID, amount: 0, currency: "GBP")
        ]
        // 50 USD + 100 EUR at 1.2 USD/EUR + zero for the skipped goal.
        viewModel.displayCurrency = "USD"
        viewModel.totalRequired = 170
        viewModel.flexAdjustment = 0.5
        viewModel.protectedGoalIds = [protectedID]
        viewModel.skippedGoalIds = [skippedID]

        #expect(viewModel.adjustedTotal == 170)
    }

    @Test("Unskip restores a flexible plan and persists its contribution")
    func unskipFlexiblePlanRestoresAmount() async throws {
        let fixture = try makePlanFixture()
        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [], skippedGoalIds: [fixture.plan.goalId]
        )
        #expect(fixture.plan.effectiveAmount == 0)

        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [], skippedGoalIds: []
        )

        #expect(fixture.plan.isSkipped == false)
        #expect(fixture.plan.isProtected == false)
        #expect(fixture.plan.flexState == .flexible)
        #expect(fixture.plan.effectiveAmount == 50)
        let reloaded = try ModelContext(fixture.container).fetch(FetchDescriptor<MonthlyPlan>())
        #expect(reloaded.first?.isSkipped == false)
        #expect(reloaded.first?.effectiveAmount == 50)
    }

    @Test("Unskip into protection preserves a custom amount")
    func unskipProtectedPlanPreservesOverride() async throws {
        let fixture = try makePlanFixture()
        fixture.plan.setCustomAmount(60)
        fixture.plan.skipThisMonth()

        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [fixture.plan.goalId], skippedGoalIds: []
        )

        #expect(fixture.plan.isSkipped == false)
        #expect(fixture.plan.isProtected == true)
        #expect(fixture.plan.flexState == .protected)
        #expect(fixture.plan.effectiveAmount == 60)
    }

    @Test("Protection can be removed after skipping without inconsistent flags")
    func protectedToSkippedToFlexibleClearsProtection() async throws {
        let fixture = try makePlanFixture()
        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [fixture.plan.goalId], skippedGoalIds: []
        )
        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [], skippedGoalIds: [fixture.plan.goalId]
        )
        #expect(fixture.plan.isProtected == false)
        #expect(fixture.plan.flexState == .skipped)

        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 1, protectedGoalIds: [], skippedGoalIds: []
        )

        #expect(fixture.plan.isSkipped == false)
        #expect(fixture.plan.isProtected == false)
        #expect(fixture.plan.flexState == .flexible)
        #expect(fixture.plan.effectiveAmount == 100)
    }

    @Test("Repeated flex adjustments use the base requirement after unskip")
    func repeatedFlexDoesNotCompound() async throws {
        let fixture = try makePlanFixture()
        fixture.plan.skipThisMonth()
        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.5, protectedGoalIds: [], skippedGoalIds: []
        )
        #expect(fixture.plan.effectiveAmount == 50)
        try await fixture.service.applyBulkFlexAdjustment(
            plans: [fixture.plan], adjustment: 0.75, protectedGoalIds: [], skippedGoalIds: []
        )
        #expect(fixture.plan.effectiveAmount == 75)
    }

    @Test("A delayed FX response cannot overwrite the latest slider amount")
    func latestSliderAdjustmentWinsDelayedConversion() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let rates = ControlledExchangeRates()
        let settings = MonthlyPlanningSettings.shared
        let previousCurrency = settings.displayCurrency
        let previousBudget = settings.monthlyBudget
        settings.displayCurrency = "USD"
        settings.monthlyBudget = nil
        defer {
            settings.displayCurrency = previousCurrency
            settings.monthlyBudget = previousBudget
        }
        let goal = Goal(
            name: "FX slider", currency: "EUR", targetAmount: 100,
            deadline: Date().addingTimeInterval(86_400)
        )
        context.insert(goal)
        try context.save()
        let viewModel = MonthlyPlanningViewModel(modelContext: context, exchangeRateService: rates)
        await viewModel.loadMonthlyRequirements()
        viewModel.protectedGoalIds = []
        viewModel.skippedGoalIds = []
        rates.suspendNextConversion = true

        let first = Task { await viewModel.applyFlexAdjustment(0.5) }
        await rates.waitForSuspendedConversion()
        await viewModel.applyFlexAdjustment(0.75)
        rates.resumeConversion()
        await first.value

        #expect(viewModel.flexAdjustment == 0.75)
        #expect(viewModel.getEffectiveAmount(for: goal.id) == 75)
        #expect(viewModel.monthlyRequirements.first?.requiredMonthly == 100)
        #expect(viewModel.adjustedTotal == 90)
        let verificationContext = ModelContext(container)
        let persistedPlans = try verificationContext.fetch(FetchDescriptor<MonthlyPlan>())
        let persistedPlan = try #require(persistedPlans.first { $0.goalId == goal.id })
        #expect(persistedPlan.customAmount == 75)
    }

    @MainActor
    private final class ControlledExchangeRates: ExchangeRateServiceProtocol {
        var suspendNextConversion = false
        private var suspendedConversion: CheckedContinuation<Void, Never>?
        private var suspensionWaiter: CheckedContinuation<Void, Never>?

        func fetchRate(from: String, to: String) async throws -> Double {
            if suspendNextConversion {
                suspendNextConversion = false
                await withCheckedContinuation { continuation in
                    suspendedConversion = continuation
                    suspensionWaiter?.resume()
                    suspensionWaiter = nil
                }
            }
            return from == to ? 1 : 1.2
        }

        func waitForSuspendedConversion() async {
            guard suspendedConversion == nil else { return }
            await withCheckedContinuation { suspensionWaiter = $0 }
        }

        func resumeConversion() {
            suspendedConversion?.resume()
            suspendedConversion = nil
        }

        func hasValidConfiguration() -> Bool { true }
        func setOfflineMode(_ offline: Bool) {}
        func refreshRatesIfStale() async {}
    }

    private func makePlanFixture() throws -> (
        container: ModelContainer, plan: MonthlyPlan, service: MonthlyPlanService
    ) {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let calculation = GoalCalculationService(
            exchangeRateService: MockExchangeRateService(),
            tatumService: DIContainer.shared.tatumService,
            modelContext: context
        )
        let plan = MonthlyPlan(
            goalId: UUID(), monthLabel: "2026-10", requiredMonthly: 100,
            remainingAmount: 1000, monthsRemaining: 10, currency: "USD"
        )
        context.insert(plan)
        try context.save()
        return (container, plan, MonthlyPlanService(modelContext: context, goalCalculationService: calculation))
    }

    private func requirement(goalID: UUID, amount: Double, currency: String) -> MonthlyRequirement {
        MonthlyRequirement(
            goalId: goalID, goalName: "Regression", currency: currency,
            targetAmount: 1000, currentTotal: 0, remainingAmount: 1000,
            monthsRemaining: 10, requiredMonthly: amount, progress: 0,
            deadline: Date(timeIntervalSince1970: 1_800_000_000), status: .onTrack
        )
    }
}
