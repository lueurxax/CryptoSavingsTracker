//
//  GoalDetailView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
import Foundation

enum GoalDetailDestructiveAction: Equatable {
    case delete
    case cancel
    case finish
}

enum GoalDetailDestructiveActionPolicy {
    static func actions(for lifecycleStatus: GoalLifecycleStatus) -> [GoalDetailDestructiveAction] {
        lifecycleStatus == .active ? [.delete, .cancel, .finish] : [.delete]
    }
}

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal

    @State private var editingGoal: Goal?
    @State private var showingDeleteConfirmation = false
    @State private var hasStartedDestructiveJourney = false
    @State private var goalPendingCompletion: Goal?

    private var fundingBranch: GoalDetailFundingBranch {
        GoalDetailFundingBranch.make(
            lifecycleStatus: goal.lifecycleStatus,
            snapshot: goal.completionSnapshot
        )
    }

    private var destructiveActions: [GoalDetailDestructiveAction] {
        GoalDetailDestructiveActionPolicy.actions(for: goal.lifecycleStatus)
    }

    private var destructiveDialogMessage: String {
        if destructiveActions.contains(.finish) {
            return "Finish records how this goal was funded. Wallet-tracked balances are released automatically; mixed balances may need one choice."
        }
        return "Delete permanently removes this goal and frees any remaining allocations."
    }

    private var goalActionsMenu: some View {
        Menu {
            Button { editingGoal = goal } label: {
                Label("Edit Goal", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Goal actions")
        .accessibilityHint("Tap to edit or delete this goal")
    }

    private var macOSGoalActions: some View {
        HStack(spacing: 8) {
            Button { editingGoal = goal } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    @ToolbarContentBuilder
    private var goalToolbarContent: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) { goalActionsMenu }
#else
        ToolbarItem(placement: .primaryAction) { macOSGoalActions }
#endif
    }

    @ViewBuilder
    private var detailContent: some View {
        switch fundingBranch {
        case .active:
            ActiveGoalDetailContent(goal: goal)
        case .finished(let content):
            finishedDetailContent(content: content)
        }
    }

    private func finishedDetailContent(content: FinishedGoalFundingContent) -> some View {
        List {
            finishedGoalSummarySection(content: content)
            FinishedGoalFundingSection(content: content)
            if let description = goal.goalDescription, !description.isEmpty {
                descriptionSection
            }
            if let linkString = goal.link, !linkString.isEmpty {
                linkSection
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(goal.name)
    }

    private func finishedGoalSummarySection(content: FinishedGoalFundingContent) -> some View {
        Section("Goal Summary") {
            summaryRow(label: "Target", value: currencyAmount(goal.targetAmount))
            summaryRow(label: "Status", value: "Finished")
            switch content {
            case .snapshot(let presentation):
                summaryRow(
                    label: "Completed",
                    value: presentation.completedAt.formatted(date: .abbreviated, time: .omitted)
                )
            case .pendingReview:
                summaryRow(label: "Completed", value: "Pending funding history review")
            }
        }
    }

    private var descriptionSection: some View {
        Section("Notes") {
            Text(goal.goalDescription ?? "")
                .foregroundStyle(AccessibleColors.primaryText)
        }
    }

    private var linkSection: some View {
        Section("Link") {
            if let linkString = goal.link,
               let url = URL(string: linkString.contains("://") ? linkString : "https://\(linkString)") {
                Link(destination: url) {
                    Label(url.host ?? linkString, systemImage: "link")
                }
                .foregroundStyle(AccessibleColors.primaryInteractive)
            }
        }
    }

    var body: some View {
        detailContent
            .toolbar { goalToolbarContent }
            // NAV-MOD: MOD-04
            .confirmationDialog(
                "Delete Goal?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Goal", role: .destructive) { deleteGoal() }
                if destructiveActions.contains(.cancel) {
                    Button("Cancel Goal (free allocations)", role: .destructive) { cancelGoal() }
                }
                if destructiveActions.contains(.finish) {
                    Button("Finish Goal") { goalPendingCompletion = goal }
                }
                Button("Cancel", role: .cancel) {
                    DIContainer.shared.navigationTelemetryTracker.cancelled(
                        journeyID: NavigationJourney.destructiveDeleteConfirmation,
                        isDirty: false,
                        cancelStage: "destructive_dialog_cancel"
                    )
                }
            } message: {
                Text(destructiveDialogMessage)
            }
            // NAV-MOD: MOD-01
            .sheet(item: $editingGoal) { goal in
                EditGoalView(goal: goal, modelContext: modelContext)
                    .presentationDetents([.large])
            }
            .onChange(of: showingDeleteConfirmation) { _, isPresented in
                if isPresented {
                    hasStartedDestructiveJourney = true
                    DIContainer.shared.navigationTelemetryTracker.flowStarted(
                        journeyID: NavigationJourney.destructiveDeleteConfirmation,
                        entryPoint: "goal_detail_menu"
                    )
                }
            }
            .goalCompletionFlow(request: $goalPendingCompletion) { finishedGoal in
                NotificationCenter.default.post(name: .goalProgressRefreshed, object: finishedGoal)
                if hasStartedDestructiveJourney {
                    DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                        journeyID: NavigationJourney.destructiveDeleteConfirmation,
                        result: "finish_goal"
                    )
                    hasStartedDestructiveJourney = false
                }
            }
    }

    private func currencyAmount(_ amount: Double) -> String {
        "\(String(format: "%.2f", amount)) \(goal.currency)"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        AdaptiveSummaryRow(label: label, value: value)
    }

    private func deleteGoal() {
        if hasStartedDestructiveJourney {
            DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                journeyID: NavigationJourney.destructiveDeleteConfirmation,
                result: "delete_goal"
            )
            hasStartedDestructiveJourney = false
        }
        withAnimation {
            Task { @MainActor in
                await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
            }
            NotificationCenter.default.post(name: .goalDeleted, object: goal)
        }
    }

    private func cancelGoal() {
        if hasStartedDestructiveJourney {
            DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                journeyID: NavigationJourney.destructiveDeleteConfirmation,
                result: "cancel_goal"
            )
            hasStartedDestructiveJourney = false
        }
        Task { @MainActor in
            await GoalLifecycleService(modelContext: modelContext).cancelGoal(goal)
        }
    }
}

private struct ActiveGoalDetailContent: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal

    @Query private var allAssets: [Asset]
    @Query private var allTransactions: [Transaction]
    @State private var showingAddAsset = false
    @State private var showingTransactionAssetPicker = false
    @State private var selectedAssetForAddTransaction: Asset?
    @State private var expandedAssets: Set<UUID> = []
    @State private var goalViewModel: GoalViewModel
    @State private var lastRefresh: Date?

    init(goal: Goal) {
        self.goal = goal
        // #Predicate cannot traverse optional to-many arrays, so fetch all assets
        // and filter in the computed property instead.
        self._allAssets = Query(sort: \Asset.currency)
        self._goalViewModel = State(initialValue: GoalViewModel(goal: goal))
    }

    private var goalAssets: [Asset] {
        allAssets.filter { asset in
            (asset.allocations ?? []).contains { allocation in
                allocation.goal?.id == goal.id
            }
        }
    }

    private var goalTransactions: [Transaction] {
        let goalAssetIDs = Set(goalAssets.map(\.id))
        return allTransactions
            .filter { transaction in
                guard let assetID = transaction.asset?.id else { return false }
                return goalAssetIDs.contains(assetID)
            }
            .sorted { $0.date > $1.date }
    }

    private var goalSummarySection: some View {
        Section("Goal Summary") {
            summaryRow(label: "Target", value: currencyAmount(goal.targetAmount))
            summaryRow(label: "Current", value: currencyAmount(goalViewModel.currentTotal))
            summaryRow(
                label: "Deadline",
                value: "\(goal.deadline.formatted(date: .abbreviated, time: .omitted)) (\(goal.daysRemaining) days remaining)"
            )
            summaryRow(label: "Suggested deposit", value: currencyAmount(goalViewModel.suggestedDeposit))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refresh balances")
                    if let lastRefresh {
                        Text("Updated \(lastRefresh, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(AccessibleColors.secondaryText)
                    }
                }
                Spacer()
                Button { Task { await refreshBalances() } } label: {
                    Label("Refresh", systemImage: goalViewModel.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                }
                .disabled(goalViewModel.isLoading)
                .buttonStyle(.bordered)
            }

            if let balanceRefreshError = goalViewModel.balanceRefreshError {
                ErrorBannerView(
                    error: balanceRefreshError,
                    onRetry: { await refreshBalances() },
                    onDismiss: { goalViewModel.balanceRefreshError = nil }
                )
            }
        }
    }

    private var activeAssetsSection: some View {
        Section("Assets") {
            if goalAssets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No assets added").font(.headline)
                    Text("Add an asset to start tracking real progress toward this goal.")
                        .font(.subheadline)
                        .foregroundStyle(AccessibleColors.secondaryText)
                    Button("Add Asset") { showingAddAsset = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("addAssetButton")
                }
                .padding(.vertical, 8)
            } else {
                ForEach(goalAssets) { asset in
                    AssetRowView(
                        asset: asset,
                        goal: goal,
                        isExpanded: expandedAssets.contains(asset.id),
                        onToggleExpanded: {
                            withAnimation(.default) {
                                if expandedAssets.contains(asset.id) {
                                    expandedAssets.remove(asset.id)
                                } else {
                                    expandedAssets.insert(asset.id)
                                }
                            }
                        },
                        onDelete: {
                            withAnimation(.default) {
                                expandedAssets.remove(asset.id)
                                try? DIContainer.shared.makeAssetMutationService(modelContext: modelContext).deleteAsset(asset)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets())
                }
                .onDelete(perform: deleteAssets)
                .animation(.default, value: goalAssets.count)

                Button("Add Asset") { showingAddAsset = true }
                    .accessibilityIdentifier("addAssetButton")
            }
        }
    }

    private var transactionsSection: some View {
        Section("Transactions") {
            if goalTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No transactions yet").font(.headline)
                    Text("Record a deposit when you add funds toward this goal.")
                        .font(.subheadline)
                        .foregroundStyle(AccessibleColors.secondaryText)
                    Button { presentAddTransaction() } label: {
                        Label(goalAssets.isEmpty ? "Add Asset First" : "Add Transaction", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("goalDetailAddTransactionButton")
                }
                .padding(.vertical, 8)
                .accessibilityIdentifier("goalDetailZeroTransactions")
            } else {
                ForEach(goalTransactions) { transaction in
                    transactionRow(transaction)
                }
                Button { presentAddTransaction() } label: {
                    Label("Add Transaction", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("goalDetailAddTransactionButton")
            }
        }
    }

    private var descriptionSection: some View {
        Section("Notes") {
            Text(goal.goalDescription ?? "")
                .foregroundStyle(AccessibleColors.primaryText)
        }
    }

    private var linkSection: some View {
        Section("Link") {
            if let linkString = goal.link,
               let url = URL(string: linkString.contains("://") ? linkString : "https://\(linkString)") {
                Link(destination: url) {
                    Label(url.host ?? linkString, systemImage: "link")
                }
                .foregroundStyle(AccessibleColors.primaryInteractive)
            }
        }
    }

    var body: some View {
        List {
            goalSummarySection
            activeAssetsSection
            transactionsSection
            if let description = goal.goalDescription, !description.isEmpty { descriptionSection }
            if let linkString = goal.link, !linkString.isEmpty { linkSection }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(goal.name)
        .onChange(of: goal.id) { _, _ in
            goalViewModel = GoalViewModel(goal: goal)
            goalViewModel.setModelContext(modelContext)
            Task { await goalViewModel.refreshValues() }
        }
        .onChange(of: goalAssets.count) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await goalViewModel.refreshValues()
            }
        }
        .onChange(of: allAssets.count) { _, _ in
            Task { await goalViewModel.refreshValues() }
        }
        .onChange(of: allTransactions.count) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await goalViewModel.refreshValues()
            }
        }
#if os(macOS)
        // NAV-MOD: MOD-01
        .popover(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
                .frame(minWidth: 400, minHeight: 300)
        }
#else
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
                .presentationDetents([.large])
        }
#endif
        .sheet(item: $selectedAssetForAddTransaction) { asset in
            AddTransactionView(asset: asset)
#if os(iOS)
                .presentationDetents([.large])
#endif
        }
        .sheet(isPresented: $showingTransactionAssetPicker) {
            NavigationStack {
                List(goalAssets) { asset in
                    Button {
                        showingTransactionAssetPicker = false
                        DispatchQueue.main.async { selectedAssetForAddTransaction = asset }
                    } label: {
                        HStack {
                            Label(asset.currency, systemImage: "bitcoinsign.circle")
                            Spacer()
                            Text("\((asset.transactions ?? []).count) transactions")
                                .font(.footnote)
                                .foregroundStyle(AccessibleColors.secondaryText)
                        }
                    }
                    .accessibilityIdentifier("goalDetailTransactionAsset-\(asset.currency)")
                }
                .navigationTitle("Choose Asset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingTransactionAssetPicker = false }
                    }
                }
            }
        }
        .task(id: goal.id) {
            goalViewModel.setModelContext(modelContext)
            await goalViewModel.refreshValues()
        }
    }

    private func refreshBalances() async {
        BalanceCacheManager.shared.clearCache()
        await goalViewModel.refreshValues()
        await MainActor.run {
            lastRefresh = Date()
            NotificationCenter.default.post(name: .goalProgressRefreshed, object: goal)
        }
    }

    private func currencyAmount(_ amount: Double) -> String {
        "\(String(format: "%.2f", amount)) \(goal.currency)"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        AdaptiveSummaryRow(label: label, value: value)
    }

    @ViewBuilder
    private func transactionRow(_ transaction: Transaction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.comment?.isEmpty == false ? transaction.comment ?? "Transaction" : "Transaction")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AccessibleColors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(AccessibleColors.secondaryText)
            }
            Spacer(minLength: 12)
            Text("\(String(format: "%.6f", transaction.amount)) \(transaction.asset?.currency ?? goal.currency)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(transaction.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goalDetailTransactionRow")
    }

    private func presentAddTransaction() {
        switch goalAssets.count {
        case 0:
            showingAddAsset = true
        case 1:
            selectedAssetForAddTransaction = goalAssets[0]
        default:
            showingTransactionAssetPicker = true
        }
    }

    private func deleteAssets(offsets: IndexSet) {
        withAnimation(.default) {
            let assetsToDelete = offsets.map { goalAssets[$0] }
            for asset in assetsToDelete {
                expandedAssets.remove(asset.id)
            }
            try? DIContainer.shared.makeAssetMutationService(modelContext: modelContext).deleteAssets(assetsToDelete)
        }
    }
}
