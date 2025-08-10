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
    @StateObject private var viewModel = DashboardViewModel()
    @State private var dashboardTotal: Double = 0.0
    @State private var dashboardProgress: Double = 0.0
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
                    dashboardProgress: dashboardProgress
                )
            } else {
                ExpandedDashboardLayout(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress
                )
            }
        }
        .platformPadding()
        .task {
            await viewModel.loadData(for: goal, modelContext: goal.modelContext!)
            await updateDashboard()
        }
        .onChange(of: goal.assets) { _, _ in
            Task {
                await updateDashboard()
            }
        }
    }
    
    @MainActor
    private func updateDashboard() async {
        dashboardTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        dashboardProgress = await GoalCalculationService.getProgress(for: goal)
    }
}

// MARK: - Compact Layout (Mobile)

struct CompactDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    
    var body: some View {
        VStack(spacing: 24) {
            HeroProgressView(goal: goal)
                .padding(.horizontal, 20)
            
            ForecastWidgetView(
                goal: goal,
                viewModel: viewModel,
                dashboardTotal: dashboardTotal,
                dashboardProgress: dashboardProgress
            )
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
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > 1200 {
                ThreeColumnDashboardLayout(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress
                )
            } else {
                TwoColumnDashboardLayout(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress,
                    geometry: geometry
                )
            }
        }
    }
}

// MARK: - Three Column Layout

struct ThreeColumnDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: Key Metrics + Hero Progress
            VStack(spacing: 20) {
                HeroProgressView(goal: goal)
                DashboardMetricsGrid(goal: goal)
            }
            .frame(maxWidth: 400)
            
            // Middle Column: Charts
            VStack(spacing: 20) {
                ForecastWidgetView(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress
                )
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Quick Actions & Stats
            VStack(spacing: 16) {
                QuickActionsPlaceholder(goal: goal)
                RecentActivityPlaceholder(goal: goal)
            }
            .frame(maxWidth: 300)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Two Column Layout

struct TwoColumnDashboardLayout: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    let dashboardTotal: Double
    let dashboardProgress: Double
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left Column
            VStack(spacing: 20) {
                HeroProgressView(goal: goal)
                DashboardMetricsGrid(goal: goal)
            }
            .frame(maxWidth: geometry.size.width * 0.4)
            
            // Right Column
            VStack(spacing: 20) {
                ForecastWidgetView(
                    goal: goal,
                    viewModel: viewModel,
                    dashboardTotal: dashboardTotal,
                    dashboardProgress: dashboardProgress
                )
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
                    animateOnAppear: false
                )
                .frame(height: 300)
            } else {
                ForecastPlaceholderView()
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
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

// MARK: - Placeholder Components

/// Placeholder for QuickActionsCard
struct QuickActionsPlaceholder: View {
    let goal: Goal
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                Button("Add Asset") {
                    // Add asset action
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
                
                Button("Add Transaction") {
                    // Add transaction action
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.green)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

/// Placeholder for RecentActivityCard
struct RecentActivityPlaceholder: View {
    let goal: Goal
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.medium)
            
            if goal.assets.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                Text("Activity: \(goal.assets.count) assets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
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