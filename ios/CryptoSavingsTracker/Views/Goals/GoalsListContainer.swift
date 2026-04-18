//
//  GoalsListContainer.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

// DetailViewType is now a shared enum

/// iOS-specific goals list container with navigation stack
struct GoalsListContainer: View {
    @Query(filter: #Predicate<Goal> { goal in
        goal.lifecycleStatusRawValue == "active"
    })
    private var goals: [Goal]
    @Binding var selectedView: DetailViewType
    @Environment(\.modelContext) private var modelContext
    @State private var editingGoal: Goal?
    @State private var refreshTrigger = UUID()
    @State private var selectedGoalForLifecycleAction: Goal?
    @State private var showingLifecycleActions = false
    @State private var addAssetContextGoal: Goal?
    @State private var addTransactionContextGoal: Goal?
    
    var body: some View {
        NavigationStack {
            List {
                Section("Your Goals") {
                    if goals.isEmpty {
                        EmptyGoalsView {
                            // Handled by toolbar button
                        }
                    } else {
                        ForEach(goals) { goal in
                            NavigationLink(destination: DetailContainerView(goal: goal, selectedView: $selectedView)) {
                                UnifiedGoalRowView.iOS(goal: goal, refreshTrigger: refreshTrigger)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    deleteGoal(goal)
                                }
                                .tint(AccessibleColors.error)
                                
                                Button("Status") {
                                    selectedGoalForLifecycleAction = goal
                                    showingLifecycleActions = true
                                }
                                .tint(AccessibleColors.warning)

                                Button("Edit") {
                                    editingGoal = goal
                                }
                                .tint(AccessibleColors.primaryInteractive)
                            }
                            .contextMenu {
                                GoalContextMenu(
                                    goal: goal,
                                    onDelete: { deleteGoal(goal) },
                                    onEdit: { editingGoal = goal },
                                    onAddAsset: { addAssetContextGoal = goal },
                                    onAddTransaction: { addTransactionContextGoal = goal }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Goals")
            .refreshable {
                await refreshGoalData()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: AddGoalView()) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add goal")
                    .platformTouchTarget()
                }
            }
            .onAppear {
                if HiddenRuntimeMode.current.allowsShortcuts,
                   PlatformManager.shared.capabilities.supportsHapticFeedback {
                    setupShortcuts()
                }
            }
        }
        // NAV-MOD: MOD-04
        .confirmationDialog(
            "Update Goal Status",
            isPresented: $showingLifecycleActions,
            titleVisibility: .visible
        ) {
            if let goal = selectedGoalForLifecycleAction {
                Button("Cancel Goal (free allocations)", role: .destructive) {
                    Task { @MainActor in
                        await GoalLifecycleService(modelContext: modelContext).cancelGoal(goal)
                    }
                }
                Button("Mark Finished (keep allocations)") {
                    Task { @MainActor in
                        await GoalLifecycleService(modelContext: modelContext).finishGoal(goal)
                    }
                }
            }
            Button("Close", role: .cancel) { }
        }
        // NAV-MOD: MOD-01
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: modelContext)
                .presentationDetents([.large])
        }
        // NAV-MOD: MOD-01
        .sheet(item: $addAssetContextGoal) { goal in
            AddAssetView(goal: goal)
                .presentationDetents([.large])
        }
        .sheet(item: $addTransactionContextGoal) { goal in
            GoalTransactionEntrySheet(goal: goal)
                .presentationDetents([.large])
        }
    }
    
    // MARK: - Private Methods
    
    private func deleteGoal(_ goal: Goal) {
        withAnimation {
            Task { @MainActor in
                await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
            }
            
            NotificationCenter.default.post(name: .goalDeleted, object: goal)
        }
    }
    
    private func refreshGoalData() async {
        let calc = DIContainer.shared.goalCalculationService
        for goal in goals {
            _ = await calc.getCurrentTotal(for: goal)
            _ = await calc.getProgress(for: goal)
        }
    }
    
    private func setupShortcuts() {
        // iOS Shortcuts integration handled in ShortcutsProvider.swift
    }
}

/// Sheet that lets the user pick an asset and record a transaction from the goals list context menu
struct GoalTransactionEntrySheet: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [Asset]

    init(goal: Goal) {
        self.goal = goal
        self._assets = Query(
            filter: #Predicate<Asset> { _ in true },
            sort: \Asset.currency
        )
    }

    private var goalAssets: [Asset] {
        assets.filter { asset in
            (asset.allocations ?? []).contains { $0.goal?.id == goal.id }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if goalAssets.isEmpty {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "bitcoinsign.circle",
                        description: Text("Add an asset to \(goal.name) before recording a transaction.")
                    )
                } else if goalAssets.count == 1, let asset = goalAssets.first {
                    AddTransactionView(asset: asset)
                } else {
                    List(goalAssets) { asset in
                        NavigationLink(destination: AddTransactionView(asset: asset)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.currency)
                                    .font(.headline)
                                if let address = asset.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Asset")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
            }
        }
    }
}

/// Context menu for goal actions
struct GoalContextMenu: View {
    let goal: Goal
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onAddAsset: () -> Void
    let onAddTransaction: () -> Void

    var body: some View {
        Group {
            Button("Edit Goal") {
                onEdit()
            }

            Button("Add Asset") {
                onAddAsset()
            }

            Button("Add Transaction") {
                onAddTransaction()
            }

            Divider()

            Button("Delete Goal", role: .destructive) {
                onDelete()
            }
        }
    }
}
