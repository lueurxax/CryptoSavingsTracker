//
//  GoalsSidebarContainer.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

/// macOS-specific goals sidebar container with split view navigation
struct GoalsSidebarContainer: View {
    @Query private var goals: [Goal]
    @Binding var selectedGoal: Goal?
    @Binding var selectedView: DetailViewType
    
    var body: some View {
        NavigationSplitView {
            GoalsSidebarView(
                goals: goals,
                selectedGoal: $selectedGoal
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let goal = selectedGoal {
                DetailContainerView(
                    goal: goal,
                    selectedView: $selectedView
                )
            } else {
                EmptyDetailView()
            }
        }
        .onAppear {
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goalDeleted)) { notification in
            if let deletedGoal = notification.object as? Goal,
               selectedGoal?.id == deletedGoal.id {
                selectedGoal = goals.first
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
    
    return GoalsSidebarContainer(
        selectedGoal: .constant(goal1),
        selectedView: .constant(DetailViewType.details)
    )
    .modelContainer(container)
}