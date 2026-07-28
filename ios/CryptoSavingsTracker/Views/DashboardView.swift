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

struct DashboardGoalSnapshot: Equatable {
    let calculationResult: GoalCurrentTotalResult
    let currentTotal: Double?
    let progress: Double?

    init(calculationResult: GoalCurrentTotalResult, targetAmount: Double) {
        self.calculationResult = calculationResult
        guard calculationResult.isComplete else {
            currentTotal = nil
            progress = nil
            return
        }

        currentTotal = calculationResult.total
        progress = targetAmount > 0 ? min(calculationResult.total / targetAmount, 1.0) : 0
    }
}

struct DashboardPortfolioEntry: Equatable {
    let amount: Double
    let currency: String
    let isComplete: Bool

    init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
        self.isComplete = true
    }

    init(calculationResult: GoalCurrentTotalResult, currency: String) {
        self.amount = calculationResult.total
        self.currency = currency
        self.isComplete = calculationResult.isComplete
    }
}

struct DashboardActivityEntry: Equatable {
    let amount: Double
    let currency: String
    let date: Date
}

enum DashboardTrendState {
    case loading
    case loaded([BalanceHistoryPoint])
    case unavailable
}

struct DashboardPortfolioRefreshFingerprint: Hashable {
    let displayCurrency: String
    let goals: [DashboardGoalRefreshFingerprint]

    init(displayCurrency: String, goals: [Goal]) {
        self.displayCurrency = displayCurrency.uppercased()
        self.goals = goals
            .filter { $0.lifecycleStatus == .active }
            .map(DashboardGoalRefreshFingerprint.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

struct DashboardRefreshRequestID: Hashable {
    let portfolioFingerprint: DashboardPortfolioRefreshFingerprint
    let exchangeRateGeneration: UInt64
    let calendarDayStart: Date
}

struct DashboardGoalRefreshFingerprint: Hashable {
    let id: UUID
    let currency: String
    let targetAmount: Double
    let deadline: Date
    let lifecycleStatusRawValue: String
    let lastModifiedDate: Date
    let allocations: [DashboardAllocationRefreshFingerprint]

    init(goal: Goal) {
        id = goal.id
        currency = goal.currency.uppercased()
        targetAmount = goal.targetAmount
        deadline = goal.deadline
        lifecycleStatusRawValue = goal.lifecycleStatusRawValue
        lastModifiedDate = goal.lastModifiedDate
        allocations = (goal.allocations ?? [])
            .map(DashboardAllocationRefreshFingerprint.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

struct DashboardAllocationRefreshFingerprint: Hashable {
    let id: UUID
    let amount: Double
    let lastModifiedDate: Date
    let assetID: UUID?
    let assetCurrency: String?
    let assetCurrentAmount: Double
    let transactions: [DashboardTransactionRefreshFingerprint]

    init(allocation: AssetAllocation) {
        id = allocation.id
        amount = allocation.amountValue
        lastModifiedDate = allocation.lastModifiedDate
        assetID = allocation.asset?.id
        assetCurrency = allocation.asset?.currency.uppercased()
        assetCurrentAmount = allocation.asset?.currentAmount ?? 0
        transactions = (allocation.asset?.transactions ?? [])
            .map(DashboardTransactionRefreshFingerprint.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

struct DashboardTransactionRefreshFingerprint: Hashable {
    let id: UUID
    let amount: Double
    let date: Date
    let sourceRawValue: String

    init(transaction: Transaction) {
        id = transaction.id
        amount = transaction.amount
        date = transaction.date
        sourceRawValue = transaction.sourceRawValue
    }
}

@MainActor
final class DashboardRefreshGenerationGuard {
    struct Generation: Equatable {
        fileprivate let value: UInt64
    }

    private var nextValue: UInt64 = 0
    private var currentGeneration: Generation?

    func begin() -> Generation {
        nextValue &+= 1
        let generation = Generation(value: nextValue)
        currentGeneration = generation
        return generation
    }

    @discardableResult
    func commitIfCurrent(
        _ generation: Generation,
        _ commit: () -> Void
    ) -> Bool {
        guard !Task.isCancelled, generation == currentGeneration else {
            return false
        }

        commit()
        return true
    }
}

enum DashboardPortfolioTotalCalculator {
    static func total(
        entries: [DashboardPortfolioEntry],
        displayCurrency: String,
        exchangeRateService: ExchangeRateServiceProtocol
    ) async throws -> Double {
        guard entries.allSatisfy(\.isComplete) else {
            throw DashboardPortfolioTotalError.incompleteGoalTotal
        }

        let targetCurrency = displayCurrency.uppercased()
        var convertedTotal = 0.0

        for entry in entries {
            let sourceCurrency = entry.currency.uppercased()
            if sourceCurrency == targetCurrency {
                convertedTotal += entry.amount
            } else {
                let rate = try await exchangeRateService.fetchRate(
                    from: sourceCurrency,
                    to: targetCurrency
                )
                convertedTotal += entry.amount * rate
            }
        }

        return convertedTotal
    }
}

enum DashboardPortfolioTotalError: Error {
    case incompleteGoalTotal
}

enum DashboardActivityTrendCalculator {
    static func points(
        entries: [DashboardActivityEntry],
        displayCurrency: String,
        endDate: Date = Date(),
        calendar: Calendar = .current,
        exchangeRateService: ExchangeRateServiceProtocol
    ) async throws -> [BalanceHistoryPoint] {
        let targetCurrency = displayCurrency.uppercased()
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) else {
            return []
        }

        let windowEntries = entries.filter { entry in
            let day = calendar.startOfDay(for: entry.date)
            return day >= startDay && day <= endDay && !entry.currency.isEmpty
        }

        var ratesByCurrency: [String: Double] = [targetCurrency: 1]
        for sourceCurrency in Set(windowEntries.map { $0.currency.uppercased() })
        where sourceCurrency != targetCurrency {
            ratesByCurrency[sourceCurrency] = try await exchangeRateService.fetchRate(
                from: sourceCurrency,
                to: targetCurrency
            )
        }

        let convertedByDay = Dictionary(grouping: windowEntries) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { dayEntries in
            dayEntries.reduce(0.0) { total, entry in
                let sourceCurrency = entry.currency.uppercased()
                return total + entry.amount * (ratesByCurrency[sourceCurrency] ?? 0)
            }
        }

        var runningTotal = 0.0
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            runningTotal += convertedByDay[day, default: 0]
            return BalanceHistoryPoint(
                date: day,
                balance: runningTotal,
                currency: targetCurrency
            )
        }
    }
}

enum DashboardActivityTrendLoader {
    static func load(
        entries: [DashboardActivityEntry],
        displayCurrency: String,
        endDate: Date = Date(),
        calendar: Calendar = .current,
        exchangeRateService: ExchangeRateServiceProtocol
    ) async -> DashboardTrendState {
        do {
            return .loaded(
                try await DashboardActivityTrendCalculator.points(
                    entries: entries,
                    displayCurrency: displayCurrency,
                    endDate: endDate,
                    calendar: calendar,
                    exchangeRateService: exchangeRateService
                )
            )
        } catch {
            return .unavailable
        }
    }
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
    @AppStorage("mvp.settings.displayCurrency") private var displayCurrency = "USD"
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshots: [UUID: DashboardGoalSnapshot] = [:]
    @State private var portfolioTotal: Double?
    @State private var trendState: DashboardTrendState = .loading
    @State private var isLoadingSnapshots = false
    @State private var refreshGenerationGuard = DashboardRefreshGenerationGuard()
    @State private var exchangeRateGeneration: UInt64 = 0
    @State private var calendarDayStart = Calendar.current.startOfDay(for: Date())

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

    private var portfolioRefreshFingerprint: DashboardPortfolioRefreshFingerprint {
        DashboardPortfolioRefreshFingerprint(
            displayCurrency: displayCurrency,
            goals: goals
        )
    }

    private var refreshRequestID: DashboardRefreshRequestID {
        DashboardRefreshRequestID(
            portfolioFingerprint: portfolioRefreshFingerprint,
            exchangeRateGeneration: exchangeRateGeneration,
            calendarDayStart: calendarDayStart
        )
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if activeGoals.isEmpty {
                    DashboardEmptyState()
                } else {
                    PortfolioSummaryCard(
                        portfolioTotal: portfolioTotal,
                        displayCurrency: displayCurrency,
                        goalCount: activeGoals.count,
                        isLoading: isLoadingSnapshots
                    )

                    ActiveGoalsSection(goals: activeGoals, snapshots: snapshots)

                    DashboardTrendCard(state: trendState)

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
        .task(id: refreshRequestID) {
            await loadSnapshots()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .exchangeRatesDidRefresh)
                .receive(on: RunLoop.main)
        ) { _ in exchangeRateGeneration &+= 1 }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name.NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in updateCalendarDay() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                updateCalendarDay()
            }
        }
        .refreshable {
            await loadSnapshots()
        }
    }

    private func updateCalendarDay() {
        let updatedDayStart = Calendar.current.startOfDay(for: Date())
        if updatedDayStart != calendarDayStart {
            calendarDayStart = updatedDayStart
        }
    }

    private func loadSnapshots() async {
        guard !Task.isCancelled else {
            return
        }

        let generation = refreshGenerationGuard.begin()
        let refreshedGoals = activeGoals
        let refreshedDisplayCurrency = displayCurrency
        let refreshedCalendarDayStart = calendarDayStart
        let refreshedActivityEntries = recentTransactions.compactMap { transaction -> DashboardActivityEntry? in
            guard let currency = transaction.asset?.currency else {
                return nil
            }
            return DashboardActivityEntry(
                amount: transaction.amount,
                currency: currency,
                date: transaction.date
            )
        }
        isLoadingSnapshots = true
        portfolioTotal = nil
        trendState = .loading

        var updatedSnapshots: [UUID: DashboardGoalSnapshot] = [:]
        for goal in refreshedGoals {
            let result = await GoalCalculationService.getCurrentTotalResult(for: goal)
            updatedSnapshots[goal.id] = DashboardGoalSnapshot(
                calculationResult: result,
                targetAmount: goal.targetAmount
            )
        }

        let updatedPortfolioTotal: Double?
        do {
            let entries = refreshedGoals.compactMap { goal in
                updatedSnapshots[goal.id].map {
                    DashboardPortfolioEntry(
                        calculationResult: $0.calculationResult,
                        currency: goal.currency
                    )
                }
            }
            updatedPortfolioTotal = try await DashboardPortfolioTotalCalculator.total(
                entries: entries,
                displayCurrency: refreshedDisplayCurrency,
                exchangeRateService: DIContainer.shared.exchangeRateService
            )
        } catch {
            updatedPortfolioTotal = nil
        }

        let updatedTrendState = await DashboardActivityTrendLoader.load(
            entries: refreshedActivityEntries,
            displayCurrency: refreshedDisplayCurrency,
            endDate: refreshedCalendarDayStart,
            exchangeRateService: DIContainer.shared.exchangeRateService
        )

        refreshGenerationGuard.commitIfCurrent(generation) {
            snapshots = updatedSnapshots
            portfolioTotal = updatedPortfolioTotal
            trendState = updatedTrendState
            isLoadingSnapshots = false
        }
    }
}

private struct PortfolioSummaryCard: View {
    let portfolioTotal: Double?
    let displayCurrency: String
    let goalCount: Int
    let isLoading: Bool

    private var balanceText: String {
        if isLoading {
            return "Updating balances..."
        }
        guard let portfolioTotal else {
            return "Balance unavailable"
        }
        return portfolioTotal.formatted(.currency(code: displayCurrency))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio Overview")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(balanceText)
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

    private var progress: Double? {
        snapshot?.progress
    }

    private var currentTotal: Double? {
        snapshot?.currentTotal
    }

    private var statusLabel: String {
        guard let snapshot else {
            return "Updating"
        }
        guard snapshot.calculationResult.isComplete else {
            return "Balance unavailable"
        }
        if goal.allocatedAssets.isEmpty {
            return "Needs asset"
        }
        if snapshot.calculationResult.total <= 0 {
            return "Needs first contribution"
        }
        if goal.daysRemaining <= 14 {
            return "Deadline soon"
        }
        return "Tracking"
    }

    private var statusTint: Color {
        guard let snapshot else {
            return AccessibleColors.primaryInteractive
        }
        guard snapshot.calculationResult.isComplete else {
            return AccessibleColors.warning
        }
        if goal.allocatedAssets.isEmpty {
            return AccessibleColors.warning
        }
        if snapshot.calculationResult.total <= 0 {
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

            if let progress {
                ProgressView(value: progress)
                    .tint(statusTint)
            } else {
                Text(snapshot == nil ? "Updating progress..." : "Progress unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let currentTotal {
                    Text(currentTotal.formatted(.currency(code: goal.currency)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(snapshot == nil ? "Updating balance..." : "Balance unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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
    let state: DashboardTrendState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity Trend")
                .font(.headline)

            switch state {
            case .loading:
                Text("Updating activity...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .unavailable:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text("Some activity could not be converted into your display currency. Retry when rates are available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let dataPoints):
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
