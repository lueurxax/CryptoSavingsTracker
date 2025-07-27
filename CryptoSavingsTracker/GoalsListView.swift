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
    
    var body: some View {
        NavigationView {
            List {
                ForEach(goals) { goal in
                    NavigationLink(destination: GoalDetailView(goal: goal)) {
                        GoalRowView(goal: goal)
                    }
                }
                .onDelete(perform: deleteGoals)
                .animation(.default, value: goals.count)
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
#else
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView()
            }
#endif
        }
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
    @ObservedObject var goal: Goal
    @State private var currentTotal: Double = 0
    @State private var progress: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.name)
                    .font(.headline)
                Spacer()
                Text("\(goal.daysRemaining) days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(currentTotal, specifier: "%.2f") / \(goal.targetAmount, specifier: "%.2f") \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding(.vertical, 4)
        .task {
            await updateValues()
        }
        .onChange(of: goal.assets) {
            Task {
                await updateValues()
            }
        }
    }
    
    private func updateValues() async {
        let total = await goal.getCurrentTotal()
        let prog = await goal.getProgress()
        
        
        await MainActor.run {
            currentTotal = total
            progress = prog
        }
    }
}

#Preview {
    GoalsListView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}