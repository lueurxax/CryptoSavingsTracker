// Extracted preview-only declarations for NAV003 policy compliance.
// Source: EnhancedDashboardComponents.swift

//
//  EnhancedDashboardComponents.swift
//  CryptoSavingsTracker
//
//  Enhanced dashboard components with improved visuals and insights
//

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    let viewModel = DIContainer.shared.makeDashboardViewModel()
    
    return ScrollView {
        VStack(spacing: 16) {
            EnhancedStatsGrid(viewModel: viewModel, goal: goal)
            InsightsView(viewModel: viewModel, goal: goal)
        }
        .padding()
    }
    .modelContainer(container)
}
