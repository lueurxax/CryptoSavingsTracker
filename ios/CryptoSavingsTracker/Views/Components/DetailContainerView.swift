//
//  DetailContainerView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

// DetailViewType is now a shared enum

/// Container view for goal detail screens without nested tab chrome.
struct DetailContainerView: View {
    let goal: Goal
    @Binding var selectedView: DetailViewType
    
    var body: some View {
        Group {
            switch selectedView {
            case .details:
                GoalDetailView(goal: goal)
            case .dashboard:
                DashboardViewForGoal(goal: goal)
            }
        }
        .animation(.easeInOut, value: selectedView)
        .navigationTitle(goal.name)
        .modifier(InlineNavBarModifier())
    }
}
