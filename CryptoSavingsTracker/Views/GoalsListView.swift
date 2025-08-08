//
//  GoalsListView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData

struct GoalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Goal.deadline)]) private var goals: [Goal]
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
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
                        ForEach(goals) { goal in
                            NavigationLink(destination: GoalDetailView(goal: goal)) {
                                GoalRowView(goal: goal)
                            }
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
                                    Task {
                                        await NotificationManager.shared.cancelNotifications(for: goal)
                                    }
                                    modelContext.delete(goal)
                                    try? modelContext.save()
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
            .navigationTitle("Crypto Goals")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
#else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
#endif
            }
#if os(macOS)
            .popover(isPresented: $showingAddGoal) {
                AddGoalView()
                    .frame(minWidth: 450, minHeight: 350)
            }
            .sheet(isPresented: .constant(editingGoal != nil)) {
                if let goal = editingGoal {
                    EditGoalView(goal: goal, modelContext: modelContext)
                        .frame(minWidth: 600, minHeight: 700)
                        .onDisappear {
                            editingGoal = nil
                        }
                }
            }
#else
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView()
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingFlowView()
            }
            .sheet(isPresented: .constant(editingGoal != nil)) {
                if let goal = editingGoal {
                    EditGoalView(goal: goal, modelContext: modelContext)
                        .onDisappear {
                            editingGoal = nil
                        }
                }
            }
#endif
    }
    
    private func deleteGoals(offsets: IndexSet) {
        withAnimation(.default) {
            for index in offsets {
                let goal = goals[index]
                Task {
                    await NotificationManager.shared.cancelNotifications(for: goal)
                }
                modelContext.delete(goal)
            }
            try? modelContext.save()
        }
    }
}

struct GoalRowView: View {
    let goal: Goal
    
    private var statusBadge: (text: String, color: Color, icon: String) {
        Task {
            let progress = await goal.getProgress()
            if progress >= 1.0 {
                return ("Achieved", AccessibleColors.success, "checkmark.circle.fill")
            } else if progress >= 0.75 {
                return ("On Track", AccessibleColors.success, "circle.fill")
            } else if goal.daysRemaining < 30 {
                return ("Behind", AccessibleColors.error, "exclamationmark.circle.fill")
            } else {
                return ("In Progress", AccessibleColors.warning, "clock.fill")
            }
        }
        
        // Fallback synchronous calculation
        let progress = goal.progress
        if progress >= 1.0 {
            return ("Achieved", AccessibleColors.success, "checkmark.circle.fill")
        } else if progress >= 0.75 {
            return ("On Track", AccessibleColors.success, "circle.fill")
        } else if goal.daysRemaining < 30 {
            return ("Behind", AccessibleColors.error, "exclamationmark.circle.fill")
        } else {
            return ("In Progress", AccessibleColors.warning, "clock.fill")
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Goal info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal.name)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status badge
                    HStack(spacing: 4) {
                        Image(systemName: statusBadge.icon)
                            .font(.caption2)
                            .foregroundColor(statusBadge.color)
                        
                        Text(statusBadge.text)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(statusBadge.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusBadge.color.opacity(0.1))
                    .cornerRadius(8)
                }
                
                HStack(spacing: 16) {
                    // Days remaining with urgency
                    HStack(spacing: 4) {
                        Image(systemName: goal.daysRemaining < 30 ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.caption2)
                            .foregroundColor(goal.daysRemaining < 30 ? AccessibleColors.error : .accessibleSecondary)
                        
                        Text("\(goal.daysRemaining) days left")
                            .font(.subheadline)
                            .foregroundColor(goal.daysRemaining < 30 ? AccessibleColors.error : .primary)
                    }
                    
                    Spacer()
                    
                    // Target amount
                    Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                        .font(.subheadline)
                        .foregroundColor(.accessibleSecondary)
                }
            }
            
            // Navigation chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.accessibleSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    GoalsListView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}