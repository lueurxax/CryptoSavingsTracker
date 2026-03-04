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
        List(selection: $selectedGoal) {
            // Portfolio Overview Section
            Section {
                Button(action: {
                    print("DEBUG: Portfolio Overview button clicked!")
                    selectedGoal = nil
                }) {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundColor(.blue)
                        Text("📊 Portfolio Overview")
                            .foregroundColor(.primary)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
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
    }
    
    private func deleteGoal(_ goal: Goal) {
        withAnimation {
            Task { @MainActor in
                await GoalLifecycleService(modelContext: modelContext).deleteGoal(goal)
            }
            
            let notification = Notification(name: Notification.Name("goalDeleted"), object: goal)
            NotificationCenter.default.post(notification)
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
