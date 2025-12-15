//
//  MonthlyPlanningWidget.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI
import SwiftData
import Foundation

/// Dashboard widget displaying monthly savings requirements
struct MonthlyPlanningWidget: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    @State private var isExpanded = false
    @State private var lastRefresh: Date?
    @State private var showingSettings = false
    private let isUITestFlow = ProcessInfo.processInfo.arguments.contains("UITEST_UI_FLOW")
    
    init(viewModel: MonthlyPlanningViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        if isUITestFlow {
            widgetContent
        } else {
            widgetContent
                .sheet(isPresented: $showingSettings) {
                    MonthlyPlanningSettingsView(goals: [])
                }
        }
    }

    private var widgetContent: some View {
        VStack(spacing: 0) {
            // Header Section
            headerSection

            // Content Section
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            } else {
                compactContent
                    .transition(.slide)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .accessibleList(
            title: "Monthly Planning Summary",
            itemCount: viewModel.monthlyRequirements.count,
            emptyMessage: "No active goals requiring monthly payments"
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Monthly savings requirements widget")
        .accessibilityHint("Shows total monthly savings needed across all goals. Double tap to expand for detailed breakdown")
        .accessibilityValue(totalAccessibilityDescription)
        .onAppear {
            // Keep collapsed in UI tests to avoid overlapping tap targets (goal names also appear inside this widget).
            if isUITestFlow {
                isExpanded = false
                showingSettings = false
            }
        }
        .task {
            await viewModel.loadMonthlyRequirements()
            lastRefresh = Date()
        }
        .refreshable {
            await viewModel.refreshCalculations()
            lastRefresh = Date()
            AccessibilityManager.shared.performHapticFeedback(.success)
        }
    }
    
    // MARK: - Header Section
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Required This Month")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if viewModel.isLoading == true {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Calculating...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(formattedTotal)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(statusColor)
                    }
                }
            }
            
            Spacer()
            
            // Settings Button
            Button(action: {
                guard !isUITestFlow else { return }
                showingSettings = true
                AccessibilityManager.shared.performHapticFeedback(.selection)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AccessibleColors.primaryInteractive)
                    .frame(width: 32, height: 32)
                    .background(AccessibleColors.primaryInteractiveBackground)
                    .clipShape(Circle())
            }
            .disabled(isUITestFlow)
            .accessibilityHidden(isUITestFlow)
            .accessibilityLabel("Monthly planning settings")
            .accessibilityHint("Configure display currency and payment deadlines")
            
            // Expand/Collapse Button
            Button(action: {
                let animationDuration = AccessibilityManager.shared.animationDuration(0.3)
                withAnimation(.easeInOut(duration: animationDuration)) {
                    isExpanded.toggle()
                }
                AccessibilityManager.shared.performHapticFeedback(.selection)
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AccessibleColors.primaryInteractive)
                    .frame(width: 32, height: 32)
                    .background(AccessibleColors.primaryInteractiveBackground)
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("planningWidgetExpandButton")
            .accessibilityLabel(isExpanded ? "Show less" : "Show more")
        }
        .padding(16)
    }
    
    // MARK: - Compact Content
    
    @ViewBuilder
    private var compactContent: some View {
        if !viewModel.monthlyRequirements.isEmpty {
            VStack(spacing: 12) {
                // Quick Stats
                quickStatsView
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Expanded Content
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 16)
            
            if viewModel.monthlyRequirements.isEmpty {
                emptyStateView
            } else {
                // Detailed breakdown
                goalBreakdownView
                
                // Flex controls (if applicable)
                if viewModel.hasFlexibleGoals && viewModel.showFlexControls {
                    flexControlsView
                }
                
                // Navigation to full planning view (smart router)
                NavigationLink(destination: MonthlyPlanningContainer()) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Monthly Plan")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Adjust amounts and start tracking")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundColor(AccessibleColors.primaryInteractive)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AccessibleColors.primaryInteractiveBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("viewMonthlyPlanLink")
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Quick Stats View
    
    @ViewBuilder
    private var quickStatsView: some View {
        HStack(spacing: 16) {
            statItem(
                title: "Goals",
                value: "\(viewModel.statistics.totalGoals)",
                color: AccessibleColors.primaryInteractive
            )
            
            if viewModel.statistics.criticalCount > 0 {
                statItem(
                    title: "Critical",
                    value: "\(viewModel.statistics.criticalCount)",
                    color: AccessibleColors.error
                )
            } else if viewModel.statistics.attentionCount > 0 {
                statItem(
                    title: "Attention",
                    value: "\(viewModel.statistics.attentionCount)",
                    color: AccessibleColors.warning
                )
            } else {
                statItem(
                    title: "On Track",
                    value: "\(viewModel.statistics.onTrackCount)",
                    color: AccessibleColors.success
                )
            }
            
            if viewModel.flexAdjustment != 1.0 {
                statItem(
                    title: "Adjusted",
                    value: "\(Int(viewModel.flexAdjustment * 100))%",
                    color: AccessibleColors.secondaryInteractive
                )
            }
        }
        .font(.caption)
    }
    
    @ViewBuilder
    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Quick Actions View
    
    @ViewBuilder
    private var quickActionsView: some View {
        HStack(spacing: 8) {
            quickActionButton(.payExact, isDefault: true)
            quickActionButton(.payHalf)
            quickActionButton(.skipMonth)
            
            Button(action: {
                withAnimation {
                    viewModel.showFlexControls.toggle()
                }
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundColor(AccessibleColors.primaryInteractive)
                    .frame(width: 28, height: 28)
                    .background(AccessibleColors.primaryInteractiveBackground)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Flex controls")
        }
    }
    
    @ViewBuilder
    private func quickActionButton(_ action: QuickAction, isDefault: Bool = false) -> some View {
        Button(action: {
            Task {
                await viewModel.applyQuickAction(action)
            }
        }) {
            Text(action.title)
                .font(.caption2)
                .fontWeight(isDefault ? .semibold : .medium)
                .foregroundColor(isDefault ? .white : AccessibleColors.primaryInteractive)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isDefault ? AccessibleColors.primaryInteractive : AccessibleColors.primaryInteractiveBackground)
                .clipShape(Capsule())
        }
        .accessibilityHint(action.description)
    }
    
    // MARK: - Goal Breakdown View
    
    @ViewBuilder
    private var goalBreakdownView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Goal Breakdown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            LazyVStack(spacing: 4) {
                ForEach(viewModel.monthlyRequirements.prefix(3)) { requirement in
                    goalBreakdownRow(requirement)
                }
                
                if viewModel.monthlyRequirements.count > 3 {
                    HStack {
                        Text("+ \(viewModel.monthlyRequirements.count - 3) more goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func goalBreakdownRow(_ requirement: MonthlyRequirement) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor(for: requirement.status))
                .frame(width: 8, height: 8)
            
            // Goal name and progress
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.goalName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(Int(requirement.progress * 100))% complete")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Required amount (with adjustment preview)
            VStack(alignment: .trailing, spacing: 2) {
                Text(requirement.formattedRequiredMonthly())
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(requirement.timeRemainingDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Flex Controls View
    
    @ViewBuilder
    private var flexControlsView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Flex Adjustment")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(viewModel.flexAdjustment * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AccessibleColors.primaryInteractive)
            }
            
            Slider(value: Binding(
                get: { viewModel.flexAdjustment },
                set: { newValue in
                    Task {
                        await viewModel.applyFlexAdjustment(newValue)
                    }
                }
            ), in: 0...1.5, step: 0.05)
            .accentColor(AccessibleColors.primaryInteractive)
            
            HStack {
                Text("Total: \(formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Button("Reset") {
                    Task {
                        await viewModel.applyQuickAction(.reset)
                    }
                }
                .font(.caption)
                .foregroundColor(AccessibleColors.secondaryInteractive)
            }
        }
        .padding(12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Empty State View
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(AccessibleColors.secondaryInteractive)
            
            Text("No Active Goals")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Create your first savings goal to see monthly requirements")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
    
    // MARK: - Computed Properties
    
    private var formattedTotal: String {
        formatAmount(viewModel.flexAdjustment == 1.0 ? viewModel.totalRequired : viewModel.adjustedTotal, 
                    currency: viewModel.displayCurrency)
    }
    
    private var statusColor: Color {
        let stats = viewModel.statistics
        if stats.criticalCount > 0 {
            return AccessibleColors.error
        } else if stats.attentionCount > 0 {
            return AccessibleColors.warning
        } else {
            return AccessibleColors.success
        }
    }
    
    private func statusColor(for status: RequirementStatus) -> Color {
        switch status {
        case .completed: return AccessibleColors.success
        case .onTrack: return AccessibleColors.success
        case .attention: return AccessibleColors.warning
        case .critical: return AccessibleColors.error
        }
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
    
    /// Comprehensive accessibility description for VoiceOver
    private var totalAccessibilityDescription: String {
        let accessibilityManager = AccessibilityManager.shared
        let totalAmount = viewModel.flexAdjustment == 1.0 ? viewModel.totalRequired : viewModel.adjustedTotal
        
        var description = accessibilityManager.voiceOverDescription(
            for: totalAmount,
            currency: viewModel.displayCurrency,
            context: "Total monthly requirement"
        )
        
        let stats = viewModel.statistics
        if stats.criticalCount > 0 {
            description += ". \(stats.criticalCount) goals need immediate attention"
        } else if stats.attentionCount > 0 {
            description += ". \(stats.attentionCount) goals need attention"
        } else if viewModel.monthlyRequirements.count > 0 {
            description += ". All \(viewModel.monthlyRequirements.count) goals are on track"
        }
        
        if let shortestDeadline = stats.shortestDeadline {
            let dateDescription = accessibilityManager.voiceOverDateDescription(shortestDeadline, format: .relative)
            description += ". Nearest deadline is \(dateDescription)"
        }
        
        return description
    }
}

// MARK: - Preview

#Preview("Compact") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self, configurations: config)
    let context = container.mainContext
    
    let viewModel = MonthlyPlanningViewModel(modelContext: context)
    
    NavigationView {
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
