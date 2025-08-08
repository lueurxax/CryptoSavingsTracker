//
//  DetailContainerView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

// DetailViewType is now a shared enum

/// Container view for goal detail screens with tab selection
struct DetailContainerView: View {
    let goal: Goal
    @Binding var selectedView: DetailViewType
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        TabView(selection: $selectedView) {
            GoalDetailView(goal: goal)
                .tabItem {
                    Image(systemName: "target")
                    Text("Details")
                }
                .tag(DetailViewType.details)
            
            DashboardViewForGoal(goal: goal)
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Dashboard")
                }
                .tag(DetailViewType.dashboard)
        }
        .navigationTitle(goal.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    return NavigationStack {
        DetailContainerView(goal: goal, selectedView: .constant(DetailViewType.details))
    }
    .modelContainer(container)
}