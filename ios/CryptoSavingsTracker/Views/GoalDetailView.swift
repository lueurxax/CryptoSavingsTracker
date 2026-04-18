    //
    //  GoalDetailView.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import SwiftData
import Foundation

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    
    @Query private var allAssets: [Asset]
    @Query private var allTransactions: [Transaction]
    @State private var showingAddAsset = false
    @State private var expandedAssets: Set<UUID> = []
    @State private var goalViewModel: GoalViewModel
    @State private var lastRefresh: Date?
    @State private var editingGoal: Goal?
    @State private var showingDeleteConfirmation = false
    @State private var hasStartedDestructiveJourney = false
    
    init(goal: Goal) {
        self.goal = goal
        // #Predicate cannot traverse optional to-many arrays, so fetch all assets
        // and filter in the goalAssets computed property instead.
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

    // MARK: - Sub Views

    private var goalActionsMenu: some View {
        Menu {
            Button {
                editingGoal = goal
            } label: {
                Label("Edit Goal", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
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
            Button {
                editingGoal = goal
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
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
        ToolbarItem(placement: .navigationBarTrailing) {
            goalActionsMenu
        }
#else
        ToolbarItem(placement: .primaryAction) {
            macOSGoalActions
        }
#endif
    }

    private var goalSummarySection: some View {
        Section("Goal Summary") {
            summaryRow(label: "Target", value: currencyAmount(goal.targetAmount))
            summaryRow(label: "Current", value: currencyAmount(goalViewModel.currentTotal))
            summaryRow(
                label: "Deadline",
                value: "\(goal.deadline.formatted(date: .abbreviated, time: .omitted)) (\(goal.daysRemaining) days remaining)"
            )
            HStack {
                Text("Suggested deposit")
                Spacer()
                Text(currencyAmount(goalViewModel.suggestedDeposit))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refresh balances")
                    if let lastRefresh {
                        Text("Updated \(lastRefresh, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await refreshBalances() }
                } label: {
                    Label("Refresh", systemImage: goalViewModel.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                }
                .disabled(goalViewModel.isLoading)
                .buttonStyle(.bordered)
            }
        }
    }

    private var assetsSection: some View {
        Section("Assets") {
            if goalAssets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No assets added")
                        .font(.headline)
                    Text("Add an asset to start tracking real progress toward this goal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Asset") {
                        showingAddAsset = true
                    }
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

                Button("Add Asset") {
                    showingAddAsset = true
                }
                .accessibilityIdentifier("addAssetButton")
            }
        }
    }

    private var hasAnyTransactions: Bool {
        goalAssets.contains { ($0.transactions ?? []).isEmpty == false }
    }

    @ViewBuilder
    private var zeroTransactionSection: some View {
        if !goalAssets.isEmpty && !hasAnyTransactions {
            Section("Transactions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No transactions yet")
                        .font(.headline)
                    Text("Record your first deposit on one of the assets above to start tracking progress.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Notes") {
            Text(goal.goalDescription ?? "")
                .foregroundStyle(.primary)
        }
    }

    private var linkSection: some View {
        Section("Link") {
            if let linkString = goal.link,
               let url = URL(string: linkString.contains("://") ? linkString : "https://\(linkString)") {
                Link(destination: url) {
                    Label(url.host ?? linkString, systemImage: "link")
                }
                .foregroundColor(.accessiblePrimary)
            }
        }
    }

    private var detailListContent: some View {
        List {
            goalSummarySection
            assetsSection
            zeroTransactionSection
            if let description = goal.goalDescription, !description.isEmpty {
                descriptionSection
            }
            if let linkString = goal.link, !linkString.isEmpty {
                linkSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(goal.name)
    }

    var body: some View {
        goalDetailCore
            .onChange(of: goal.id) { _, _ in
                goalViewModel = GoalViewModel(goal: goal)
                goalViewModel.setModelContext(modelContext)
                Task {
                    await goalViewModel.refreshValues()
                }
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
            .onChange(of: showingDeleteConfirmation) { _, isPresented in
                if isPresented {
                    hasStartedDestructiveJourney = true
                    DIContainer.shared.navigationTelemetryTracker.flowStarted(
                        journeyID: NavigationJourney.destructiveDeleteConfirmation,
                        entryPoint: "goal_detail_menu"
                    )
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
    } // End of body

    private var goalDetailCore: some View {
        detailListContent
            .toolbar {
                goalToolbarContent
            }
            // NAV-MOD: MOD-04
            .confirmationDialog(
                "Delete Goal?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Goal", role: .destructive) {
                    deleteGoal()
                }
                Button("Cancel Goal (free allocations)", role: .destructive) {
                    cancelGoal()
                }
                Button("Mark Finished (keep allocations)") {
                    finishGoal()
                }
                Button("Cancel", role: .cancel) {
                    DIContainer.shared.navigationTelemetryTracker.cancelled(
                        journeyID: NavigationJourney.destructiveDeleteConfirmation,
                        isDirty: false,
                        cancelStage: "destructive_dialog_cancel"
                    )
                }
            } message: {
                Text("Choose how to archive '\(goal.name)'. Finished goals keep allocations (treated as spent). Cancel frees allocations back to unallocated.")
            }
            // NAV-MOD: MOD-01
            .sheet(item: $editingGoal) { goal in
                EditGoalView(goal: goal, modelContext: modelContext)
#if os(macOS)
                    .presentationDetents([.large])
#else
                    .presentationDetents([.large])
#endif
            }
            .task(id: goal.id) {
                goalViewModel.setModelContext(modelContext)
                await goalViewModel.refreshValues()
            }
    }
    
    private func refreshBalances() async {
        // Clear cache to force refresh
        BalanceCacheManager.shared.clearCache()
        
        // Refresh goal values
        await goalViewModel.refreshValues()

        await MainActor.run {
            lastRefresh = Date()
            // Post notification to refresh all goal progress views
            NotificationCenter.default.post(name: .goalProgressRefreshed, object: goal)
        }
    }

    private func currencyAmount(_ amount: Double) -> String {
        "\(String(format: "%.2f", amount)) \(goal.currency)"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func deleteAssets(offsets: IndexSet) {
        withAnimation(.default) {
                // Get the assets to delete before modifying anything
            let assetsToDelete = offsets.map { goalAssets[$0] }
            
                // Remove from expanded assets set to prevent UI issues
            for asset in assetsToDelete {
                expandedAssets.remove(asset.id)
            }
            
            try? DIContainer.shared.makeAssetMutationService(modelContext: modelContext).deleteAssets(assetsToDelete)
        }
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

    private func finishGoal() {
        if hasStartedDestructiveJourney {
            DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                journeyID: NavigationJourney.destructiveDeleteConfirmation,
                result: "finish_goal"
            )
            hasStartedDestructiveJourney = false
        }
        Task { @MainActor in
            await GoalLifecycleService(modelContext: modelContext).finishGoal(goal)
        }
    }
}
