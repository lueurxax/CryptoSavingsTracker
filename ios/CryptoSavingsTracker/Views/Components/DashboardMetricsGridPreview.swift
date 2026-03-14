// Extracted preview-only declarations for NAV003 policy compliance.
// Source: DashboardMetricsGrid.swift

//
//  DashboardMetricsGrid.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 45))
    container.mainContext.insert(goal)
    
    return VStack {
        DashboardMetricsGrid(goal: goal)
        Spacer()
    }
    .padding()
    .modelContainer(container)
}
