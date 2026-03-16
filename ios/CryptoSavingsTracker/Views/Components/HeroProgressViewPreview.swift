// Extracted preview-only declarations for NAV003 policy compliance.
// Source: HeroProgressView.swift

//
//  HeroProgressView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
    
    let goal = Goal(name: "Emergency Fund", currency: "EUR", targetAmount: 1600, deadline: Date().addingTimeInterval(86400 * 85))
    container.mainContext.insert(goal)
    
    return ScrollView {
        HeroProgressView(goal: goal)
            .padding()
    }
    .modelContainer(container)
}
