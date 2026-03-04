// Extracted preview-only declarations for NAV003 policy compliance.
// Source: MonthlyPlanningWidget.swift

import SwiftUI
import SwiftData
import Foundation

#Preview("Compact") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self, configurations: config)
    let context = container.mainContext
    
    let viewModel = MonthlyPlanningViewModel(modelContext: context)
    
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                MonthlyPlanningWidget(viewModel: viewModel)
                
                // Other dashboard widgets would go here
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
    }
    .modelContainer(container)
}
