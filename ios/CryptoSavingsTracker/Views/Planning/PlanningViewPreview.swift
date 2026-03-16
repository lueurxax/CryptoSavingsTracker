// Extracted preview-only declarations for NAV003 policy compliance.
// Source: PlanningView.swift

import SwiftUI
import SwiftData

private struct PlanningPreviewHost: View {
    let container: ModelContainer
    @StateObject private var viewModel: MonthlyPlanningViewModel

    init(container: ModelContainer, viewModel: MonthlyPlanningViewModel) {
        self.container = container
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            iOSCompactPlanningView(
                viewModel: viewModel,
                staleDrafts: [],
                goalNamesByID: [:]
            )
        }
        .modelContainer(container)
    }
}

@MainActor
func makePlanningPresentationPreviewViewModel(container: ModelContainer) -> MonthlyPlanningViewModel {
    let modelContext = container.mainContext
    let bitcoinGoal = Goal(
        name: "Bitcoin Reserve",
        currency: "USD",
        targetAmount: 12000,
        deadline: Date().addingTimeInterval(86400 * 30)
    )
    let stablecoinGoal = Goal(
        name: "Stablecoin Buffer",
        currency: "USD",
        targetAmount: 6000,
        deadline: Date().addingTimeInterval(86400 * 75)
    )

    modelContext.insert(bitcoinGoal)
    modelContext.insert(stablecoinGoal)
    try? modelContext.save()

    MonthlyPlanningSettings.shared.monthlyBudget = 1400
    MonthlyPlanningSettings.shared.budgetCurrency = "USD"
    MonthlyPlanningSettings.shared.paymentDay = 5

    let viewModel = MonthlyPlanningViewModel(modelContext: modelContext)
    viewModel.goals = [bitcoinGoal, stablecoinGoal]
    viewModel.monthlyRequirements = [
        MonthlyRequirement(
            goalId: bitcoinGoal.id,
            goalName: bitcoinGoal.name,
            currency: "USD",
            targetAmount: 12000,
            currentTotal: 3750,
            remainingAmount: 8250,
            monthsRemaining: 1,
            requiredMonthly: 8250,
            progress: 0.31,
            deadline: bitcoinGoal.deadline,
            status: .critical
        ),
        MonthlyRequirement(
            goalId: stablecoinGoal.id,
            goalName: stablecoinGoal.name,
            currency: "USD",
            targetAmount: 6000,
            currentTotal: 4200,
            remainingAmount: 1800,
            monthsRemaining: 2,
            requiredMonthly: 900,
            progress: 0.70,
            deadline: stablecoinGoal.deadline,
            status: .attention
        )
    ]
    viewModel.totalRequired = 9150
    viewModel.displayCurrency = "USD"
    viewModel.budgetFeasibility = FeasibilityResult(
        isFeasible: false,
        minimumRequired: 9150,
        currency: "USD",
        infeasibleGoals: [
            InfeasibleGoal(
                id: UUID(),
                goalId: bitcoinGoal.id,
                goalName: bitcoinGoal.name,
                deadline: bitcoinGoal.deadline,
                requiredMonthly: 8250,
                shortfall: 6850,
                currency: "USD"
            )
        ],
        suggestions: []
    )
    return viewModel
}

#Preview("iOS Compact") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, MonthlyPlan.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
    return PlanningPreviewHost(
        container: container,
        viewModel: makePlanningPresentationPreviewViewModel(container: container)
    )
}

#Preview("macOS") {
    let modelContext = CryptoSavingsTrackerApp.previewModelContainer.mainContext
    NavigationStack {
        macOSPlanningView(
            viewModel: MonthlyPlanningViewModel(modelContext: modelContext),
            staleDrafts: [],
            goalNamesByID: [:]
        )
    }
    .modelContainer(CryptoSavingsTrackerApp.previewModelContainer)
    .frame(width: 800, height: 600)
}
