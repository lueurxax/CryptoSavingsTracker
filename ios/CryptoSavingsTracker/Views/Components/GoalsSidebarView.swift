//
//  GoalsSidebarView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

/// Sidebar view for macOS showing list of goals
struct GoalsSidebarView: View {
    let goals: [Goal]
    let archivedGoals: [Goal]
    @Binding var selectedGoal: Goal?
    @Environment(\.modelContext) private var modelContext
    @State private var editingGoal: Goal?
    @State private var lifecycleErrorTitle = "Goal Not Updated"
    @State private var lifecycleErrorMessage: String?

    init(
        goals: [Goal],
        archivedGoals: [Goal] = [],
        selectedGoal: Binding<Goal?>
    ) {
        self.goals = goals
        self.archivedGoals = archivedGoals
        _selectedGoal = selectedGoal
    }
    
    var body: some View {
        List(selection: $selectedGoal) {
            // Portfolio Overview Section
            Section {
                Button(action: {
                    selectedGoal = nil
                }) {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(AccessibleColors.primaryInteractive)
                        Text("Portfolio Overview")
                            .foregroundStyle(AccessibleColors.primaryText)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(AccessibleColors.primaryInteractiveBackground)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Portfolio overview")
                .accessibilityHint("Shows a summary of all goals and assets.")
                .accessibilityIdentifier("goals.sidebar.portfolio_overview")
            }
            
            // Individual Goals Section  
            Section("Your Goals") {
                ForEach(goals) { goal in
                    UnifiedGoalRowView.macOS(goal: goal)
                        .tag(goal)
                        .contextMenu {
                            GoalSidebarContextMenu(
                                goal: goal, 
                                onDelete: { deleteGoal(goal) },
                                onEdit: { editingGoal = goal }
                            )
                        }
                }
            }

            if !archivedGoals.isEmpty {
                Section("Archived Goals") {
                    ForEach(archivedGoals) { goal in
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(AccessibleColors.secondaryText)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.name)
                                    .font(.body.weight(.medium))
                                Text("\(goal.currency) target: \(goal.targetAmount.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                            }

                            Spacer()

                            Button("Restore") {
                                restoreGoal(goal)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("restoreGoalButton-\(goal.name)")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("archivedGoalRow-\(goal.name)")
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: AddGoalView()) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add goal")
            }
        }
        // NAV-MOD: MOD-01
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: modelContext)
                .presentationDetents([.large])
        }
        .alert(
            lifecycleErrorTitle,
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
    }
    
    private func deleteGoal(_ goal: Goal) {
        Task { @MainActor in
            do {
                try await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
            } catch {
                lifecycleErrorTitle = "Goal Not Updated"
                lifecycleErrorMessage = "Unable to delete this goal. Please try again."
            }
        }
    }

    private func restoreGoal(_ goal: Goal) {
        Task { @MainActor in
            do {
                try await DIContainer.shared
                    .makeGoalMutationService(modelContext: modelContext)
                    .restoreGoal(goal)
                selectedGoal = goal
            } catch {
                lifecycleErrorTitle = "Goal Not Restored"
                lifecycleErrorMessage = "Unable to restore this goal. Please try again."
            }
        }
    }
}



/// Context menu for goal actions in sidebar
struct GoalSidebarContextMenu: View {
    let goal: Goal
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        Group {
            Button("Edit Goal") {
                onEdit()
            }
            
            Button("Add Asset") {
                // Add asset action
            }
            
            Button("Add Transaction") {
                // Add transaction action
            }
            
            Divider()
            
            Button("Delete Goal", role: .destructive) {
                onDelete()
            }
        }
    }
}
