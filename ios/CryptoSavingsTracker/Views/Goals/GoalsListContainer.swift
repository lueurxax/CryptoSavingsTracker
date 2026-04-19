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
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var selectedGoalForAddAsset: Goal?
    @State private var selectedAssetForAddTransaction: Asset?
    @State private var selectedGoalForTransactionAssetPicker: Goal?
    @State private var refreshTrigger = UUID()
    @State private var selectedGoalForLifecycleAction: Goal?
    @State private var selectedSharedGoal: FamilyShareInviteeGoalProjection?
    @State private var showingLifecycleActions = false
    @AppStorage(PreviewFeaturesRuntime.userDefaultsKey) private var previewFeaturesEnabled = false
    @StateObject private var familyShareCoordinator = DIContainer.shared.familyShareAcceptanceCoordinator

    var body: some View {
        NavigationStack {
            List {
                if showsSharedGoalsSection {
                    Section {
                        Color.clear
                            .frame(height: 0)
                            .accessibilityIdentifier("sharedGoalsSection")

                        ForEach(familyShareCoordinator.sharedSections) { section in
                            SharedGoalsSectionView(
                                section: section,
                                onGoalSelected: { goal in
                                    selectedSharedGoal = goal
                                },
                                onPrimaryAction: { section in
                                    Task {
                                        await familyShareCoordinator.handlePrimaryAction(for: section)
                                    }
                                }
                            )
                            .environmentObject(familyShareCoordinator)
                        }
                    } header: {
                        Text(familyShareCoordinator.inviteeProjection.entryTitle)
                    } footer: {
                        Text(familyShareCoordinator.inviteeProjection.entrySummary)
                    }
                }

                Section("Your Goals") {
                    if goals.isEmpty {
                        EmptyGoalsView {
                            showingAddGoal = true
                        }
                    } else {
                        ForEach(goals) { goal in
                            NavigationLink(destination: DetailContainerView(goal: goal, selectedView: $selectedView)) {
                                UnifiedGoalRowView.iOS(goal: goal, refreshTrigger: refreshTrigger)
                            }
                            .accessibilityIdentifier("goalRow-\(goal.name)")
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
                                    onAddAsset: {
                                        selectedGoalForAddAsset = goal
                                    },
                                    onAddTransaction: {
                                        presentAddTransaction(for: goal)
                                    },
                                    onDelete: { deleteGoal(goal) },
                                    onEdit: { editingGoal = goal }
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
            .sheet(item: $selectedSharedGoal) { goal in
                NavigationStack {
                    SharedGoalDetailView(goal: goal) {
                        selectedSharedGoal = nil
                    }
                    .environmentObject(familyShareCoordinator)
                }
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
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView()
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedGoalForAddAsset) { goal in
                AddAssetView(goal: goal)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedAssetForAddTransaction) { asset in
                AddTransactionView(asset: asset)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedGoalForTransactionAssetPicker) { goal in
                NavigationStack {
                    List(goal.uniqueAllocatedAssets) { asset in
                        Button {
                            selectedGoalForTransactionAssetPicker = nil
                            DispatchQueue.main.async {
                                selectedAssetForAddTransaction = asset
                            }
                        } label: {
                            HStack {
                                Label(asset.currency, systemImage: "bitcoinsign.circle")
                                Spacer()
                                Text("\((asset.transactions ?? []).count) transactions")
                                    .font(.footnote)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                            }
                        }
                        .accessibilityIdentifier("goalsContextTransactionAsset-\(asset.currency)")
                    }
                    .navigationTitle("Choose Asset")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                selectedGoalForTransactionAssetPicker = nil
                            }
                        }
                    }
                }
            }
    }

    // MARK: - Private Methods

    private var showsSharedGoalsSection: Bool {
        _ = previewFeaturesEnabled
        return HiddenRuntimeMode.current.allowsFamilySharing && familyShareCoordinator.sharedSections.isEmpty == false
    }

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

    private func presentAddTransaction(for goal: Goal) {
        switch goal.uniqueAllocatedAssets.count {
        case 0:
            selectedGoalForAddAsset = goal
        case 1:
            selectedAssetForAddTransaction = goal.uniqueAllocatedAssets[0]
        default:
            selectedGoalForTransactionAssetPicker = goal
        }
    }
}

/// Context menu for goal actions
struct GoalContextMenu: View {
    let goal: Goal
    let onAddAsset: () -> Void
    let onAddTransaction: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

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
