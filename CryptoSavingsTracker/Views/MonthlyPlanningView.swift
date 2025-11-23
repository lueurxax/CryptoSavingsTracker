//
//  MonthlyPlanningView.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftUI
import SwiftData

struct MonthlyPlanningView: View {
    @Query(sort: \Goal.deadline) private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var viewModel: MonthlyPlanningViewModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let viewModel = viewModel {
                    // Monthly Planning Widget
                    MonthlyPlanningWidget(viewModel: viewModel)
                    
                    // Goal Requirements List
                    if !viewModel.monthlyRequirements.isEmpty {
                        requirementsList(for: viewModel.monthlyRequirements)
                    }
                } else {
                    ProgressView("Loading...")
                }
            }
            .padding()
        }
        .navigationTitle("Monthly Planning")
        .onAppear {
            if viewModel == nil {
                viewModel = MonthlyPlanningViewModel(modelContext: modelContext)
            }
        }
        .task {
            if let viewModel = viewModel {
                await viewModel.loadMonthlyRequirements()
            }
        }
    }
    
    private func requirementsList(for requirements: [MonthlyRequirement]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Goal Requirements")
                .font(.headline)
            
            ForEach(requirements) { requirement in
                RequirementRow(requirement: requirement)
            }
        }
    }
}

struct RequirementRow: View {
    let requirement: MonthlyRequirement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(requirement.goalName)
                    .font(.headline)
                
                Spacer()
                
                Text("\(requirement.monthsRemaining) months")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Required Monthly:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(CurrencyFormatter.format(amount: requirement.requiredMonthly, currency: requirement.currency))
                    .font(.callout)
                    .fontWeight(.medium)
            }
            
            let pct = min(max(requirement.progress, 0), 1)
            ProgressView(value: pct)
                .tint(requirement.status == .critical ? .red : 
                      requirement.status == .attention ? .orange : .blue)
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemGray6))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .cornerRadius(12)
    }
}
