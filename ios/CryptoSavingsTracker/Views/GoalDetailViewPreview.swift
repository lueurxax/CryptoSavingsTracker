// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalDetailView.swift

import SwiftUI
import SwiftData
import Foundation

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    container.mainContext.insert(goal)
    
    return NavigationStack {
        GoalDetailView(goal: goal)
    }
    .modelContainer(container)
}
