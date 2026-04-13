import Testing
@testable import CryptoSavingsTracker

struct BudgetHealthPresentationTests {

    @Test("Not applied budget state matches widget copy contract")
    func notAppliedCopyMatchesContract() {
        let state = BudgetHealthState.notApplied

        #expect(state.statusText == "Budget not applied")
        #expect(state.primaryActionTitle == "Apply Budget")
        #expect(state.insightText(currency: "USD", conversionContext: nil) == "Budget saved, not applied this month.")
        #expect(state.collapsedStatusText(currency: "USD") == "Budget not applied")
    }

    @Test("Needs recalculation state matches widget copy contract")
    func needsRecalculationCopyMatchesContract() {
        let state = BudgetHealthState.needsRecalculation

        #expect(state.statusText == "Needs review")
        #expect(state.primaryActionTitle == "Recalculate")
        #expect(state.insightText(currency: "USD", conversionContext: nil) == "Your goals or month changed. Recalculate allocations.")
        #expect(state.collapsedStatusText(currency: "USD") == "Needs review")
    }
}
