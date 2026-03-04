import Testing
import Foundation
import SwiftData
@testable import CryptoSavingsTracker

@MainActor
struct MonthlyPlanningBudgetPreviewOrderingTests {

    @Test("Latest preview request wins over stale request")
    func latestWins() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        let settings = viewModel.planningSettings
        let previousBudget = settings.monthlyBudget
        let previousCurrency = settings.budgetCurrency
        defer {
            settings.monthlyBudget = previousBudget
            settings.budgetCurrency = previousCurrency
        }

        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 1200,
            currentTotal: 0,
            deadline: deadline
        )
        context.insert(goal)
        try context.save()

        settings.monthlyBudget = 1200
        settings.budgetCurrency = "USD"

        await viewModel.loadMonthlyRequirements()

        let first = MoneyQuantizer.normalize(Decimal(string: "1")!, currency: "USD", mode: .halfUp)
        let second = MoneyQuantizer.normalize(Decimal(string: "1200")!, currency: "USD", mode: .halfUp)

        await viewModel.previewBudget(amount: first, currency: "USD")
        await viewModel.previewBudget(amount: second, currency: "USD")

        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(viewModel.budgetComputationResult != nil)
        #expect(viewModel.budgetComputationResult?.enteredBudgetCanonical.minorUnitValue == second.minorUnitValue)
        #expect(viewModel.budgetComputationResult?.state == .readyFeasible)
    }
}
