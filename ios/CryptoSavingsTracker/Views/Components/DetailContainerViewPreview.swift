// Extracted preview-only declarations for NAV003 policy compliance.
// Source: DetailContainerView.swift

//
//  DetailContainerView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    if let container = try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config) {
        let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
        container.mainContext.insert(goal)

        return AnyView(
            NavigationStack {
                DetailContainerView(goal: goal, selectedView: .constant(DetailViewType.details))
            }
            .modelContainer(container)
        )
    }
    return AnyView(
        ContentUnavailableView(
            "Preview unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("SwiftData in-memory container failed to initialize.")
        )
        .padding()
    )
}
