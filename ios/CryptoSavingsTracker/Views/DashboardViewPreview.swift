// Extracted preview-only declarations for NAV003 policy compliance.
// Source: DashboardView.swift

import SwiftUI
import SwiftData

#Preview {
    return NavigationStack {
        DashboardView()
    }
    .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
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
        NavigationStack {
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
    
    var body: some View {
        // Use the enhanced GoalDashboardView which includes all the improved components
        GoalDashboardView(goal: goal)
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

struct MobileStatsSection: View {
    let goal: Goal
    @StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()
    
    var body: some View {
        EnhancedStatsGrid(viewModel: viewModel, goal: goal)
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
