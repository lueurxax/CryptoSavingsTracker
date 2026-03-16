// Extracted preview-only declarations for NAV003 policy compliance.
// Source: AddTransactionView.swift

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    let asset = Asset(currency: "BTC")
    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    
    return AddTransactionView(asset: asset)
        .modelContainer(container)
}
