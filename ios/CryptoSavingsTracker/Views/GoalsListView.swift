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
    @Query(
        filter: #Predicate<Goal> { goal in
            goal.lifecycleStatusRawValue == "active"
        },
        sort: [SortDescriptor(\Goal.deadline)]
    )
    private var goals: [Goal]
    @State private var refreshTrigger = UUID()
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var selectedGoalForLifecycleAction: Goal?
    @State private var showingLifecycleActions = false
    @State private var showingOnboarding = false

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
                                        Task { @MainActor in
                                            await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
                                        }
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
        withAnimation(.default) {
            for index in offsets {
                let goal = goals[index]
                Task { @MainActor in
                    await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
                }
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
