//
//  GoalComparisonView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct GoalComparisonView: View {
    @Query private var goals: [Goal]
    @State private var selectedGoals: Set<Goal> = []
    
    var body: some View {
        NavigationView {
            List(goals) { goal in
                GoalSelectionRow(
                    goal: goal,
                    isSelected: selectedGoals.contains(goal),
                    onToggle: {
                        if selectedGoals.contains(goal) {
                            selectedGoals.remove(goal)
                        } else {
                            selectedGoals.insert(goal)
                        }
                    }
                )
            }
            .navigationTitle("Select Goals to Compare")
            .frame(minWidth: 250)
            
            if selectedGoals.isEmpty {
                EmptyComparisonView()
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: min(selectedGoals.count, 3)), spacing: 16) {
                        ForEach(Array(selectedGoals)) { goal in
                            GoalComparisonCard(goal: goal)
                        }
                    }
                    .platformPadding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct GoalSelectionRow: View {
    let goal: Goal
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading) {
                Text(goal.name)
                    .font(.headline)
                Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct EmptyComparisonView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select Goals to Compare")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Choose 2-4 goals from the sidebar to see a side-by-side comparison")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GoalComparisonCard: View {
    let goal: Goal
    @State private var progress: Double = 0
    @State private var currentTotal: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress Ring (smaller)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Complete")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Key Stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.0f", currentTotal)) \(goal.currency)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Days Left:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(goal.daysRemaining)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(goal.daysRemaining < 30 ? .red : .primary)
                }
                
                HStack {
                    Text("Assets:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(goal.assets.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .platformPadding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        .task {
            progress = await GoalCalculationService.getProgress(for: goal)
            currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
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
    
    return GoalComparisonView()
        .modelContainer(container)
}