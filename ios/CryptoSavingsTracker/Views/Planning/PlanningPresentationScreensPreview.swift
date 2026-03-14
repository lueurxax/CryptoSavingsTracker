import SwiftUI
import SwiftData

private enum PlanningPresentationTab {
    case goals
    case adjust
    case stats
}

private struct PlanningPresentationChrome<Content: View>: View {
    let container: ModelContainer
    let selectedTab: PlanningPresentationTab
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(.regularMaterial)
        }
        .modelContainer(container)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Goals", icon: "target", tab: .goals)
            tabButton(title: "Adjust", icon: "slider.horizontal.3", tab: .adjust)
            tabButton(title: "Stats", icon: "chart.bar.fill", tab: .stats)
        }
        .background(AccessibleColors.mediumBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tabButton(title: String, icon: String, tab: PlanningPresentationTab) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Rectangle()
                .fill(selectedTab == tab ? AccessibleColors.primaryInteractive : .clear)
                .frame(height: 2)
        }
        .foregroundColor(selectedTab == tab ? AccessibleColors.primaryInteractive : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}

private struct PlanningAdjustPresentationScreen: View {
    let container: ModelContainer
    @StateObject private var viewModel: MonthlyPlanningViewModel

    init(container: ModelContainer, viewModel: MonthlyPlanningViewModel) {
        self.container = container
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        PlanningPresentationChrome(container: container, selectedTab: .adjust) {
            ScrollView {
                VStack(spacing: 16) {
                    budgetCard
                    FlexAdjustmentSlider(viewModel: viewModel)
                    quickActionsCard
                }
                .padding()
            }
        }
    }

    private var budgetCard: some View {
        BudgetHealthCard(
            state: viewModel.budgetHealthState,
            budgetAmount: viewModel.hasBudget ? viewModel.budgetAmount : nil,
            budgetCurrency: viewModel.budgetCurrency,
            minimumRequired: viewModel.budgetFeasibility.minimumRequired > 0 ? viewModel.budgetFeasibility.minimumRequired : nil,
            nextConstrainedGoal: viewModel.budgetFocusGoalName,
            nextDeadline: viewModel.budgetFocusGoalDeadline,
            conversionContext: viewModel.budgetConversionContext,
            onPrimaryAction: {},
            onEdit: {}
        )
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ForEach([QuickAction.payExact, .payHalf, .skipMonth, .reset], id: \.title) { action in
                    HStack {
                        Image(systemName: action.systemImage)
                            .frame(width: 16)
                            .foregroundColor(AccessibleColors.primaryInteractive)
                        Text(action.title)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlanningStatsPresentationScreen: View {
    let container: ModelContainer
    @StateObject private var viewModel: MonthlyPlanningViewModel

    init(container: ModelContainer, viewModel: MonthlyPlanningViewModel) {
        self.container = container
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        PlanningPresentationChrome(container: container, selectedTab: .stats) {
            ScrollView {
                VStack(spacing: 16) {
                    budgetCard
                    summaryCard
                    statisticsCard
                }
                .padding()
            }
        }
    }

    private var budgetCard: some View {
        BudgetHealthCard(
            state: viewModel.budgetHealthState,
            budgetAmount: viewModel.hasBudget ? viewModel.budgetAmount : nil,
            budgetCurrency: viewModel.budgetCurrency,
            minimumRequired: viewModel.budgetFeasibility.minimumRequired > 0 ? viewModel.budgetFeasibility.minimumRequired : nil,
            nextConstrainedGoal: viewModel.budgetFocusGoalName,
            nextDeadline: viewModel.budgetFocusGoalDeadline,
            conversionContext: viewModel.budgetConversionContext,
            onPrimaryAction: {},
            onEdit: {}
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Summary")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Total Required", value: formatAmount(viewModel.totalRequired, currency: viewModel.displayCurrency))
                summaryRow("Active Goals", value: "\(viewModel.statistics.totalGoals)")
                if let deadline = viewModel.statistics.shortestDeadline {
                    summaryRow("Next Deadline", value: deadline.formatted(.dateTime.month(.abbreviated).day().year()))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                statisticRow("On Track", count: viewModel.statistics.onTrackCount, color: AccessibleColors.success)
                statisticRow("Need Attention", count: viewModel.statistics.attentionCount, color: AccessibleColors.warning)
                statisticRow("Critical", count: viewModel.statistics.criticalCount, color: AccessibleColors.error)
                statisticRow("Completed", count: viewModel.statistics.completedCount, color: AccessibleColors.success)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func statisticRow(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

#Preview("Planning Adjust") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        MonthlyPlan.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.sharedModelContainer

    let viewModel = makePlanningPresentationPreviewViewModel(container: container)
    viewModel.flexAdjustment = 0.94
    return PlanningAdjustPresentationScreen(container: container, viewModel: viewModel)
}

#Preview("Planning Stats") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        MonthlyPlan.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.sharedModelContainer

    let viewModel = makePlanningPresentationPreviewViewModel(container: container)
    return PlanningStatsPresentationScreen(container: container, viewModel: viewModel)
}
