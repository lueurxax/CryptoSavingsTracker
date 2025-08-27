//
//  DashboardComponents.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

// MARK: - Goal Dashboard View

struct GoalDashboardView: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    @State private var dashboardTotal: Double = 0.0
    @State private var dashboardProgress: Double = 0.0
    @StateObject private var whatIf = WhatIfSettings()
    @Environment(\.platformCapabilities) private var platform
    
    private var isCompact: Bool {
        #if os(iOS)
        return true  // Force mobile layout on iOS
        #else
        return platform.navigationStyle == .stack
        #endif
    }
    
    var body: some View {
        ScrollView {
            if isCompact {
                CompactDashboardLayout(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    whatIf: whatIf
                )
            } else {
                ExpandedDashboardLayout(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    whatIf: whatIf
                )
            }
        }
        .platformPadding()
        .task {
            await viewModel.loadData(for: goal, modelContext: goal.modelContext!)
            await updateDashboard()
        }
        .onChange(of: goal) { _, _ in
            Task {
                await viewModel.loadData(for: goal, modelContext: goal.modelContext!)
                await updateDashboard()
            }
        }
        .onChange(of: goal.allocations) { _, _ in
            Task {
                await updateDashboard()
            }
        }
    }
    
    @MainActor
    private func updateDashboard() async {
        let calc = DIContainer.shared.goalCalculationService
        dashboardTotal = await calc.getCurrentTotal(for: goal)
        dashboardProgress = await calc.getProgress(for: goal)
    }
}

// MARK: - Compact Layout (Mobile)

struct CompactDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var whatIf: WhatIfSettings
    
    var body: some View {
        VStack(spacing: 24) {
            HeroProgressView(goal: goal)
                .padding(.horizontal, 20)
            
            ForecastWidgetView(
                goal: goal,
                viewModel: viewModel,
                dashboardTotal: dashboardTotal,
                dashboardProgress: dashboardProgress,
                whatIf: whatIf
            )
            .padding(.horizontal, 20)
            
            // Simple What‑If controls on mobile as a separate card
            WhatIfView(goal: goal, settings: whatIf)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Expanded Layout (Desktop)

struct ExpandedDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var whatIf: WhatIfSettings
    
    var body: some View {
        GeometryReader { geometry in
            // Always use ThreeColumnDashboardLayout for desktop to show enhanced components
            ThreeColumnDashboardLayout(
                goal: goal,
                viewModel: viewModel,
                dashboardTotal: dashboardTotal,
                dashboardProgress: dashboardProgress,
                whatIf: whatIf
            )
        }
    }
}

// MARK: - Three Column Layout

struct ThreeColumnDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var whatIf: WhatIfSettings
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left Column: Key Metrics + Hero Progress
            VStack(spacing: 16) {
                HeroProgressView(goal: goal)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
                
                EnhancedStatsGrid(viewModel: viewModel, goal: goal)
            }
            .frame(maxWidth: 380)
            
            // Middle Column: Charts
            VStack(spacing: 16) {
                ForecastWidgetView(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    whatIf: whatIf
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
                
                WhatIfView(goal: goal, settings: whatIf)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Quick Actions, Insights & Activity
            VStack(spacing: 16) {
                QuickActionsView(goal: goal)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
                
                InsightsView(viewModel: viewModel, goal: goal)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
                
                RecentActivityView(goal: goal, viewModel: viewModel)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 3)
            }
            .frame(maxWidth: 340)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Two Column Layout

struct TwoColumnDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    let geometry: GeometryProxy
    @ObservedObject var whatIf: WhatIfSettings
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left Column
            VStack(spacing: 20) {
                HeroProgressView(goal: goal)
                EnhancedStatsGrid(viewModel: viewModel, goal: goal)
            }
            .frame(maxWidth: geometry.size.width * 0.4)
            
            // Right Column
            VStack(spacing: 20) {
                ForecastWidgetView(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    whatIf: whatIf
                )
                // Optional: show utility panels below charts on medium screens
                VStack(spacing: 16) {
                    InsightsView(viewModel: viewModel, goal: goal)
                    HStack(alignment: .top, spacing: 16) {
                        QuickActionsView(goal: goal)
                        RecentActivityView(goal: goal, viewModel: viewModel)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }
}

// MARK: - Forecast Widget

struct ForecastWidgetView: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var whatIf: WhatIfSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForecastWidgetHeader(viewModel: viewModel, goal: goal)
            
            if viewModel.isLoadingForecast || viewModel.isLoadingBalanceHistory {
                ChartSkeletonView(height: 300, type: .line)
            } else if !viewModel.balanceHistory.isEmpty && !viewModel.forecastData.isEmpty {
                ForecastChartView(
                    historicalData: viewModel.balanceHistory,
                    forecastData: viewModel.forecastData,
                    targetValue: goal.targetAmount,
                    targetDate: goal.deadline,
                    currency: goal.currency,
                    animateOnAppear: false,
                    overlaySeries: whatIf.enabled ? generateWhatIfOverlay() : nil,
                    overlayColor: .purple
                )
                .frame(height: 300)
            } else {
                ForecastPlaceholderView()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
        .cornerRadius(16)
    }
}

// MARK: - What‑If overlay generator
extension ForecastWidgetView {
    private func generateWhatIfOverlay() -> [BalanceHistoryPoint] {
        guard !viewModel.forecastData.isEmpty else { return [] }
        let startDate = Date()
        let endDate = goal.deadline
        let calendar = Calendar.current
        var points: [BalanceHistoryPoint] = []
        // Use forecast dates (weekly) as x-axis
        let dates = viewModel.forecastData
            .map { $0.date }
            .filter { $0 >= startDate && $0 <= endDate }
        // Helper calculators
        func monthsBetween(_ date: Date) -> Double {
            let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
            return Double(days) / 30.0
        }
        func daysBetween(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
        }
        // Estimate recent trend (currency/day) from last ~30 days of balance history
        let history = viewModel.balanceHistory
        var trendPerDay: Double = 0
        if history.count >= 2 {
            let recent = Array(history.suffix( min(history.count, 30) ))
            if let first = recent.first?.balance, let last = recent.last?.balance {
                let days = max(1, recent.count - 1)
                trendPerDay = (last - first) / Double(days)
            }
        }

        for date in dates {
            let contribution = whatIf.oneTime + whatIf.monthly * monthsBetween(date)
            let value = dashboardTotal + contribution + (Double(daysBetween(date)) * trendPerDay)
            points.append(BalanceHistoryPoint(date: date, balance: value, currency: goal.currency))
        }
        return points
    }
}


// MARK: - Forecast Widget Header

struct ForecastWidgetHeader: View {
    @ObservedObject var viewModel: DashboardViewModel
    let goal: Goal
    
    var body: some View {
        HStack {
            Text("Goal Forecast")
                .font(.headline)
                .fontWeight(.medium)
            
            Spacer()
            
            if let lastForecast = viewModel.forecastData.last {
                ForecastStatusIndicator(forecast: lastForecast, goal: goal)
            }
        }
    }
}

// MARK: - Forecast Status Indicator

struct ForecastStatusIndicator: View {
    let forecast: ForecastPoint
    let goal: Goal
    
    private var willReachGoal: Bool {
        forecast.realistic >= goal.targetAmount
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: willReachGoal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(willReachGoal ? AccessibleColors.success : AccessibleColors.warning)
            
            Text(willReachGoal ? "On Track" : "Behind")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(willReachGoal ? AccessibleColors.success : AccessibleColors.warning)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((willReachGoal ? AccessibleColors.success : AccessibleColors.warning).opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Forecast Placeholder

struct ForecastPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.accessibleSecondary)
            
            VStack(spacing: 4) {
                Text("No Forecast Available")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("Add more transactions to generate forecast predictions")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Quick Actions

struct QuickActionsView: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    @State private var showingAddAsset = false
    @State private var showingAddTransaction = false
    @State private var showingAssetPicker = false
    @State private var showingEditGoal = false
    @State private var selectedAsset: Asset?

    private var goalAssets: [Asset] { goal.allocatedAssets }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                Button(action: { showingAddAsset = true }) {
                    label(icon: "plus.circle.fill", title: "Add Asset")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(AccessibleColors.primaryInteractive)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    if goalAssets.count <= 1 {
                        selectedAsset = goalAssets.first
                        showingAddTransaction = selectedAsset != nil
                    } else {
                        showingAssetPicker = true
                    }
                }) {
                    label(icon: "arrow.down.circle.fill", title: "Add Transaction")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(goalAssets.isEmpty ? Color.gray.opacity(0.4) : AccessibleColors.success)
                        .cornerRadius(10)
                }
                .disabled(goalAssets.isEmpty)
                
                Button(action: { showingEditGoal = true }) {
                    label(icon: "pencil.circle.fill", title: "Edit Goal")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(AccessibleColors.warning)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
        .cornerRadius(16)
        .sheet(isPresented: $showingAddAsset) { AddAssetView(goal: goal) }
        .sheet(isPresented: $showingAddTransaction) {
            if let asset = selectedAsset { AddTransactionView(asset: asset) }
        }
        .sheet(isPresented: $showingAssetPicker) {
            NavigationView {
                List(goalAssets, id: \.id) { asset in
                    Button(action: {
                        selectedAsset = asset
                        showingAssetPicker = false
                        showingAddTransaction = true
                    }) {
                        HStack {
                            Image(systemName: "bitcoinsign.circle")
                            Text(asset.currency)
                            Spacer()
                            if let addr = asset.address { Text(addr).font(.caption2).foregroundColor(.secondary) }
                        }
                    }
                }
                .navigationTitle("Select Asset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAssetPicker = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditGoal) { EditGoalView(goal: goal, modelContext: modelContext) }
    }
    
    private func label(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title).fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Recent Activity

struct RecentActivityView: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showingAssetPicker = false
    @State private var selectedAsset: Asset?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.medium)
            
            if viewModel.recentTransactions.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.recentTransactions.prefix(5), id: \.id) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.asset.currency)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let note = tx.comment, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundColor(.accessibleSecondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let amountText = String(format: "%@%.2f", tx.amount >= 0 ? "+" : "", tx.amount)
                            Text(amountText)
                                .font(.subheadline)
                                .foregroundColor(tx.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                            Text(tx.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button(action: { showingAssetPicker = true }) {
                    HStack(spacing: 6) {
                        Text("View All")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.caption)
                    .foregroundColor(.accessiblePrimary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
        .cornerRadius(16)
        .sheet(isPresented: $showingAssetPicker) {
            NavigationView {
                List(goal.allocatedAssets, id: \.id) { asset in
                    NavigationLink(destination: TransactionHistoryView(asset: asset)) {
                        HStack {
                            Image(systemName: "bitcoinsign.circle")
                            Text(asset.currency)
                            Spacer()
                            if let addr = asset.address { Text(addr).font(.caption2).foregroundColor(.secondary) }
                        }
                    }
                }
                .navigationTitle("Assets")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingAssetPicker = false } } }
            }
        }
    }
}

// MARK: - Preview Support

// Mock ForecastDataPoint for preview
struct ForecastDataPoint {
    let realistic: Double
    let date: Date
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    return GoalDashboardView(goal: goal)
        .modelContainer(container)
}
