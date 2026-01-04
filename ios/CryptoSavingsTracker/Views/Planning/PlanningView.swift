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
    @Environment(\.modelContext) private var modelContext
    @Query private var allPlans: [MonthlyPlan]
    @State private var viewId = UUID()  // Force view refresh

    // Get stale draft plans (past months that are still in draft state)
    private var staleDrafts: [MonthlyPlan] {
        let currentMonth = viewModel.planningMonthLabel
        return allPlans.filter { $0.monthLabel < currentMonth && $0.state == .draft }
            .sorted { $0.monthLabel > $1.monthLabel } // Most recent first
    }

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                iOSCompactPlanningView(viewModel: viewModel, staleDrafts: staleDrafts)
            } else {
                iOSRegularPlanningView(viewModel: viewModel, staleDrafts: staleDrafts)
            }
            #else
            macOSPlanningView(viewModel: viewModel, staleDrafts: staleDrafts)
            #endif
        }
        .navigationTitle("Monthly Planning")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear {
        }
        .id(viewId)
        .onReceive(viewModel.$monthlyRequirements) { _ in
            viewId = UUID()  // Force view refresh
        }
    }
}

// MARK: - iOS Compact Layout

struct iOSCompactPlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    let staleDrafts: [MonthlyPlan]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var showingBudgetSheet = false

    var body: some View {
        VStack(spacing: 0) {
            perGoalContent
        }
        .background(.regularMaterial)
        .sheet(isPresented: $showingBudgetSheet) {
            BudgetCalculatorSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var perGoalContent: some View {
        VStack(spacing: 0) {
            // Stale Draft Banner (if any)
            if !staleDrafts.isEmpty {
                StaleDraftBanner(
                    stalePlans: staleDrafts,
                    onMarkCompleted: { plan in
                        plan.state = .completed
                        plan.isSkipped = false
                        try? modelContext.save()
                    },
                    onMarkSkipped: { plan in
                        plan.isSkipped = true
                        plan.state = .completed
                        try? modelContext.save()
                    },
                    onDelete: { plan in
                        modelContext.delete(plan)
                        try? modelContext.save()
                    }
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            BudgetNoticesView(viewModel: viewModel) {
                showingBudgetSheet = true
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            if viewModel.hasBudget {
                BudgetSummaryCard(
                    budgetAmount: viewModel.budgetAmount,
                    budgetCurrency: viewModel.budgetCurrency,
                    feasibility: viewModel.budgetFeasibility,
                    isApplied: viewModel.isBudgetAppliedForCurrentMonth,
                    currentFocusGoal: viewModel.budgetFocusGoalName,
                    currentFocusDeadline: viewModel.budgetFocusGoalDeadline,
                    onEdit: { showingBudgetSheet = true }
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                BudgetEntryCard(onSetBudget: { showingBudgetSheet = true })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Consolidated Header (replaces context + summary)
            consolidatedHeader
                .padding(.horizontal)
                .padding(.bottom, 12)

            // Improved Tab Selector with underline indicator
            improvedTabSelector
                .padding(.horizontal)
                .padding(.bottom, 8)

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
    }

    // MARK: - Improved Tab Selector

    @ViewBuilder
    private var improvedTabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Goals", tag: 0, icon: "target")
            tabButton(title: "Adjust", tag: 1, icon: "slider.horizontal.3")
            tabButton(title: "Stats", tag: 2, icon: "chart.bar.fill")
        }
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func tabButton(title: String, tag: Int, icon: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        }) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(selectedTab == tag ? .semibold : .regular)
                }
                .foregroundColor(selectedTab == tag ? AccessibleColors.primaryInteractive : .secondary)

                // Underline indicator
                Rectangle()
                    .fill(selectedTab == tag ? AccessibleColors.primaryInteractive : Color.clear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) tab")
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }
    
    // MARK: - Consolidated Header (combines context + summary)

    @ViewBuilder
    private var consolidatedHeader: some View {
        VStack(spacing: 16) {
            // Main stats row
            HStack(alignment: .top, spacing: 16) {
                // Total amount (primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Total")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: true, vertical: false)

                    if viewModel.flexAdjustment != 1.0 {
                        HStack(spacing: 4) {
                            Text("(\(Int(viewModel.flexAdjustment * 100))% adjusted)")
                                .font(.caption2)
                                .foregroundColor(AccessibleColors.secondaryInteractive)

                            Button("Reset") {
                                Task {
                                    await viewModel.applyQuickAction(.reset)
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(AccessibleColors.primaryInteractive)
                        }
                    }
                }

                Spacer()

                // Goals count
                VStack(alignment: .center, spacing: 4) {
                    Text("Goals")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("\(viewModel.statistics.totalGoals)")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // Next deadline (with year)
                if let deadline = viewModel.statistics.shortestDeadline {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Next Due")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text(deadline, format: .dateTime.month(.abbreviated).day().year())
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            // Status summary row with icons (accessible)
            statusSummaryRow
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status Summary Row (replaces legend)

    @ViewBuilder
    private var statusSummaryRow: some View {
        HStack(spacing: 12) {
            if viewModel.statistics.onTrackCount > 0 {
                statusPill(
                    icon: "checkmark",
                    count: viewModel.statistics.onTrackCount,
                    label: "On Track",
                    color: AccessibleColors.success
                )
            }

            if viewModel.statistics.attentionCount > 0 {
                statusPill(
                    icon: "exclamationmark",
                    count: viewModel.statistics.attentionCount,
                    label: "Attention",
                    color: AccessibleColors.warning
                )
            }

            if viewModel.statistics.criticalCount > 0 {
                statusPill(
                    icon: "exclamationmark.triangle.fill",
                    count: viewModel.statistics.criticalCount,
                    label: "Critical",
                    color: AccessibleColors.error
                )
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func statusPill(icon: String, count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .fontWeight(.semibold)

            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityLabel("\(count) goals \(label.lowercased())")
    }

    // Legacy headers kept for compatibility but unused
    @ViewBuilder
    private var contextHeader: some View {
        EmptyView()
    }

    @ViewBuilder
    private var summaryHeader: some View {
        EmptyView()
    }
    
    @ViewBuilder
    private var goalsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.monthlyRequirements) { requirement in
                    GoalRequirementRow(
                        requirement: requirement,
                        flexState: viewModel.getFlexState(for: requirement.goalId),
                        adjustedAmount: viewModel.getEffectiveAmount(for: requirement.goalId),
                        showBudgetIndicator: viewModel.hasBudget && viewModel.hasCustomAmount(for: requirement.goalId),
                        onToggleProtection: {
                            viewModel.toggleProtection(for: requirement.goalId)
                        },
                        onToggleSkip: {
                            viewModel.toggleSkip(for: requirement.goalId)
                        },
                        onSetCustomAmount: { amount in
                            viewModel.setCustomAmount(for: requirement.goalId, amount: amount)
                        }
                    )
                }

                // Empty state
                if viewModel.monthlyRequirements.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No Active Goals")
                            .font(.headline)

                        Text("Create savings goals to see monthly requirements")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
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
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(viewModel.flexAdjustment * 100))%")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(AccessibleColors.primaryInteractive)
                            if viewModel.hasBudget {
                                Text("of budget \(formatAmount(viewModel.budgetAmount, currency: viewModel.budgetCurrency))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Slider(value: Binding(
                        get: { viewModel.flexAdjustment },
                        set: { newValue in
                            Task {
                                await viewModel.applyFlexAdjustment(newValue)
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

                    // Impact summary
                    if viewModel.flexAdjustment != 1.0 {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Impact")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(AccessibleColors.primaryInteractive)
                            }

                            Spacer()

                            if viewModel.affectedGoalsCount > 0 {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Goals Affected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("\(viewModel.affectedGoalsCount)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(viewModel.flexAdjustment < 1.0 ? AccessibleColors.warning : AccessibleColors.success)
                                }
                            }
                        }
                        .padding()
                        .background(AccessibleColors.primaryInteractive.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
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
    let staleDrafts: [MonthlyPlan]
    @Environment(\.modelContext) private var modelContext
    @State private var showingBudgetSheet = false
    
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
                                adjustedAmount: viewModel.getEffectiveAmount(for: requirement.goalId),
                                showBudgetIndicator: viewModel.hasBudget && viewModel.hasCustomAmount(for: requirement.goalId),
                                onToggleProtection: {
                                    viewModel.toggleProtection(for: requirement.goalId)
                                },
                                onToggleSkip: {
                                    viewModel.toggleSkip(for: requirement.goalId)
                                },
                                onSetCustomAmount: { amount in
                                    viewModel.setCustomAmount(for: requirement.goalId, amount: amount)
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
                    BudgetNoticesView(viewModel: viewModel) {
                        showingBudgetSheet = true
                    }

                    if viewModel.hasBudget {
                        BudgetSummaryCard(
                            budgetAmount: viewModel.budgetAmount,
                            budgetCurrency: viewModel.budgetCurrency,
                            feasibility: viewModel.budgetFeasibility,
                            isApplied: viewModel.isBudgetAppliedForCurrentMonth,
                            currentFocusGoal: viewModel.budgetFocusGoalName,
                            currentFocusDeadline: viewModel.budgetFocusGoalDeadline,
                            onEdit: { showingBudgetSheet = true }
                        )
                    } else {
                        BudgetEntryCard(onSetBudget: { showingBudgetSheet = true })
                    }

                    ForEach(viewModel.monthlyRequirements) { requirement in
                        GoalRequirementRow(
                            requirement: requirement,
                            flexState: viewModel.getFlexState(for: requirement.goalId),
                            adjustedAmount: viewModel.getEffectiveAmount(for: requirement.goalId),
                            showBudgetIndicator: viewModel.hasBudget && viewModel.hasCustomAmount(for: requirement.goalId),
                            onToggleProtection: {
                                viewModel.toggleProtection(for: requirement.goalId)
                            },
                            onToggleSkip: {
                                viewModel.toggleSkip(for: requirement.goalId)
                            },
                            onSetCustomAmount: { amount in
                                viewModel.setCustomAmount(for: requirement.goalId, amount: amount)
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
        .sheet(isPresented: $showingBudgetSheet) {
            BudgetCalculatorSheet(viewModel: viewModel)
        }
    }
}

// MARK: - macOS Layout

struct macOSPlanningView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    let staleDrafts: [MonthlyPlan]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        #if os(macOS)
        macOSLayout
            .onAppear {
            }
            .onChange(of: viewModel.monthlyRequirements.count) { oldValue, newValue in
            }
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

            // Main content - Goals list (removed NavigationView wrapper)
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading monthly requirements...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.monthlyRequirements.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Stale Draft Banner (macOS)
                            if !staleDrafts.isEmpty {
                                StaleDraftBanner(
                                    stalePlans: staleDrafts,
                                    onMarkCompleted: { plan in
                                        plan.state = .completed
                                        plan.isSkipped = false
                                        try? modelContext.save()
                                    },
                                    onMarkSkipped: { plan in
                                        plan.isSkipped = true
                                        plan.state = .completed
                                        try? modelContext.save()
                                    },
                                    onDelete: { plan in
                                        modelContext.delete(plan)
                                        try? modelContext.save()
                                    }
                                )
                                .padding(.bottom)
                            }

                            ForEach(viewModel.monthlyRequirements) { requirement in
                                GoalRequirementRow(
                                    requirement: requirement,
                                    flexState: viewModel.getFlexState(for: requirement.goalId),
                                    adjustedAmount: viewModel.getEffectiveAmount(for: requirement.goalId),
                                    showBudgetIndicator: viewModel.hasBudget && viewModel.hasCustomAmount(for: requirement.goalId),
                                    onToggleProtection: {
                                        viewModel.toggleProtection(for: requirement.goalId)
                                    },
                                    onToggleSkip: {
                                        viewModel.toggleSkip(for: requirement.goalId)
                                    },
                                    onSetCustomAmount: { amount in
                                        viewModel.setCustomAmount(for: requirement.goalId, amount: amount)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                    .frame(minWidth: 400)
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
                                adjustedAmount: viewModel.getEffectiveAmount(for: requirement.goalId),
                                showBudgetIndicator: viewModel.hasBudget && viewModel.hasCustomAmount(for: requirement.goalId),
                                onToggleProtection: {
                                    viewModel.toggleProtection(for: requirement.goalId)
                                },
                                onToggleSkip: {
                                    viewModel.toggleSkip(for: requirement.goalId)
                                },
                                onSetCustomAmount: { amount in
                                    viewModel.setCustomAmount(for: requirement.goalId, amount: amount)
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

            Button("Refresh") {
                Task {
                    await viewModel.refreshCalculations()
                }
            }
            .buttonStyle(.borderedProminent)
            
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
    @State private var showingBudgetSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BudgetNoticesView(viewModel: viewModel) {
                    showingBudgetSheet = true
                }

                if viewModel.hasBudget {
                    BudgetSummaryCard(
                        budgetAmount: viewModel.budgetAmount,
                        budgetCurrency: viewModel.budgetCurrency,
                        feasibility: viewModel.budgetFeasibility,
                        isApplied: viewModel.isBudgetAppliedForCurrentMonth,
                        currentFocusGoal: viewModel.budgetFocusGoalName,
                        currentFocusDeadline: viewModel.budgetFocusGoalDeadline,
                        onEdit: { showingBudgetSheet = true }
                    )
                } else {
                    BudgetEntryCard(onSetBudget: { showingBudgetSheet = true })
                }

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
        .sheet(isPresented: $showingBudgetSheet) {
            BudgetCalculatorSheet(viewModel: viewModel)
        }
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
                    summaryRow("Next Deadline", value: deadline.formatted(.dateTime.month(.abbreviated).day().year()))
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(viewModel.flexAdjustment * 100))%")
                            .fontWeight(.medium)
                            .foregroundColor(AccessibleColors.primaryInteractive)
                        if viewModel.hasBudget {
                            Text("of budget \(formatAmount(viewModel.budgetAmount, currency: viewModel.budgetCurrency))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Slider(value: Binding(
                    get: { viewModel.flexAdjustment },
                    set: { newValue in
                        viewModel.flexAdjustment = newValue
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

                // Impact summary
                if viewModel.flexAdjustment != 1.0 {
                    Divider().padding(.vertical, 4)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Adjusted Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatAmount(viewModel.adjustedTotal, currency: viewModel.displayCurrency))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AccessibleColors.primaryInteractive)
                        }

                        if viewModel.affectedGoalsCount > 0 {
                            HStack {
                                Text("Goals Affected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(viewModel.affectedGoalsCount)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(viewModel.flexAdjustment < 1.0 ? AccessibleColors.warning : AccessibleColors.success)
                            }
                        }
                    }
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
        iOSCompactPlanningView(viewModel: MonthlyPlanningViewModel(modelContext: ModelContext(try! ModelContainer(for: Goal.self))), staleDrafts: [])
    }
}

#Preview("macOS") {
    NavigationView {
        macOSPlanningView(viewModel: MonthlyPlanningViewModel(modelContext: ModelContext(try! ModelContainer(for: Goal.self))), staleDrafts: [])
    }
    .frame(width: 800, height: 600)
}
