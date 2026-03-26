import SwiftUI
import SwiftData

private struct MonthlyPlanningContainerPreviewHost: View {
    let container: ModelContainer

    var body: some View {
        NavigationStack {
            MonthlyPlanningContainer()
        }
        .modelContainer(container)
    }
}

private func makeMonthlyPlanningContainerPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        MonthlyPlan.self,
        MonthlyExecutionRecord.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.previewModelContainer

    let context = container.mainContext

    let piano = Goal(
        name: "Piano for daughter",
        currency: "USD",
        targetAmount: 500,
        deadline: Calendar.current.date(byAdding: .day, value: 29, to: Date()) ?? Date()
    )
    let birthday = Goal(
        name: "Afina's birthday party",
        currency: "USD",
        targetAmount: 1000,
        deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    )

    context.insert(piano)
    context.insert(birthday)
    try? context.save()

    MonthlyPlanningSettings.shared.monthlyBudget = 2800
    MonthlyPlanningSettings.shared.budgetCurrency = "USD"
    MonthlyPlanningSettings.shared.paymentDay = 29

    return container
}

#Preview("Monthly Planning Container Light") {
    MonthlyPlanningContainerPreviewHost(container: makeMonthlyPlanningContainerPreviewContainer())
}

#Preview("Monthly Planning Container Dark") {
    MonthlyPlanningContainerPreviewHost(container: makeMonthlyPlanningContainerPreviewContainer())
        .preferredColorScheme(.dark)
}
