//
//  FlexAdjustmentView.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftUI
import SwiftData
import Combine

struct FlexAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Goal> { goal in
            goal.lifecycleStatusRawValue == "active"
        },
        sort: \Goal.deadline
    )
    private var goals: [Goal]
    
    @StateObject private var viewModel = FlexAdjustmentViewModel()
    @State private var flexPercentage: Double = 100
    @State private var redistributionStrategy: RedistributionStrategy = .balanced
    @State private var protectedGoals: Set<UUID> = []
    @State private var hasStartedTelemetryFlow = false
    
    enum RedistributionStrategy: String, CaseIterable {
        case balanced = "Balanced"
        case urgent = "Urgent First"
        case largest = "Largest First"
        case riskMinimizing = "Minimize Risk"
    }

    private var isDirty: Bool {
        abs(flexPercentage - 100) > 0.001 || redistributionStrategy != .balanced || !protectedGoals.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Adjustment Controls
                adjustmentSection
                
                // Strategy Selection
                strategySection
                
                // Impact Preview
                impactPreview
                
                // Goals List with Adjustments
                adjustedGoalsList
            }
            .navigationTitle("Flex Adjustment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        DIContainer.shared.navigationTelemetryTracker.cancelled(
                            journeyID: NavigationJourney.goalContributionEditCancel,
                            isDirty: isDirty,
                            cancelStage: "toolbar_cancel"
                        )
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyAdjustments()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canApplyAdjustments)
                }
            }
        }
        .task {
            await viewModel.initialize(goals: goals, modelContext: modelContext)
            if !hasStartedTelemetryFlow {
                hasStartedTelemetryFlow = true
                DIContainer.shared.navigationTelemetryTracker.flowStarted(
                    journeyID: NavigationJourney.goalContributionEditCancel,
                    entryPoint: "flex_adjustment_sheet"
                )
            }
        }
    }
    
    private var adjustmentSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    Text("Payment Adjustment")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(Int(flexPercentage))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(colorForPercentage(flexPercentage))
                }
                
                Slider(value: $flexPercentage, in: 0...200, step: 5)
                    .tint(colorForPercentage(flexPercentage))
                    .onChange(of: flexPercentage) { _, newValue in
                        Task {
                            await viewModel.calculateAdjustments(
                                percentage: newValue,
                                strategy: redistributionStrategy,
                                protectedGoals: protectedGoals
                            )
                        }
                    }
            }
            
            // Quick Presets
            HStack(spacing: 12) {
                ForEach([0, 25, 50, 100, 150], id: \.self) { percentage in
                    Button("\(percentage)%") {
                        withAnimation {
                            flexPercentage = Double(percentage)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(flexPercentage == Double(percentage) ? .accessiblePrimary : .secondary)
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color.accessibleSurfaceSubtle)
        #else
        .background(Color.gray.opacity(0.1))
        #endif
    }
    
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Redistribution Strategy")
                .font(.headline)
            
            Picker("Strategy", selection: $redistributionStrategy) {
                ForEach(RedistributionStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: redistributionStrategy) { _, newStrategy in
                Task {
                    await viewModel.calculateAdjustments(
                        percentage: flexPercentage,
                        strategy: newStrategy,
                        protectedGoals: protectedGoals
                    )
                }
            }
            
            Text(strategyDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color.accessibleSurface)
        #else
        .background(Color.accessibleSurface)
        #endif
    }
    
    private var strategyDescription: String {
        switch redistributionStrategy {
        case .balanced:
            return "Distribute adjustment equally across all goals"
        case .urgent:
            return "Prioritize goals with nearest deadlines"
        case .largest:
            return "Reduce largest payment amounts first"
        case .riskMinimizing:
            return "Minimize impact on goal completion dates"
        }
    }
    
    private var impactPreview: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(CurrencyFormatter.format(amount: viewModel.originalTotal, currency: "USD"))
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Adjusted Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(CurrencyFormatter.format(amount: viewModel.adjustedTotal, currency: "USD"))
                        .font(.headline)
                        .foregroundColor(colorForPercentage(flexPercentage))
                }
            }
            
            if viewModel.hasRiskAnalysis {
                Divider()
                
                HStack {
                    Label("\(viewModel.goalsAtRisk) goals may be delayed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(AccessibleColors.warning)
                    
                    Spacer()
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color.accessibleSurfaceSubtle)
        #else
        .background(Color.gray.opacity(0.1))
        #endif
    }
    
    private var adjustedGoalsList: some View {
        List {
            ForEach(viewModel.adjustedRequirements) { requirement in
                FlexGoalRow(
                    requirement: requirement,
                    isProtected: protectedGoals.contains(requirement.goalId),
                    onProtectionToggle: { isProtected in
                        if isProtected {
                            protectedGoals.insert(requirement.goalId)
                        } else {
                            protectedGoals.remove(requirement.goalId)
                        }
                        
                        Task {
                            await viewModel.calculateAdjustments(
                                percentage: flexPercentage,
                                strategy: redistributionStrategy,
                                protectedGoals: protectedGoals
                            )
                        }
                    }
                )
            }
        }
        .listStyle(.plain)
    }
    
    private func colorForPercentage(_ percentage: Double) -> Color {
        switch percentage {
        case 0..<50:
            return AccessibleColors.error
        case 50..<75:
            return AccessibleColors.warning
        case 75..<125:
            return AccessibleColors.primaryInteractive
        case 125..<175:
            return AccessibleColors.success
        default:
            return AccessibleColors.chartColor(at: 3)
        }
    }
    
    private func applyAdjustments() {
        // Save adjustments to user preferences or apply to monthly planning
        DIContainer.shared.navigationTelemetryTracker.flowCompleted(
            journeyID: NavigationJourney.goalContributionEditCancel,
            result: "applied"
        )
        dismiss()
    }
}

struct FlexGoalRow: View {
    let requirement: MonthlyRequirement
    let isProtected: Bool
    let onProtectionToggle: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.goalName)
                        .font(.headline)
                    
                    Text("\(requirement.monthsRemaining) months remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    onProtectionToggle(!isProtected)
                } label: {
                    Image(systemName: isProtected ? "lock.fill" : "lock.open")
                        .foregroundColor(isProtected ? .accessiblePrimary : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(CurrencyFormatter.format(amount: requirement.monthlyAmount, currency: requirement.displayCurrency))
                        .font(.callout)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adjusted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(CurrencyFormatter.format(amount: requirement.displayAmount, currency: requirement.displayCurrency))
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(
                            isProtected
                                ? .accessiblePrimary
                                : colorForChange(from: requirement.monthlyAmount, to: requirement.displayAmount)
                        )
                }
                
                Spacer()
            }
            
            if let risk = requirement.riskLevel {
                HStack {
                    Image(systemName: riskIcon(for: risk))
                        .font(.caption)
                    
                    Text(riskDescription(for: risk))
                        .font(.caption)
                }
                .foregroundColor(riskColor(for: risk))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func colorForChange(from original: Double, to adjusted: Double) -> Color {
        let change = (adjusted - original) / original
        if change < -0.5 {
            return AccessibleColors.error
        } else if change < -0.25 {
            return AccessibleColors.warning
        } else if change < 0.25 {
            return .primary
        } else if change < 0.5 {
            return AccessibleColors.success
        } else {
            return AccessibleColors.chartColor(at: 3)
        }
    }
    
    private func riskIcon(for risk: MonthlyRequirement.RiskLevel) -> String {
        switch risk {
        case .low:
            return "checkmark.circle"
        case .medium:
            return "exclamationmark.circle"
        case .high:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }
    
    private func riskDescription(for risk: MonthlyRequirement.RiskLevel) -> String {
        switch risk {
        case .low:
            return "Low risk"
        case .medium:
            return "May delay completion"
        case .high:
            return "Significant delay expected"
        case .critical:
            return "Goal at risk"
        }
    }
    
    private func riskColor(for risk: MonthlyRequirement.RiskLevel) -> Color {
        switch risk {
        case .low:
            return AccessibleColors.success
        case .medium:
            return AccessibleColors.warning
        case .high:
            return AccessibleColors.error
        case .critical:
            return AccessibleColors.chartColor(at: 3)
        }
    }
}

@MainActor
class FlexAdjustmentViewModel: ObservableObject {
    @Published var originalTotal: Double = 0
    @Published var adjustedTotal: Double = 0
    @Published var adjustedRequirements: [MonthlyRequirement] = []
    @Published var goalsAtRisk: Int = 0
    @Published var hasRiskAnalysis: Bool = false
    @Published var canApplyAdjustments: Bool = false
    
    private var flexService: FlexAdjustmentService?
    private var originalRequirements: [MonthlyRequirement] = []
    
    func initialize(goals: [Goal], modelContext: ModelContext) async {
        flexService = DIContainer.shared.makeFlexAdjustmentService(modelContext: modelContext)
        
        // Calculate original requirements
        let monthlyService = DIContainer.shared.monthlyPlanningService
        originalRequirements = await monthlyService.calculateMonthlyRequirements(for: goals)
        
        originalTotal = originalRequirements.reduce(0) { $0 + $1.monthlyAmount }
        adjustedTotal = originalTotal
        adjustedRequirements = originalRequirements
        canApplyAdjustments = true
    }
    
    func calculateAdjustments(percentage: Double, strategy: FlexAdjustmentView.RedistributionStrategy, protectedGoals: Set<UUID>) async {
        guard let flexService = flexService else { return }
        
        // Map strategy to service strategy
        let serviceStrategy: RedistributionStrategy
        switch strategy {
        case .balanced:
            serviceStrategy = .balanced
        case .urgent:
            serviceStrategy = .prioritizeUrgent
        case .largest:
            serviceStrategy = .prioritizeLargest
        case .riskMinimizing:
            serviceStrategy = .minimizeRisk
        }
        
        // Calculate adjustment amount (negative for reduction, positive for increase)
        let adjustment = (percentage - 100.0) / 100.0
        
        let adjustedResults = await flexService.applyFlexAdjustment(
            requirements: originalRequirements,
            adjustment: adjustment,
            protectedGoalIds: protectedGoals,
            skippedGoalIds: Set<UUID>(),  // No skipped goals for now
            strategy: serviceStrategy
        )
        
        await MainActor.run {
            // Convert AdjustedRequirement back to MonthlyRequirement with adjusted amounts
            self.adjustedRequirements = adjustedResults.map { adjusted in
                let req = adjusted.requirement
                // Create new requirement with adjusted amount
                return MonthlyRequirement(
                    goalId: req.goalId,
                    goalName: req.goalName,
                    currency: req.currency,
                    targetAmount: req.targetAmount,
                    currentTotal: req.currentTotal,
                    remainingAmount: req.remainingAmount,
                    monthsRemaining: req.monthsRemaining,
                    requiredMonthly: adjusted.adjustedAmount,  // Use adjusted amount here
                    progress: req.progress,
                    deadline: req.deadline,
                    status: req.status
                )
            }
            self.adjustedTotal = adjustedResults.reduce(0) { $0 + $1.adjustedAmount }
            self.goalsAtRisk = adjustedResults.filter { $0.impactAnalysis.estimatedDelay > 0 }.count
            self.hasRiskAnalysis = !adjustedResults.isEmpty
        }
    }
}
