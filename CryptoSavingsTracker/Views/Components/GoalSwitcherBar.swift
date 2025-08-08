//
//  GoalSwitcherBar.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct GoalSwitcherBar: View {
    @Binding var selectedGoal: Goal?
    let goals: [Goal]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Goal")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.accessibleSecondary)
                .padding(.horizontal, 16)
            
            if goals.isEmpty {
                EmptyGoalSwitcher()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(goals) { goal in
                            GoalPill(
                                goal: goal,
                                isSelected: selectedGoal?.id == goal.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedGoal = goal
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear {
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
        }
    }
}

struct GoalPill: View {
    let goal: Goal
    let isSelected: Bool
    let onTap: () -> Void
    @State private var progress: Double = 0
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(goal.name)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundColor(isSelected ? .accessiblePrimary : .primary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 0)
                    
                    // Progress indicator
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 0.75 ? AccessibleColors.success :
                                progress >= 0.5 ? AccessibleColors.warning : 
                                AccessibleColors.primaryInteractive,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                
                // Quick stats
                HStack(spacing: 8) {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                    
                    Text("\(goal.daysRemaining)d left")
                        .font(.caption2)
                        .foregroundColor(
                            goal.daysRemaining < 30 ? AccessibleColors.error :
                            goal.daysRemaining < 60 ? AccessibleColors.warning :
                            .accessibleSecondary
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AccessibleColors.primaryInteractive.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? AccessibleColors.primaryInteractive : Color.clear,
                                lineWidth: isSelected ? 2 : 0
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            progress = await goal.getProgress()
        }
        .onChange(of: goal.assets) { _, _ in
            Task {
                progress = await goal.getProgress()
            }
        }
    }
}

struct EmptyGoalSwitcher: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 32))
                .foregroundColor(.accessibleSecondary)
            
            VStack(spacing: 4) {
                Text("No Goals Yet")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("Create your first savings goal to start tracking")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

#Preview {
    @Previewable @State var selectedGoal: Goal? = nil
    
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 30))
    let goal2 = Goal(name: "Ethereum Fund", currency: "USD", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))
    let goal3 = Goal(name: "Emergency Crypto", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86400 * 90))
    
    return VStack {
        GoalSwitcherBar(selectedGoal: $selectedGoal, goals: [goal1, goal2, goal3])
        Spacer()
    }
    .modelContainer(container)
    .onAppear {
        container.mainContext.insert(goal1)
        container.mainContext.insert(goal2)
        container.mainContext.insert(goal3)
        selectedGoal = goal1
    }
}