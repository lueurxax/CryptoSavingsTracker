//
//  ContentViewClean.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

// Notification.Name extension moved to shared file

/// Clean, minimal ContentView using platform abstraction
struct ContentView: View {
    @Environment(\.platformCapabilities) private var platform

    var body: some View {
        Group {
            switch platform.navigationStyle {
            case .stack:
                iOSContentView()
            case .splitView:
                macOSContentView()
            case .tabs:
                // Future: Tab-based navigation
                iOSContentView()
            }
        }
    }
}

// MARK: - iOS Content View

struct iOSContentView: View {
    @Query(filter: #Predicate<Goal> { goal in
        goal.lifecycleStatusRawValue == "active"
    })
    private var goals: [Goal]
    @State private var selectedView: DetailViewType = .details
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            GoalsList(
                goals: goals,
                selectedView: $selectedView,
                onDelete: deleteGoal,
                onRefresh: refreshGoalData
            )
        }
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
}

// MARK: - macOS Content View

struct macOSContentView: View {
    @Query(filter: #Predicate<Goal> { goal in
        goal.lifecycleStatusRawValue == "active"
    })
    private var goals: [Goal]
    @State private var selectedGoal: Goal?
    @State private var selectedView: DetailViewType = .details

    var body: some View {
        NavigationSplitView {
            GoalsSidebarView(
                goals: goals,
                selectedGoal: $selectedGoal
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let goal = selectedGoal {
                DetailContainerView(
                    goal: goal,
                    selectedView: $selectedView
                )
            } else {
                EmptyDetailView()
            }
        }
        .onAppear {
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goalDeleted)) { notification in
            if let deletedGoal = notification.object as? Goal,
               selectedGoal?.id == deletedGoal.id {
                selectedGoal = goals.first
            }
        }
    }
}

// MARK: - Goals List Component

struct GoalsList: View {
    let goals: [Goal]
    @Binding var selectedView: DetailViewType
    let onDelete: (Goal) -> Void
    let onRefresh: () async -> Void
    @EnvironmentObject private var familyShareCoordinator: FamilyShareAcceptanceCoordinator
    @State private var familyShareEnabled = DIContainer.shared.familyShareRollout.isEnabled()
    @State private var showingAddGoal = false
    @State private var showingSettings = false
    @State private var editingGoal: Goal?
    @State private var addAssetForGoal: Goal?
    @State private var addTransactionAssetForGoal: Asset?
    @State private var transactionAssetsForPicker: [Asset] = []
    @State private var goalForTransactionPicker: Goal?
    @State private var showTransactionAssetPicker = false
    @State private var showNoAssetsForTransactionAlert = false
    @State private var goalNeedingTransactionAsset: Goal?
    @State private var selectedSharedGoal: FamilyShareInviteeGoalProjection?
    @State private var monthlyPlanningViewModel: MonthlyPlanningViewModel?
    @State private var refreshTrigger = UUID()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            // Portfolio-wide Monthly Planning Widget
            if !goals.isEmpty {
                Section {
                    if let viewModel = monthlyPlanningViewModel {
                        MonthlyPlanningWidget(viewModel: viewModel)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if familyShareEnabled && !familyShareCoordinator.inviteeProjection.sections.isEmpty {
                Section {
                    Text(familyShareCoordinator.inviteeProjection.entrySummary)
                        .font(.subheadline)
                        .foregroundColor(.accessibleSecondary)
                        .accessibilityIdentifier("sharedGoalsSectionSummary")
                } header: {
                    Text(familyShareCoordinator.inviteeProjection.entryTitle)
                        .textCase(nil)
                }
                .accessibilityIdentifier("sharedGoalsSection")
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(familyShareCoordinator.inviteeProjection.sections) { section in
                    Section {
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
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .textCase(nil)
                    .accessibilityIdentifier("sharedGoalsOwnerSection-\(section.namespaceID.namespaceKey.replacingOccurrences(of: "|", with: "-"))")
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
                                onDelete(goal)
                            }
                            .tint(AccessibleColors.error)

                            Button("Edit") {
                                editingGoal = goal
                            }
                            .tint(AccessibleColors.primaryInteractive)
                        }
                        .contextMenu {
                            GoalContextMenuContent(
                                goal: goal,
                                onDelete: { onDelete(goal) },
                                onEdit: { editingGoal = goal },
                                onAddAsset: { addAssetForGoal = goal },
                                onAddTransaction: { handleAddTransaction(for: goal) },
                                onCancel: {
                                    Task { @MainActor in
                                        await GoalLifecycleService(modelContext: modelContext).cancelGoal(goal)
                                    }
                                },
                                onFinish: {
                                    Task { @MainActor in
                                        await GoalLifecycleService(modelContext: modelContext).finishGoal(goal)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .navigationDestination(isPresented: $showingAddGoal) {
            AddGoalView()
        }
        .navigationDestination(item: $selectedSharedGoal) { goal in
            SharedGoalDetailView(goal: goal) {
                selectedSharedGoal = nil
            }
        }
        .refreshable {
            await onRefresh()
            if familyShareEnabled {
                await familyShareCoordinator.refreshAllState()
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                goalsToolbarButtons
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                goalsToolbarButtons
            }
            #endif
        }
        .onAppear {
            familyShareEnabled = DIContainer.shared.familyShareRollout.isEnabled()
            setupShortcuts()
            // Create the monthly planning view model with model context
            if monthlyPlanningViewModel == nil {
                monthlyPlanningViewModel = MonthlyPlanningViewModel(modelContext: modelContext)
            }
            if familyShareEnabled {
                Task {
                    await familyShareCoordinator.refreshAllState()
                }
            }
        }
        // NAV-MOD: MOD-01
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: goal.modelContext!)
                .presentationDetents([.large])
        }
        // NAV-MOD: MOD-01
        .sheet(item: $addAssetForGoal) { goal in
            AddAssetView(goal: goal)
                .presentationDetents([.large])
        }
        // NAV-MOD: MOD-01
        .sheet(item: $addTransactionAssetForGoal) { asset in
            AddTransactionView(asset: asset)
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "Add transaction to which asset?",
            isPresented: $showTransactionAssetPicker
        ) {
            ForEach(transactionAssetsForPicker) { asset in
                Button(asset.currency) {
                    addTransactionAssetForGoal = asset
                    transactionAssetsForPicker = []
                }
            }
            Button("Cancel", role: .cancel) {
                transactionAssetsForPicker = []
                goalForTransactionPicker = nil
                showTransactionAssetPicker = false
                goalNeedingTransactionAsset = nil
            }
        } message: {
            if let goal = goalForTransactionPicker {
                Text("Choose an asset in \"\(goal.name)\"")
            } else {
                Text("Choose an asset for the transaction")
            }
        }
        .alert("No Assets Yet", isPresented: $showNoAssetsForTransactionAlert) {
            Button("Add Asset") {
                if let goal = goalNeedingTransactionAsset {
                    addAssetForGoal = goal
                    goalNeedingTransactionAsset = nil
                }
            }
            Button("Cancel", role: .cancel) {
                goalNeedingTransactionAsset = nil
            }
        } message: {
            Text("Add an asset to the goal before adding a transaction.")
        }
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var goalsToolbarButtons: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("openSettingsButton")
        .platformTouchTarget()

        Button {
            showingAddGoal = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add goal")
        .accessibilityIdentifier("addGoalButton")
        .platformTouchTarget()
    }

    private func setupShortcuts() {
        // iOS Shortcuts integration handled in ShortcutsProvider.swift
    }

    private func handleAddTransaction(for goal: Goal) {
        let assets = goal.uniqueAllocatedAssets
        guard assets.isEmpty == false else {
            goalNeedingTransactionAsset = goal
            showNoAssetsForTransactionAlert = true
            return
        }

        if assets.count == 1 {
            addTransactionAssetForGoal = assets.first
            return
        }

        goalForTransactionPicker = goal
        transactionAssetsForPicker = assets
        showTransactionAssetPicker = true
    }
}

// MARK: - Shared Components

struct GoalContextMenuContent: View {
    let goal: Goal
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onAddAsset: () -> Void
    let onAddTransaction: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void

    var body: some View {
        Group {
            Button("Edit Goal") {
                onEdit()
            }

            Button("Cancel Goal (free allocations)") {
                onCancel()
            }

            Button("Mark Finished (keep allocations)") {
                onFinish()
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

// DetailViewType is now defined in Models/DetailViewType.swift

// MARK: - Preview
