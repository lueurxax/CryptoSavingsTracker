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
    @Binding var selectedGoal: Goal?
    @Environment(\.modelContext) private var modelContext
    @State private var editingGoal: Goal?
    
    var body: some View {
        List(goals, selection: $selectedGoal) { goal in
            GoalSidebarRow(goal: goal)
                .tag(goal)
                .contextMenu {
                    GoalSidebarContextMenu(
                        goal: goal, 
                        onDelete: { deleteGoal(goal) },
                        onEdit: { editingGoal = goal }
                    )
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
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: modelContext)
        }
    }
    
    private func deleteGoal(_ goal: Goal) {
        withAnimation {
            Task {
                await NotificationManager.shared.cancelNotifications(for: goal)
            }
            modelContext.delete(goal)
            try? modelContext.save()
            
            let notification = Notification(name: Notification.Name("goalDeleted"), object: goal)
            NotificationCenter.default.post(notification)
        }
    }
}

/// Individual row in the goals sidebar
struct GoalSidebarRow: View {
    let goal: Goal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goal.name)
                .font(.headline)
                .fontWeight(.medium)
            
            HStack {
                Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(goal.daysRemaining) days left")
                    .font(.caption2)
                    .foregroundColor(goal.daysRemaining < 30 ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let goal2 = Goal(name: "Ethereum Fund", currency: "USD", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))
    
    container.mainContext.insert(goal1)
    container.mainContext.insert(goal2)
    
    return GoalsSidebarView(goals: [goal1, goal2], selectedGoal: .constant(goal1))
        .modelContainer(container)
}