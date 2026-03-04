// Extracted preview-only declarations for NAV003 policy compliance.
// Source: AddAssetView.swift

import SwiftUI
import SwiftData
import Foundation

#Preview {
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    
    return AddAssetView(goal: goal)
        .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
}
