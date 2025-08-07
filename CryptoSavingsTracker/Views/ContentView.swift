//
//  ContentView.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("preferAdvancedDashboard") private var preferAdvancedDashboard = false
    @Query private var goals: [Goal]
    
    var body: some View {
        TabView {
            GoalsListView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
            
            Group {
                if preferAdvancedDashboard && !goals.isEmpty {
                    // Show advanced dashboard for first goal (or add goal selection)
                    if let firstGoal = goals.first {
                        DashboardView(goal: firstGoal)
                    } else {
                        SimpleDashboardView()
                    }
                } else {
                    SimpleDashboardView()
                }
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
