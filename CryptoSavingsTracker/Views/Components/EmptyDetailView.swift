//
//  EmptyDetailView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData
import Foundation

/// Empty state view for when no goal is selected in detail pane
struct EmptyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var monthlyPlanningViewModel: MonthlyPlanningViewModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Monthly Planning Widget
                if let viewModel = monthlyPlanningViewModel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Portfolio Overview")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        MonthlyPlanningWidget(viewModel: viewModel)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                
                // Empty state content
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    // Text content
                    VStack(spacing: 8) {
                        Text("Select a Goal")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Choose a goal from the sidebar to view its details and progress")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if monthlyPlanningViewModel == nil {
                monthlyPlanningViewModel = MonthlyPlanningViewModel(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    EmptyDetailView()
}