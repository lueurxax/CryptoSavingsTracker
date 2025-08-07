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
    @Query private var goals: [Goal]
    @Bindable var goal: Goal
    
    @State private var showingWidgetCustomization = false
    @State private var widgets: [DashboardWidget] = []
    @State private var isEditMode = false
    @State private var dashboardTotal: Double = 0.0
    @State private var dashboardProgress: Double = 0.0
    @StateObject private var viewModel = DashboardViewModel()
    
    // Progressive disclosure helper
    private var progressiveHelper: ProgressiveDisclosureHelper {
        ProgressiveDisclosureHelper(modelContext: modelContext)
    }
    
    // Grid layout
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Compact header with key info
                VStack(spacing: 12) {
                    // Primary goal info - most important at the top
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                HStack(spacing: 16) {
                                    // Current progress - most critical metric
                                    Text("\(String(format: "%.0f", dashboardTotal)) / \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    // Progress percentage - secondary critical metric
                                    Text("\(Int(dashboardProgress * 100))%")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(dashboardProgress >= 0.75 ? AccessibleColors.success : dashboardProgress >= 0.5 ? AccessibleColors.warning : AccessibleColors.error)
                                }
                                
                                // Days remaining - urgency indicator
                                let daysLeft = goal.daysRemaining
                                HStack(spacing: 4) {
                                    Image(systemName: daysLeft < 30 ? "exclamationmark.triangle.fill" : "calendar")
                                        .foregroundColor(daysLeft < 30 ? AccessibleColors.error : daysLeft < 60 ? AccessibleColors.warning : AccessibleColors.success)
                                        .font(.caption)
                                    
                                    Text("\(daysLeft) days remaining")
                                        .font(.subheadline)
                                        .foregroundColor(daysLeft < 30 ? AccessibleColors.error : .accessibleSecondary)
                                        
                                    Text("• \(goal.deadline.formatted(.dateTime.month(.abbreviated).day()))")
                                        .font(.caption)
                                        .foregroundColor(.accessibleSecondary)
                                }
                            }
                            
                            Spacer()
                            
                            // Controls moved to top right but smaller
                            HStack(spacing: 12) {
                                Button(action: { showingWidgetCustomization = true }) {
                                    Image(systemName: "square.grid.3x3")
                                        .font(.title3)
                                        .foregroundColor(.accessibleSecondary)
                                }
                                .accessibilityLabel("Customize dashboard")
                                
                                Button(action: { isEditMode.toggle() }) {
                                    Text(isEditMode ? "Done" : "Edit")
                                        .font(.caption)
                                        .foregroundColor(.accessiblePrimary)
                                }
                            }
                        }
                        
                        // Compact progress bar
                        ProgressView(value: dashboardProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .scaleEffect(y: 1.5)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
                
                // Dashboard content
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sortedWidgets) { widget in
                            DashboardWidgetView(
                                widget: widget,
                                goal: goal,
                                dashboardTotal: dashboardTotal,
                                dashboardProgress: dashboardProgress,
                                viewModel: viewModel,
                                isEditMode: isEditMode
                            )
                            .onTapGesture {
                                if isEditMode {
                                    // Handle widget configuration
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await updateDashboard()
                    await viewModel.loadData(for: goal, modelContext: modelContext)
                }
                .onAppear {
                    // Initialize widgets based on user level
                    if widgets.isEmpty {
                        widgets = progressiveHelper.getDashboardWidgets()
                    }
                    
                    Task {
                        await updateDashboard()
                        await viewModel.loadData(for: goal, modelContext: modelContext)
                    }
                }
                .onChange(of: goal.assets) {
                    Task {
                        await updateDashboard()
                    }
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $showingWidgetCustomization) {
                DashboardCustomizationView(widgets: $widgets)
            }
        }
    }
    
    @MainActor
    private func updateDashboard() async {
        do {
            dashboardTotal = await goal.getCurrentTotal()
            dashboardProgress = await goal.getProgress()
        } catch {
            // Use fallback values on error
            dashboardTotal = goal.currentTotal
            dashboardProgress = goal.progress
        }
    }
    
    private var sortedWidgets: [DashboardWidget] {
        widgets.sorted { $0.position < $1.position }
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
                        animateOnAppear: false
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
                            Text("\(goal.assets.count)")
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
    
    return DashboardView(goal: goal)
        .modelContainer(container)
}