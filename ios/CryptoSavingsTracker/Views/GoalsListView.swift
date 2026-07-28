//
//  GoalsListView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
import Foundation

struct GoalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @State private var refreshTrigger = UUID()
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var selectedGoalForLifecycleAction: Goal?
    @State private var showingLifecycleActions = false
    @State private var showingOnboarding = false
    @State private var lifecycleErrorMessage: String?

    init() {
        _goals = Query(
            filter: GoalListQuery.activePredicate,
            sort: \Goal.deadline,
            order: .forward
        )
    }

    var body: some View {
        Group {
                if goals.isEmpty {
                    EmptyStateView.noGoals(
                        onCreateGoal: {
                            showingAddGoal = true
                        },
                        onStartOnboarding: {
                            showingOnboarding = true
                        }
                    )
                } else {
                    List {
                        // Unallocated Assets Warning Section
                        Section {
                            UnallocatedAssetsSection()
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        Section {
                            GoalsListMVPGuidanceCard()
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        // Individual Goals
                        Section("Your Goals") {
                            ForEach(goals) { goal in
                                NavigationLink(destination: GoalDetailView(goal: goal)) {
                                    UnifiedGoalRowView.iOS(goal: goal, refreshTrigger: refreshTrigger)
                                        .id("\(goal.id)-\(refreshTrigger)") // Force refresh when goal changes or when triggered
                                }
                                .accessibilityIdentifier("goalRow-\(goal.name)")
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.regularMaterial)
                                        .padding(.vertical, 2)
                                )
                                .contextMenu {
                                    Button {
                                        editingGoal = goal
                                    } label: {
                                        HStack {
                                            Text("Edit Goal")
                                            Image(systemName: "pencil")
                                        }
                                    }

                                    Button {
                                        selectedGoalForLifecycleAction = goal
                                        showingLifecycleActions = true
                                    } label: {
                                        HStack {
                                            Text("Goal Status…")
                                            Image(systemName: "flag")
                                        }
                                    }

                                    Button {
                                        deleteGoal(goal)
                                    } label: {
                                        HStack {
                                            Text("Delete Goal")
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                            }
                            .onDelete(perform: deleteGoals)
                            .animation(.default, value: goals.count)
                        }
                    }
                }
            }
            .navigationTitle("Crypto Goals")
            // NAV-MOD: MOD-04
            .confirmationDialog(
                "Update Goal Status",
                isPresented: $showingLifecycleActions,
                titleVisibility: .visible
            ) {
                if let goal = selectedGoalForLifecycleAction {
                    Button("Cancel Goal (free allocations)", role: .destructive) {
                        cancelGoal(goal)
                    }
                    Button("Mark Finished (keep allocations)") {
                        finishGoal(goal)
                    }
                }
                Button("Close", role: .cancel) { }
            }
            .alert(
                "Goal Not Updated",
                isPresented: Binding(
                    get: { lifecycleErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            lifecycleErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    lifecycleErrorMessage = nil
                }
            } message: {
                Text(lifecycleErrorMessage ?? "Unable to update this goal right now.")
            }
            .onAppear {
                // Debug log all loaded goals
                for _ in goals {
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .goalProgressRefreshed)) { _ in
                // Refresh all goal rows when any goal is refreshed
                refreshTrigger = UUID()
            }
            .onChange(of: editingGoal) { oldValue, newValue in
                // When edit dialog closes, force refresh goal data
                if oldValue != nil && newValue == nil {

                    // Force SwiftData to refresh by calling processPendingChanges
                    modelContext.processPendingChanges()

                    // Force view refresh by updating refresh trigger
                    refreshTrigger = UUID()

                    // Log updated goal data
                    for _ in goals {
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .platformModal(isPresented: $showingAddGoal) {
                AddGoalView()
            }
            .platformModal(isPresented: .constant(editingGoal != nil)) {
                if let goal = editingGoal {
                    EditGoalView(goal: goal, modelContext: modelContext)
                        .onDisappear {
                            editingGoal = nil
                        }
                }
            }
    }

    private func deleteGoals(offsets: IndexSet) {
        for index in offsets {
            deleteGoal(goals[index])
        }
    }

    private func deleteGoal(_ goal: Goal) {
        Task { @MainActor in
            do {
                try await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
            } catch {
                lifecycleErrorMessage = "Unable to delete this goal. Please try again."
            }
        }
    }

    private func cancelGoal(_ goal: Goal) {
        Task { @MainActor in
            do {
                try await GoalLifecycleService(modelContext: modelContext).cancelGoal(goal)
            } catch {
                lifecycleErrorMessage = "Unable to cancel this goal. Please try again."
            }
        }
    }

    private func finishGoal(_ goal: Goal) {
        Task { @MainActor in
            do {
                try await GoalLifecycleService(modelContext: modelContext).finishGoal(goal)
            } catch {
                lifecycleErrorMessage = "Unable to finish this goal. Please try again."
            }
        }
    }
}

private struct GoalsListMVPGuidanceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Getting Started", systemImage: "flag.2.crossed")
                .font(.headline)
            Text("Create goals here, then add assets and contributions from each goal to keep progress moving.")
                .font(.subheadline)
                .foregroundStyle(AccessibleColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}
