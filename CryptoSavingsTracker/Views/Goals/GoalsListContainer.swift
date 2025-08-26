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
    @Query private var goals: [Goal]
    @Binding var selectedView: DetailViewType
    @Environment(\.modelContext) private var modelContext
    @State private var editingGoal: Goal?
    @State private var refreshTrigger = UUID()
    
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
                                .tint(.red)
                                
                                Button("Edit") {
                                    editingGoal = goal
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                GoalContextMenu(
                                    goal: goal, 
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
                if PlatformManager.shared.capabilities.supportsHapticFeedback {
                    setupShortcuts()
                }
            }
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: modelContext)
                .presentationDetents([.large])
        }
    }
    
    // MARK: - Private Methods
    
    private func deleteGoal(_ goal: Goal) {
        withAnimation {
            Task {
                await NotificationManager.shared.cancelNotifications(for: goal)
            }
            modelContext.delete(goal)
            try? modelContext.save()
            
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

/// Context menu for goal actions
struct GoalContextMenu: View {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal1)
    
    return GoalsListContainer(selectedView: .constant(DetailViewType.details))
        .modelContainer(container)
}
