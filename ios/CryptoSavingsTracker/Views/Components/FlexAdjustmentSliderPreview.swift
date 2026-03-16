// Extracted preview-only declarations for NAV003 policy compliance.
// Source: FlexAdjustmentSlider.swift

//
//  FlexAdjustmentSlider.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI
import SwiftData
import Combine

#Preview("Flex Slider") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
    let context = container.mainContext
    
    let viewModel = MonthlyPlanningViewModel(modelContext: context)
    
    ScrollView {
        VStack(spacing: 20) {
            FlexAdjustmentSlider(viewModel: viewModel)
            
            // Demo content
            Rectangle()
                .fill(.secondary.opacity(0.1))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Text("Other Planning Controls")
                        .foregroundColor(.secondary)
                )
        }
        .padding()
    }
    .modelContainer(container)
}
