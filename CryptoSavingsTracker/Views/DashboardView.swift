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
    
    private var isCompact: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return horizontalSizeClass == .compact
#endif
    }
    
    var body: some View {
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
                            
                                // Balance Trend Chart - Always Visible
                            ChartSection(goal: currentGoal)
                            
                                // Insights Widget
                            MobileInsightsSection(goal: currentGoal)
                            
                                // Forecast Widget
                            MobileForecastSection(goal: currentGoal)
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                    } else {
                            // Desktop/iPad layout
                        VStack(spacing: 20) {
                                // Hero Progress Section
                            HeroProgressView(goal: currentGoal)
                                .padding(.horizontal, 16)
                            
                                // Balance Trend Chart - Always Visible
                            TrendSparklineView(goal: currentGoal)
                                .padding(.horizontal, 16)
                            
                                // Forecast Widget
                            DesktopForecastSection(goal: currentGoal)
                                .padding(.horizontal, 16)
                        }
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
        .navigationTitle("Dashboard")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
        }
#if os(iOS)
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("Switch Goal"),
                buttons: goalActionButtons
            )
        }
#else
            // Use sheet for macOS instead of ActionSheet
        .sheet(isPresented: $showingActionSheet) {
            MacGoalSwitcherSheet(goals: goals, selectedGoal: $selectedGoal)
        }
#endif
    }
    
#if os(iOS)
    private var goalActionButtons: [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = []
        
        for goal in goals {
            buttons.append(.default(Text(goal.name)) {
                selectedGoal = goal
            })
        }
        
        buttons.append(.cancel())
        return buttons
    }
#endif
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
                                    .foregroundColor(.red)
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
        .background(.regularMaterial)
        .cornerRadius(12)
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
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Spacer()
                if let tooltip = tooltip {
                    tooltip
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.gray.opacity(0.03))
        .cornerRadius(8)
    }
}

    // MARK: - Dashboard Customization View
struct DashboardCustomizationView: View {
    @Binding var widgets: [DashboardWidget]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
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
                    ForEach(widgets) { widget in
                        HStack {
                            Image(systemName: widget.type.icon)
                                .foregroundColor(.gray)
                            Text(widget.type.rawValue)
                            Spacer()
                            Text(widget.size == .small ? "S" : widget.size == .medium ? "M" : widget.size == .large ? "L" : "Full")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
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
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
        // Create sample data
    let goal = Goal(name: "Crypto Portfolio", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    return NavigationView {
        DashboardView()
    }
    .modelContainer(container)
}

    // MARK: - Mobile Components (moved from ImprovedDashboardView)

struct MobileGoalSwitcher: View {
    @Binding var selectedGoal: Goal?
    let goals: [Goal]
    @Binding var showingActionSheet: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let goal = selectedGoal {
                    Text(goal.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                        .font(.subheadline)
                        .foregroundColor(.accessibleSecondary)
                }
            }
            
            Spacer()
            
            if goals.count > 1 {
                Button(action: {
                    showingActionSheet = true
                }) {
                    HStack(spacing: 6) {
                        Text("Switch")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.accessiblePrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}


struct ChartSection: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Balance Trend")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                    // Trend indicator
                if let latest = viewModel.balanceHistory.last,
                   let first = viewModel.balanceHistory.first,
                   first.balance > 0 {
                    let change = latest.balance - first.balance
                    let changePercent = (change / first.balance) * 100
                    
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text("\(change >= 0 ? "+" : "")\(String(format: "%.1f", changePercent))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(change >= 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((change >= 0 ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
                // Simplified sparkline chart
            if viewModel.balanceHistory.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 60)
                    .overlay(
                        Text("No transaction data yet")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                    )
            } else {
                SimpleTrendChart(dataPoints: viewModel.balanceHistory)
                    .frame(height: 60)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .task {
            await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
        }
    }
}

struct BottomActionBar: View {
    let goal: Goal
    @Binding var showingChart: Bool
    
    var body: some View {
        EmptyView()
    }
}

struct MobileEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
                // Hero icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.accessiblePrimary)
            }
            
            VStack(spacing: 12) {
                Text("Ready to Start Saving?")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Create your first crypto savings goal and start tracking your progress toward financial freedom.")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            NavigationLink(destination: AddGoalView()) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text("Create Your First Goal")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
    }
}

    // MARK: - macOS Goal Switcher Sheet
#if os(macOS)
struct MacGoalSwitcherSheet: View {
    let goals: [Goal]
    @Binding var selectedGoal: Goal?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(goals, id: \.id) { goal in
                Button(action: {
                    selectedGoal = goal
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Target: \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedGoal?.id == goal.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .navigationTitle("Switch Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
#endif

// MARK: - Dashboard View for Specific Goal
struct DashboardViewForGoal: View {
    let goal: Goal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingTrendChart = false
    
    private var isCompact: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return horizontalSizeClass == .compact
#endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isCompact {
                    Spacer().frame(height: 16)
                }
                
                // Mobile layout
                if isCompact {
                    VStack(spacing: 20) {
                        // Hero Progress Section
                        HeroProgressView(goal: goal)
                        
                        // Key Metrics Grid
                        DashboardMetricsGrid(goal: goal)
                        
                        // Balance Trend Chart - Always Visible
                        ChartSection(goal: goal)
                        
                        // Forecast Widget
                        MobileForecastSection(goal: goal)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                } else {
                    // Desktop/iPad layout
                    VStack(spacing: 20) {
                        // Hero Progress Section
                        HeroProgressView(goal: goal)
                            .padding(.horizontal, 16)
                        
                        // Key Metrics Grid
                        DashboardMetricsGrid(goal: goal)
                            .padding(.horizontal, 16)
                        
                        // Balance Trend Chart - Always Visible
                        TrendSparklineView(goal: goal)
                            .padding(.horizontal, 16)
                        
                        // Forecast Widget
                        DesktopForecastSection(goal: goal)
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical)
                }
            }
            .padding(.horizontal, isCompact ? 16 : 0)
        }
    }
}

// MARK: - Mobile Forecast Section
// MARK: - Mobile Insights Section

struct MobileInsightsSection: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    
    var body: some View {
        InsightsView(viewModel: viewModel, goal: goal)
            .task {
                await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
            }
    }
}

struct MobileForecastSection: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    @State private var currentTotal: Double = 0
    @State private var progress: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goal Forecast")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Status indicator
                if let lastForecast = viewModel.forecastData.last {
                    ForecastStatusBadge(forecast: lastForecast, goal: goal)
                }
            }
            
            if viewModel.isLoadingForecast || viewModel.isLoadingBalanceHistory {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 120)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                                .font(.title2)
                                .foregroundColor(.accessibleSecondary)
                            
                            Text("Forecast Unavailable")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Add more transactions to generate predictions")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .task {
            await updateData()
            await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
        }
        .onChange(of: goal.allocations) { _, _ in
            Task { 
                await updateData()
                await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
            }
        }
    }
    
    private func updateData() async {
        let calc = DIContainer.shared.goalCalculationService
        let total = await calc.getCurrentTotal(for: goal)
        let prog = await calc.getProgress(for: goal)
        
        await MainActor.run {
            currentTotal = total
            progress = prog
        }
    }
}

// MARK: - Desktop Forecast Section
struct DesktopForecastSection: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goal Forecast")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Status indicator
                if let lastForecast = viewModel.forecastData.last {
                    ForecastStatusBadge(forecast: lastForecast, goal: goal)
                }
            }
            
            if viewModel.isLoadingForecast || viewModel.isLoadingBalanceHistory {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 300)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.0)
                    )
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                                .font(.largeTitle)
                                .foregroundColor(.accessibleSecondary)
                            
                            Text("Forecast Unavailable")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Text("Add more transactions to generate forecast predictions")
                                .font(.subheadline)
                                .foregroundColor(.accessibleSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    )
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .task {
            await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
        }
        .onChange(of: goal.allocations) { _, _ in
            Task { 
                await viewModel.loadData(for: goal, modelContext: ModelContext(goal.modelContext?.container ?? CryptoSavingsTrackerApp.sharedModelContainer))
            }
        }
    }
}

// MARK: - Forecast Status Badge
struct ForecastStatusBadge: View {
    let forecast: ForecastPoint
    let goal: Goal
    
    private var isOnTrack: Bool {
        forecast.realistic >= goal.targetAmount
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOnTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
            Text(isOnTrack ? "On Track" : "Behind")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(isOnTrack ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isOnTrack ? Color.green : Color.orange).opacity(0.1))
        .cornerRadius(12)
    }
}
