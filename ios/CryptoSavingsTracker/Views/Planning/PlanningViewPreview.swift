// Extracted preview-only declarations for NAV003 policy compliance.
// Source: PlanningView.swift

import SwiftUI
import SwiftData

#Preview("iOS Compact") {
    let modelContext = CryptoSavingsTrackerApp.sharedModelContainer.mainContext
    NavigationStack {
        iOSCompactPlanningView(
            viewModel: MonthlyPlanningViewModel(modelContext: modelContext),
            staleDrafts: []
        )
    }
    .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
}

#Preview("macOS") {
    let modelContext = CryptoSavingsTrackerApp.sharedModelContainer.mainContext
    NavigationStack {
        macOSPlanningView(
            viewModel: MonthlyPlanningViewModel(modelContext: modelContext),
            staleDrafts: []
        )
    }
    .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
    .frame(width: 800, height: 600)
}
