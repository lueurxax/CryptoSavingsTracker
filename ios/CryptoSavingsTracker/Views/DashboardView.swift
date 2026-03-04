    //
    //  DashboardView.swift
    //  CryptoSavingsTracker
    //
    //  Created by Claude on 07/08/2025.
    //

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var goals: [Goal]
    @State private var selectedGoal: Goal?
    @State private var showingTrendChart = false
    @State private var showingActionSheet = false
    @State private var showingCustomize = false
    @State private var dashboardVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .dashboard)
    @AppStorage("dashboard_widgets") private var widgetsJSON: String = ""
    @State private var widgets: [DashboardWidget] = []
    @StateObject private var widgetsViewModel = DIContainer.shared.makeDashboardViewModel()
    private var isCompact: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return horizontalSizeClass == .compact
#endif
    }

    var body: some View {
        Group {
            if dashboardVisualEnabled {
                ScrollView {
                    VStack(spacing: 0) {
                        if isCompact {
                            Spacer().frame(height: 16)
                        }
                            // Goal Switcher with improved mobile UX (only for mobile)
                        if !goals.isEmpty && isCompact {
                            MobileGoalSwitcher(
                                selectedGoal: $selectedGoal,
                                goals: goals,
                                showingActionSheet: $showingActionSheet
                            )
                            .padding(.bottom, 24)
                        }

                        if let currentGoal = selectedGoal {
                            if isCompact {
                                    // Mobile-optimized layout
                                VStack(spacing: 20) {
                                        // Hero Progress Section
                                    HeroProgressView(goal: currentGoal)
                                    // Enhanced Stats
                                    MobileStatsSection(goal: currentGoal)

                                        // Balance Trend Chart - Always Visible
                                    ChartSection(goal: currentGoal)

                                        // Insights Widget
                                    MobileInsightsSection(goal: currentGoal)

                                    // Forecast Widget
                                    MobileForecastSection(goal: currentGoal)

                                    // Custom Widgets Grid (persisted)
                                    if !widgets.isEmpty {
                                        CustomWidgetsGrid(goal: currentGoal, viewModel: widgetsViewModel, widgets: widgets)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                            } else {
                                    // Desktop/iPad layout - Use the enhanced dashboard
                                VStack(spacing: 20) {
                                    GoalDashboardView(goal: currentGoal)
                                    // Custom Widgets Grid (persisted)
                                    if !widgets.isEmpty {
                                        CustomWidgetsGrid(goal: currentGoal, viewModel: widgetsViewModel, widgets: widgets)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical)
                            }
                        } else {
                                // Empty state when no goals exist
                            if isCompact {
                                MobileEmptyState()
                                    .padding(.top, 40)
                            } else {
                                DashboardEmptyState()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.horizontal, isCompact ? 16 : 0)
                }
            } else {
                LegacyDashboardFallbackView(goals: goals, selectedGoal: $selectedGoal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .navigationTitle("Dashboard")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCustomize = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
            }
        }
        .onAppear {
            dashboardVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .dashboard)
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
            // Load persisted widgets (if any)
            if widgets.isEmpty {
                loadWidgets()
            }
        }
#if os(iOS)
        // NAV-MOD: MOD-04
        .confirmationDialog("Switch Goal", isPresented: $showingActionSheet, titleVisibility: .visible) {
            ForEach(goals) { goal in
                Button(goal.name) {
                    selectedGoal = goal
                }
            }
            Button("Cancel", role: .cancel) {}
        }
#else
            // NAV-MOD: MOD-01
        .sheet(isPresented: $showingActionSheet) {
            MacGoalSwitcherSheet(goals: goals, selectedGoal: $selectedGoal)
        }
#endif
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingCustomize) {
            DashboardCustomizationView(widgets: $widgets)
        }
        .onChange(of: widgets) { _, _ in
            persistWidgets()
        }
    }

    private func loadWidgets() {
        if let data = widgetsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DashboardWidget].self, from: data) {
            widgets = decoded
        } else {
            // Default starter layout
            widgets = [
                DashboardWidget(type: .summary, position: 0),
                DashboardWidget(type: .forecast, position: 1),
                DashboardWidget(type: .lineChart, position: 2)
            ]
            persistWidgets()
        }
    }

    private func persistWidgets() {
        if let data = try? JSONEncoder().encode(widgets) {
            widgetsJSON = String(data: data, encoding: .utf8) ?? ""
        }
    }
}

    // MARK: - Supporting Components

struct TrendSparklineView: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Balance Trend")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let latest = viewModel.balanceHistory.last,
                   let first = viewModel.balanceHistory.first,
                   first.balance > 0 {
                    let change = latest.balance - first.balance
                    let changePercent = (change / first.balance) * 100
                    
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .foregroundColor(change >= 0 ? AccessibleColors.success : AccessibleColors.error)
                        
                        Text("\(change >= 0 ? "+" : "")\(String(format: "%.1f", changePercent))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(change >= 0 ? AccessibleColors.success : AccessibleColors.error)
                    }
                }
            }
            
            if viewModel.balanceHistory.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 40)
                    .overlay(
                        Text("No data yet")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                    )
            } else {
                SimpleTrendChart(dataPoints: viewModel.balanceHistory)
                    .frame(height: 40)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .cornerRadius(12)
        .task {
            await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
        }
    }
}

struct SimpleTrendChart: View {
    let dataPoints: [BalanceHistoryPoint]
    
    var body: some View {
        GeometryReader { geometry in
            if dataPoints.count > 1 {
                Path { path in
                    let maxBalance = dataPoints.map { $0.balance }.max() ?? 1
                    let minBalance = dataPoints.map { $0.balance }.min() ?? 0
                    let range = maxBalance - minBalance
                    
                    for (index, point) in dataPoints.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(dataPoints.count - 1)
                        let normalizedY = range > 0 ? (point.balance - minBalance) / range : 0.5
                        let y = geometry.size.height * (1 - normalizedY)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(AccessibleColors.primaryInteractive, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(.easeInOut(duration: 0.5), value: dataPoints.count)
            }
        }
    }
}

// Deprecated placeholder removed; real QuickActionsView lives in DashboardComponents.swift

struct DashboardEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.accessibleSecondary)
            
            VStack(spacing: 6) {
                Text("Dashboard Ready")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Create your first savings goal to start tracking your crypto journey")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .multilineTextAlignment(.center)
            }
            
            NavigationLink(destination: GoalsListView()) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create First Goal")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: 200)
                .frame(height: 50)
                .background(AccessibleColors.primaryInteractive)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

struct LegacyDashboardFallbackView: View {
    let goals: [Goal]
    @Binding var selectedGoal: Goal?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dashboard (Legacy Visual Style)")
                .font(.headline)

            if !goals.isEmpty {
                Picker("Goal", selection: Binding(
                    get: { selectedGoal?.id ?? goals.first?.id ?? UUID() },
                    set: { id in
                        selectedGoal = goals.first(where: { $0.id == id })
                    }
                )) {
                    ForEach(goals) { goal in
                        Text(goal.name).tag(goal.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let goal = selectedGoal {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.name)
                        .font(.title3)
                    Text("Target: \(goal.currency) \(String(format: "%,.2f", goal.targetAmount))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Legacy fallback keeps flow available when visual rollout flag is disabled.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(.regularMaterial)
                .cornerRadius(10)
            } else {
                Text("No goals available.")
                    .foregroundColor(.secondary)
            }
        }
    }
}

    // MARK: - Dashboard Widget View
struct DashboardWidgetView: View {
    let widget: DashboardWidget
    let goal: Goal
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var viewModel: DashboardViewModel
    let isEditMode: Bool
    
    private var gridSpan: (columns: Int, rows: Int) {
        switch widget.size {
        case .small: return (1, 1)
        case .medium: return (2, 1)
        case .large: return (2, 2)
        case .full: return (2, 1)
        }
    }
    
    var body: some View {
        Group {
            switch widget.type {
            case .progressRing:
                ProgressRingView(
                    progress: dashboardProgress,
                    current: dashboardTotal,
                    target: goal.targetAmount,
                    currency: goal.currency,
                    lineWidth: widget.size == .large ? 20 : 15,
                    showLabels: widget.size != .small
                )
                .aspectRatio(1, contentMode: .fit)
                
            case .lineChart:
                if viewModel.isLoadingBalanceHistory {
                    ChartSkeletonView(height: 250, type: .line)
                } else if !viewModel.balanceHistory.isEmpty {
                    LineChartView(
                        dataPoints: viewModel.balanceHistory,
                        timeRange: .month,
                        animateOnAppear: false,
                        targetValue: goal.targetAmount
                    )
                } else {
                    ChartPlaceholderView(type: .lineChart)
                }
                
            case .stackedBar:
                if viewModel.isLoadingAssetComposition {
                    ChartSkeletonView(height: 200, type: .bar)
                } else if !viewModel.assetComposition.isEmpty {
                    StackedBarChartView(
                        assetCompositions: viewModel.assetComposition,
                        totalValue: dashboardTotal,
                        currency: goal.currency,
                        animateOnAppear: false
                    )
                } else {
                    ChartPlaceholderView(type: .stackedBar)
                }
                
            case .forecast:
                if viewModel.isLoadingForecast || viewModel.isLoadingBalanceHistory {
                    ChartSkeletonView(height: 300, type: .line)
                } else if !viewModel.balanceHistory.isEmpty && !viewModel.forecastData.isEmpty {
                    ForecastChartView(
                        historicalData: viewModel.balanceHistory,
                        forecastData: viewModel.forecastData,
                        targetValue: goal.targetAmount,
                        targetDate: goal.deadline,
                        currency: goal.currency,
                        animateOnAppear: false
                    )
                } else {
                    ChartPlaceholderView(type: .forecast)
                }
                
            case .heatmap:
                if viewModel.isLoadingHeatmap {
                    ChartSkeletonView(height: 150, type: .heatmap)
                } else if !viewModel.heatmapData.isEmpty {
                    HeatmapCalendarView(
                        heatmapData: viewModel.heatmapData,
                        title: "Transaction Activity",
                        animateOnAppear: false
                    )
                } else {
                    ChartPlaceholderView(type: .heatmap)
                }
                
            case .summary:
                SummaryStatsView(
                    goal: goal,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    viewModel: viewModel
                )
            }
        }
        .overlay(
            Group {
                if isEditMode {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                    // Remove widget
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AccessibleColors.error)
                                    .background(Color.white, in: Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
        )
    }
}

    // MARK: - Chart Placeholder
struct ChartPlaceholderView: View {
    let type: DashboardWidgetType
    
    var body: some View {
        Group {
            switch type {
            case .lineChart:
                EmptyStateView.noChartData(chartType: "Balance History")
            case .stackedBar:
                EmptyStateView.noAssets(onAddAsset: {
                        // This will be handled by the parent view
                })
            case .forecast:
                EmptyStateView.noForecastData()
            case .heatmap:
                EmptyStateView.noActivity()
            default:
                EmptyStateView.noChartData(chartType: type.rawValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

    // MARK: - Summary Stats View
struct SummaryStatsView: View {
    let goal: Goal
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                // Primary metrics - most important information
            HStack(spacing: 20) {
                    // Daily target - actionable metric
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("DAILY TARGET")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.accessibleSecondary)
                        MetricTooltips.dailyTarget
                    }
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", viewModel.dailyTarget))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(goal.currency)
                            .font(.headline)
                            .foregroundColor(.accessibleSecondary)
                    }
                }
                
                Spacer()
                
                    // Achievement status - motivational
                VStack(alignment: .trailing, spacing: 4) {
                    if dashboardProgress >= 1.0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.accessibleAchievement)
                            Text("ACHIEVED")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.accessibleAchievement)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AccessibleColors.achievementBackground)
                        .cornerRadius(12)
                    } else if viewModel.streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.accessibleStreak)
                            Text("\(viewModel.streak) DAY STREAK")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.accessibleStreak)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AccessibleColors.streakBackground)
                        .cornerRadius(12)
                    } else {
                        let remaining = goal.targetAmount - dashboardTotal
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("TO GO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.accessibleSecondary)
                            Text(String(format: "%.0f", remaining))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            
            Divider()
            
                // Secondary metrics in a more scannable layout
            HStack(spacing: 0) {
                    // Portfolio overview
                VStack(alignment: .leading, spacing: 8) {
                    Text("PORTFOLIO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accessibleSecondary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(goal.allocatedAssets.count)")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Assets")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.transactionCount)")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Transactions")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                    }
                }
                
                Spacer()
                
                    // Time tracking
                VStack(alignment: .trailing, spacing: 8) {
                    Text("TIMELINE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accessibleSecondary)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(viewModel.daysRemaining)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(viewModel.daysRemaining < 30 ? AccessibleColors.error : .primary)
                        Text("Days Left")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardSummaryCornerRadius)
                .fill(VisualComponentTokens.financeSurfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardSummaryCornerRadius)
                .stroke(VisualComponentTokens.financeSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardSummaryCornerRadius))
        .accessibilityIdentifier("dashboard.summary_card")
    }
}

// MARK: - Custom Widgets Grid
struct CustomWidgetsGrid: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let widgets: [DashboardWidget]
    @State private var dashboardTotal: Double = 0
    @State private var dashboardProgress: Double = 0

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: 120, maximum: .infinity)), count: 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Widgets")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(widgets.sorted { $0.position < $1.position }) { widget in
                    DashboardWidgetView(
                        widget: widget,
                        goal: goal,
                        dashboardTotal: dashboardTotal,
                        dashboardProgress: dashboardProgress,
                        viewModel: viewModel,
                        isEditMode: false
                    )
                    .gridCellColumns(widget.size.columns)
                }
            }
        }
        .task {
            await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
            let calc = DIContainer.shared.goalCalculationService
            let total = await calc.getCurrentTotal(for: goal)
            let progress = await calc.getProgress(for: goal)
            await MainActor.run {
                dashboardTotal = total
                dashboardProgress = progress
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let tooltip: HelpTooltip?
    
    init(title: String, value: String, icon: String, color: Color, tooltip: HelpTooltip? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.tooltip = tooltip
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.callout)
                }
                Spacer()
                if let tooltip = tooltip { tooltip }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

    // MARK: - Dashboard Customization View
struct DashboardCustomizationView: View {
    @Binding var widgets: [DashboardWidget]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Available Widgets") {
                    ForEach(DashboardWidgetType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(.blue)
                            Text(type.rawValue)
                            Spacer()
                            Button("Add") {
                                let newWidget = DashboardWidget(
                                    type: type,
                                    size: .medium,
                                    position: widgets.count
                                )
                                widgets.append(newWidget)
                            }
                            .font(.caption)
                        }
                    }
                }
                
                Section("Current Widgets") {
                    ForEach($widgets, id: \.id) { $widget in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: widget.type.icon)
                                    .foregroundColor(.gray)
                                Text(widget.type.rawValue)
                                Spacer()
                                // Size selector
                                Picker("Size", selection: $widget.size) {
                                    Text("S").tag(DashboardWidget.WidgetSize.small)
                                    Text("M").tag(DashboardWidget.WidgetSize.medium)
                                    Text("L").tag(DashboardWidget.WidgetSize.large)
                                    Text("Full").tag(DashboardWidget.WidgetSize.full)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 220)
                            }
                            Text("Span: \(widget.size.columns) columns, \(widget.size.rows) rows")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        widgets.remove(atOffsets: indexSet)
                    }
                    .onMove { source, destination in
                        widgets.move(fromOffsets: source, toOffset: destination)
                            // Update positions
                        for (index, _) in widgets.enumerated() {
                            widgets[index].position = index
                        }
                    }
                }
            }
            .navigationTitle("Customize Dashboard")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        widgets = [
                            DashboardWidget(type: .summary, size: .medium, position: 0),
                            DashboardWidget(type: .forecast, size: .full, position: 1),
                            DashboardWidget(type: .lineChart, size: .full, position: 2)
                        ]
                    }
                }
            }
        }
    }
}
