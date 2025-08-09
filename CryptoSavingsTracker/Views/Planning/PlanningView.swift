//
//  PlanningView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI
import SwiftData

/// Main planning view with platform-specific layouts
struct PlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                iOSCompactPlanningView(viewModel: viewModel)
            } else {
                iOSRegularPlanningView(viewModel: viewModel)
            }
            #else
            macOSPlanningView(viewModel: viewModel)
            #endif
        }
        .navigationTitle("Monthly Planning")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

// MARK: - iOS Compact Layout

struct iOSCompactPlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            summaryHeader
            
            // Tab Selector
            Picker("View", selection: $selectedTab) {
                Text("Goals").tag(0)
                Text("Controls").tag(1)
                Text("Stats").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.bottom)
            
            // Tab Content
            TabView(selection: $selectedTab) {
                goalsListView
                    .tag(0)
                
                flexControlsView
                    .tag(1)
                
                statisticsView
                    .tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
        .background(.regularMaterial)
    }
    
    @ViewBuilder
    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Required")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if let deadline = viewModel.statistics.shortestDeadline {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Next Deadline")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(deadline, format: .dateTime.month().day())
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            
            if viewModel.flexAdjustment != 1.0 {
                HStack {
                    Text("Adjusted to \(Int(viewModel.flexAdjustment * 100))%")
                        .font(.caption)
                        .foregroundColor(AccessibleColors.secondaryInteractive)
                    
                    Spacer()
                    
                    Button("Reset") {
                        Task {
                            await viewModel.applyQuickAction(.reset)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(AccessibleColors.primaryInteractive)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AccessibleColors.primaryInteractiveBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(.regularMaterial)
    }
    
    @ViewBuilder
    private var goalsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.monthlyRequirements) { requirement in
                    GoalRequirementRow(
                        requirement: requirement,
                        flexState: viewModel.getFlexState(for: requirement.goalId),
                        adjustedAmount: viewModel.adjustmentPreview[requirement.goalId],
                        onToggleProtection: {
                            viewModel.toggleProtection(for: requirement.goalId)
                        },
                        onToggleSkip: {
                            viewModel.toggleSkip(for: requirement.goalId)
                        }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refreshCalculations()
        }
    }
    
    @ViewBuilder
    private var flexControlsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Flex Slider
                VStack(spacing: 16) {
                    HStack {
                        Text("Payment Adjustment")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(viewModel.flexAdjustment * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(AccessibleColors.primaryInteractive)
                    }
                    
                    Slider(value: Binding(
                        get: { viewModel.flexAdjustment },
                        set: { newValue in
                            Task {
                                await viewModel.previewAdjustment(newValue)
                            }
                        }
                    ), in: 0...1.5, step: 0.05) {
                        Text("Flex Adjustment")
                    } minimumValueLabel: {
                        Text("0%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("150%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .accentColor(AccessibleColors.primaryInteractive)
                    
                    Text("Drag to adjust payment amounts. Protected goals won't be reduced.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Quick Actions
                quickActionsGrid
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var statisticsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Overview
                statusOverviewCard
                
                // Goals by Status
                goalsByStatusCard
                
                // Performance Metrics
                performanceMetricsCard
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var quickActionsGrid: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach([QuickAction.payExact, .payHalf, .skipMonth, .reset], id: \.title) { action in
                    quickActionCard(action)
                }
            }
        }
    }
    
    @ViewBuilder
    private func quickActionCard(_ action: QuickAction) -> some View {
        Button(action: {
            Task {
                await viewModel.applyQuickAction(action)
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.title2)
                    .foregroundColor(AccessibleColors.primaryInteractive)
                
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(action.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var statusOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Overview")
                .font(.headline)
            
            Text(viewModel.statistics.statusSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                statusBadge("On Track", count: viewModel.statistics.onTrackCount, color: AccessibleColors.success)
                statusBadge("Attention", count: viewModel.statistics.attentionCount, color: AccessibleColors.warning)
                statusBadge("Critical", count: viewModel.statistics.criticalCount, color: AccessibleColors.error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func statusBadge(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var goalsByStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goal Breakdown")
                .font(.headline)
            
            ForEach(Array(groupedGoals.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { status in
                if let goals = groupedGoals[status], !goals.isEmpty {
                    statusSection(status: status, goals: goals)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func statusSection(status: RequirementStatus, goals: [MonthlyRequirement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(goals.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(goals.prefix(3)) { goal in
                HStack {
                    Text(goal.goalName)
                        .font(.caption)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(goal.formattedRequiredMonthly())
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            if goals.count > 3 {
                Text("+ \(goals.count - 3) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var performanceMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Metrics")
                .font(.headline)
            
            metricRow("Average Required", value: formatAmount(viewModel.statistics.averageMonthlyRequired, currency: viewModel.displayCurrency))
            metricRow("Total Goals", value: "\(viewModel.statistics.totalGoals)")
            metricRow("Completion Rate", value: "\(Int(Double(viewModel.statistics.completedCount) / Double(max(1, viewModel.statistics.totalGoals)) * 100))%")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private var groupedGoals: [RequirementStatus: [MonthlyRequirement]] {
        Dictionary(grouping: viewModel.monthlyRequirements, by: \.status)
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - iOS Regular Layout

struct iOSRegularPlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View {
        #if os(macOS)
        macOSRegularLayout
        #else
        iosRegularLayout
        #endif
    }
    
    #if os(macOS)
    @ViewBuilder
    private var macOSRegularLayout: some View {
        HSplitView {
            // Left panel - Goals list
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.monthlyRequirements) { requirement in
                            GoalRequirementRow(
                                requirement: requirement,
                                flexState: viewModel.getFlexState(for: requirement.goalId),
                                adjustedAmount: viewModel.adjustmentPreview[requirement.goalId],
                                onToggleProtection: {
                                    viewModel.toggleProtection(for: requirement.goalId)
                                },
                                onToggleSkip: {
                                    viewModel.toggleSkip(for: requirement.goalId)
                                }
                            )
                        }
                    }
                    .padding()
                }
                .navigationTitle("Goals")
            }
            .frame(minWidth: 300)
            
            // Right panel - Controls and statistics
            macOSControlsPanel(viewModel: viewModel)
                .frame(minWidth: 350)
        }
    }
    #endif
    
    @ViewBuilder
    private var iosRegularLayout: some View {
        // iOS uses NavigationView instead of HSplitView
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.monthlyRequirements) { requirement in
                        GoalRequirementRow(
                            requirement: requirement,
                            flexState: viewModel.getFlexState(for: requirement.goalId),
                            adjustedAmount: viewModel.adjustmentPreview[requirement.goalId],
                            onToggleProtection: {
                                viewModel.toggleProtection(for: requirement.goalId)
                            },
                            onToggleSkip: {
                                viewModel.toggleSkip(for: requirement.goalId)
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Goals")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - macOS Layout

struct macOSPlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iosLayout
        #endif
    }
    
    #if os(macOS)
    @ViewBuilder
    private var macOSLayout: some View {
        HSplitView {
            // Left sidebar - Summary and controls
            macOSControlsPanel(viewModel: viewModel)
                .frame(minWidth: 320, maxWidth: 400)
            
            // Main content - Goals list
            NavigationView {
                if viewModel.monthlyRequirements.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.monthlyRequirements) { requirement in
                                GoalRequirementRow(
                                    requirement: requirement,
                                    flexState: viewModel.getFlexState(for: requirement.goalId),
                                    adjustedAmount: viewModel.adjustmentPreview[requirement.goalId],
                                    onToggleProtection: {
                                        viewModel.toggleProtection(for: requirement.goalId)
                                    },
                                    onToggleSkip: {
                                        viewModel.toggleSkip(for: requirement.goalId)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task {
                        await viewModel.refreshCalculations()
                    }
                }
            }
        }
    }
    #endif
    
    @ViewBuilder
    private var iosLayout: some View {
        // iOS simplified layout
        NavigationView {
            if viewModel.monthlyRequirements.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.monthlyRequirements) { requirement in
                            GoalRequirementRow(
                                requirement: requirement,
                                flexState: viewModel.getFlexState(for: requirement.goalId),
                                adjustedAmount: viewModel.adjustmentPreview[requirement.goalId],
                                onToggleProtection: {
                                    viewModel.toggleProtection(for: requirement.goalId)
                                },
                                onToggleSkip: {
                                    viewModel.toggleSkip(for: requirement.goalId)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Monthly Requirements")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create savings goals to see your monthly payment requirements")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - macOS Controls Panel

struct macOSControlsPanel: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary section
                summarySection
                
                // Flex controls section
                if viewModel.hasFlexibleGoals {
                    flexControlsSection
                }
                
                // Quick actions section
                quickActionsSection
                
                // Statistics section
                statisticsSection
            }
            .padding()
        }
        #if os(macOS)
        .background(Color(.controlBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }
    
    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Total Required", value: formatAmount(viewModel.totalRequired, currency: viewModel.displayCurrency))
                
                if viewModel.flexAdjustment != 1.0 {
                    summaryRow("Adjusted Total", value: formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))
                        .foregroundColor(AccessibleColors.primaryInteractive)
                }
                
                summaryRow("Active Goals", value: "\(viewModel.statistics.totalGoals)")
                
                if let deadline = viewModel.statistics.shortestDeadline {
                    summaryRow("Next Deadline", value: deadline.formatted(.dateTime.month().day()))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    @ViewBuilder
    private var flexControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment Adjustment")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack {
                    Text("Amount")
                    Spacer()
                    Text("\(Int(viewModel.flexAdjustment * 100))%")
                        .fontWeight(.medium)
                        .foregroundColor(AccessibleColors.primaryInteractive)
                }
                
                Slider(value: Binding(
                    get: { viewModel.flexAdjustment },
                    set: { newValue in
                        Task {
                            await viewModel.previewAdjustment(newValue)
                        }
                    }
                ), in: 0...1.5, step: 0.05)
                .accentColor(AccessibleColors.primaryInteractive)
                
                HStack {
                    Text("0%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("150%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                ForEach([QuickAction.payExact, .payHalf, .skipMonth, .reset], id: \.title) { action in
                    Button(action: {
                        Task {
                            await viewModel.applyQuickAction(action)
                        }
                    }) {
                        HStack {
                            Image(systemName: action.systemImage)
                                .frame(width: 16)
                                .foregroundColor(AccessibleColors.primaryInteractive)
                            
                            Text(action.title)
                                .font(.subheadline)
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(action.description)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                statisticRow("On Track", count: viewModel.statistics.onTrackCount, color: AccessibleColors.success)
                statisticRow("Need Attention", count: viewModel.statistics.attentionCount, color: AccessibleColors.warning)
                statisticRow("Critical", count: viewModel.statistics.criticalCount, color: AccessibleColors.error)
                statisticRow("Completed", count: viewModel.statistics.completedCount, color: AccessibleColors.success)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func statisticRow(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Preview

#Preview("iOS Compact") {
    NavigationView {
        iOSCompactPlanningView(viewModel: MonthlyPlanningViewModel(modelContext: ModelContext(try! ModelContainer(for: Goal.self))))
    }
}

#Preview("macOS") {
    NavigationView {
        macOSPlanningView(viewModel: MonthlyPlanningViewModel(modelContext: ModelContext(try! ModelContainer(for: Goal.self))))
    }
    .frame(width: 800, height: 600)
}