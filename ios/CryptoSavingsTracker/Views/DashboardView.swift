//
//  DashboardView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import Combine
import SwiftData
import SwiftUI

private struct DashboardGoalSnapshot: Equatable {
    let currentTotal: Double
    let progress: Double
}

private enum DashboardPrimaryAction {
    case createGoal
    case addAsset(Goal)
    case recordContribution(Asset)

    var title: String {
        switch self {
        case .createGoal:
            return "Create Goal"
        case .addAsset:
            return "Add Asset"
        case .recordContribution:
            return "Record Contribution"
        }
    }

    var systemImage: String {
        switch self {
        case .createGoal:
            return "flag.fill"
        case .addAsset:
            return "plus.circle.fill"
        case .recordContribution:
            return "arrow.down.circle.fill"
        }
    }

    var message: String {
        switch self {
        case .createGoal:
            return "Start with one clear target, then add assets and contributions as you go."
        case .addAsset(let goal):
            return "Add the first asset for \(goal.name) to begin tracking real progress."
        case .recordContribution(let asset):
            return "Record a contribution for \(asset.currency) to update your dashboard activity."
        }
    }
}

struct DashboardView: View {
    @Query(sort: \Goal.deadline) private var goals: [Goal]
    @State private var snapshots: [UUID: DashboardGoalSnapshot] = [:]
    @State private var isLoadingSnapshots = false

    private var activeGoals: [Goal] {
        goals
            .filter { $0.lifecycleStatus == .active }
            .sorted { lhs, rhs in
                if lhs.deadline == rhs.deadline {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.deadline < rhs.deadline
            }
    }

    private var activeAssets: [Asset] {
        var seenIDs = Set<UUID>()
        return activeGoals
            .flatMap(\.allocatedAssets)
            .filter { asset in
                seenIDs.insert(asset.id).inserted
            }
    }

    private var recentTransactions: [Transaction] {
        var seenIDs = Set<UUID>()
        return activeAssets
            .flatMap { $0.transactions ?? [] }
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    private var portfolioTotal: Double {
        activeGoals.reduce(0) { partialResult, goal in
            partialResult + (snapshots[goal.id]?.currentTotal ?? 0)
        }
    }

    private var primaryAction: DashboardPrimaryAction {
        guard let firstGoal = activeGoals.first else {
            return .createGoal
        }

        if let goalWithoutAssets = activeGoals.first(where: { $0.allocatedAssets.isEmpty }) {
            return .addAsset(goalWithoutAssets)
        }

        if let firstAsset = activeAssets.first, recentTransactions.isEmpty {
            return .recordContribution(firstAsset)
        }

        if let firstAsset = activeAssets.first {
            return .recordContribution(firstAsset)
        }

        return .addAsset(firstGoal)
    }

    private var recentTrendPoints: [BalanceHistoryPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recentWindow = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }

        var runningTotal = 0.0
        let groupedTransactions = Dictionary(grouping: recentTransactions) {
            calendar.startOfDay(for: $0.date)
        }

        return recentWindow.map { day in
            let dayTotal = groupedTransactions[day, default: []].reduce(0.0) { $0 + $1.amount }
            runningTotal += dayTotal
            return BalanceHistoryPoint(date: day, balance: runningTotal, currency: activeGoals.first?.currency ?? "USD")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if activeGoals.isEmpty {
                    DashboardEmptyState()
                } else {
                    PortfolioSummaryCard(
                        portfolioTotal: portfolioTotal,
                        goalCount: activeGoals.count,
                        isLoading: isLoadingSnapshots
                    )

                    ActiveGoalsSection(goals: activeGoals, snapshots: snapshots)

                    DashboardTrendCard(dataPoints: recentTrendPoints)

                    RecentActivityCard(transactions: Array(recentTransactions.prefix(4)))

                    DashboardActionStrip(primaryAction: primaryAction)
                }
            }
            .padding(16)
        }
        .navigationTitle("Dashboard")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .accessibilityIdentifier("mvpRootDashboard")
        .task {
            await loadSnapshots()
        }
        .onChange(of: goals.count) { _, _ in
            Task {
                await loadSnapshots()
            }
        }
        .refreshable {
            await loadSnapshots()
        }
    }

    private func loadSnapshots() async {
        isLoadingSnapshots = true

        var updatedSnapshots: [UUID: DashboardGoalSnapshot] = [:]
        for goal in activeGoals {
            let total = await GoalCalculationService.getCurrentTotal(for: goal)
            let progress = goal.targetAmount > 0 ? min(total / goal.targetAmount, 1.0) : 0
            updatedSnapshots[goal.id] = DashboardGoalSnapshot(currentTotal: total, progress: progress)
        }

        snapshots = updatedSnapshots
        isLoadingSnapshots = false
    }
}

private struct PortfolioSummaryCard: View {
    let portfolioTotal: Double
    let goalCount: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio Overview")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoading ? "Updating balances..." : portfolioTotal.formatted(.currency(code: "USD")))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Saved balances across your active goals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(goalCount)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AccessibleColors.primaryInteractive)
                    Text(goalCount == 1 ? "Active Goal" : "Active Goals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dashboardCardStyle()
    }
}

private struct ActiveGoalsSection: View {
    let goals: [Goal]
    let snapshots: [UUID: DashboardGoalSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Goals")
                .font(.headline)

            ForEach(goals) { goal in
                NavigationLink(destination: GoalDetailView(goal: goal)) {
                    GoalOverviewRow(goal: goal, snapshot: snapshots[goal.id])
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GoalOverviewRow: View {
    let goal: Goal
    let snapshot: DashboardGoalSnapshot?

    private var progress: Double {
        snapshot?.progress ?? 0
    }

    private var currentTotal: Double {
        snapshot?.currentTotal ?? 0
    }

    private var statusLabel: String {
        if goal.allocatedAssets.isEmpty {
            return "Needs asset"
        }
        if currentTotal <= 0 {
            return "Needs first contribution"
        }
        if goal.daysRemaining <= 14 {
            return "Deadline soon"
        }
        return "Tracking"
    }

    private var statusTint: Color {
        if goal.allocatedAssets.isEmpty {
            return AccessibleColors.warning
        }
        if currentTotal <= 0 {
            return AccessibleColors.primaryInteractive
        }
        if goal.daysRemaining <= 14 {
            return AccessibleColors.error
        }
        return AccessibleColors.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(goal.deadline, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.12), in: Capsule())
            }

            ProgressView(value: progress)
                .tint(statusTint)

            HStack {
                Text(currentTotal.formatted(.currency(code: goal.currency)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("of \(goal.targetAmount.formatted(.currency(code: goal.currency)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(goal.daysRemaining)d left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCardStyle()
    }
}

private struct DashboardTrendCard: View {
    let dataPoints: [BalanceHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity Trend")
                .font(.headline)

            if dataPoints.count > 1 && dataPoints.contains(where: { $0.balance != 0 }) {
                SimpleTrendChart(dataPoints: dataPoints)
                    .frame(height: 72)

                Text("Last 7 days of recorded contribution activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recent activity yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Record a contribution to start building a balance trend on the dashboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dashboardCardStyle()
    }
}

struct SimpleTrendChart: View {
    let dataPoints: [BalanceHistoryPoint]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let maxBalance = dataPoints.map(\.balance).max() ?? 1
                let minBalance = dataPoints.map(\.balance).min() ?? 0
                let range = max(maxBalance - minBalance, 1)

                for (index, point) in dataPoints.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(dataPoints.count - 1, 1))
                    let normalizedY = (point.balance - minBalance) / range
                    let y = geometry.size.height * (1 - normalizedY)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(AccessibleColors.primaryInteractive, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct RecentActivityCard: View {
    let transactions: [Transaction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            if transactions.isEmpty {
                Text("No contributions recorded yet. Activity will appear here after your first transaction.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions) { transaction in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.asset?.currency ?? "Asset")
                                .font(.subheadline.weight(.semibold))
                            Text(transaction.date, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(transaction.amount.formatted(.currency(code: transaction.asset?.currency ?? "USD")))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if transaction.id != transactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .dashboardCardStyle()
    }
}

private struct DashboardActionStrip: View {
    let primaryAction: DashboardPrimaryAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Step")
                .font(.headline)

            Text(primaryAction.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                primaryLink
                NavigationLink(destination: AddGoalView()) {
                    Label("Add Goal", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .dashboardCardStyle()
    }

    @ViewBuilder
    private var primaryLink: some View {
        switch primaryAction {
        case .createGoal:
            NavigationLink(destination: AddGoalView()) {
                actionLabel(title: primaryAction.title, systemImage: primaryAction.systemImage)
            }
            .buttonStyle(.borderedProminent)
        case .addAsset(let goal):
            NavigationLink(destination: AddAssetView(goal: goal)) {
                actionLabel(title: primaryAction.title, systemImage: primaryAction.systemImage)
            }
            .buttonStyle(.borderedProminent)
        case .recordContribution(let asset):
            NavigationLink(destination: AddTransactionView(asset: asset)) {
                actionLabel(title: primaryAction.title, systemImage: primaryAction.systemImage)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
    }
}

struct DashboardEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "flag.fill")
                .font(.system(size: 36))
                .foregroundStyle(AccessibleColors.primaryInteractive)

            VStack(alignment: .leading, spacing: 8) {
                Text("Track your first savings goal")
                    .font(.title2.weight(.bold))
                Text("Create a goal, add an asset, and watch progress update as balances change.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("You can add wallet addresses later for automatic crypto tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink(destination: AddGoalView()) {
                Label("Create Goal", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .dashboardCardStyle()
    }
}

private extension View {
    func dashboardCardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}
