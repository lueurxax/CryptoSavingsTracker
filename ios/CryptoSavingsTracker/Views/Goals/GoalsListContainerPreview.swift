// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalsListContainer.swift

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal1)
    
    return GoalsListContainer(selectedView: .constant(DetailViewType.details))
        .modelContainer(container)
}
