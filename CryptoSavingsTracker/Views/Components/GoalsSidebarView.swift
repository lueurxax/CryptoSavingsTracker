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
                #if os(macOS)
                .presentationDetents([.large])
                #else
                .presentationDetents([.large])
                #endif
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
    @State private var displayEmoji: String? = nil
    @State private var progressAnimation: Double = 0
    @State private var asyncProgress: Double = 0
    
    private var progressBarColor: Color {
        let progress = asyncProgress
        if progress >= 0.75 {
            return .green
        } else if progress >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Emoji or icon
            if let emoji = displayEmoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.title3)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            
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
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 3)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 1)
                            .fill(progressBarColor)
                            .frame(width: geometry.size.width * progressAnimation, height: 3)
                            .animation(.easeInOut(duration: 0.6), value: progressAnimation)
                    }
                }
                .frame(height: 3)
                
                // Progress percentage
                Text("\(Int(asyncProgress * 100))% complete")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            displayEmoji = goal.emoji
        }
        .task {
            // Load async currency-converted progress
            await loadAsyncProgress()
        }
    }
    
    private func loadAsyncProgress() async {
        // Use the proper service that does currency conversion
        let newProgress = await GoalCalculationService.getProgress(for: goal)
        
        await MainActor.run {
            asyncProgress = newProgress
            
            withAnimation(.easeOut(duration: 0.8)) {
                progressAnimation = newProgress
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