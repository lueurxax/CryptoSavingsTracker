//
//  SimpleDashboardView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData

struct SimpleDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var goals: [Goal]
    
    @State private var selectedGoal: Goal?
    @State private var dashboardTotal: Double = 0.0
    @State private var dashboardProgress: Double = 0.0
    @State private var goalProgressData: [UUID: Double] = [:]
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showingBalanceHistoryDetail = false
    @AppStorage("preferAdvancedDashboard") private var preferAdvancedDashboard = false
    
    var selectedGoalOrFirst: Goal? {
        selectedGoal ?? goals.first
    }
    
    private var columns: [GridItem] {
        // Always use flexible layout that fills the available space
        return [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }
    
    private var isVeryWide: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    private var isSmallScreen: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }
    
    var body: some View {
            VStack(spacing: 0) {
                // Header
                if !goals.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Dashboard")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            
                            // Advanced dashboard toggle
                            if !goals.isEmpty {
                                Button(action: {
                                    preferAdvancedDashboard.toggle()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: preferAdvancedDashboard ? "rectangle.grid.3x2.fill" : "rectangle.grid.1x2")
                                        Text(preferAdvancedDashboard ? "Advanced" : "Simple")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.accessiblePrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accessiblePrimaryBackground)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                        
                        // Goal selector
                        if goals.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(goals) { goal in
                                        CompactGoalButton(
                                            goal: goal,
                                            progress: goalProgressData[goal.id] ?? 0.0,
                                            isSelected: selectedGoalOrFirst?.id == goal.id
                                        ) {
                                            withAnimation(.spring()) {
                                                selectedGoal = goal
                                                Task {
                                                    await updateDashboard()
                                                    await viewModel.loadData(for: goal, modelContext: modelContext)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom)
                } else {
                    // Enhanced empty state with guidance
                    NavigationLink(destination: AddGoalView()) {
                        EmptyStateView.noGoals(onCreateGoal: {})
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Dashboard content
                if let goal = selectedGoalOrFirst {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            // Progress Ring - single column on all layouts
                            VStack {
                                if viewModel.isLoading {
                                    ChartSkeletonView(height: isSmallScreen ? 120 : 150, type: .ring)
                                } else {
                                    ProgressRingView(
                                        progress: dashboardProgress,
                                        current: dashboardTotal,
                                        target: goal.targetAmount,
                                        currency: goal.currency,
                                        lineWidth: isSmallScreen ? 10 : 12,
                                        showLabels: true
                                    )
                                    .frame(height: isSmallScreen ? 120 : 150)
                                    
                                    Text("Goal Progress")
                                        .font(.caption)
                                        .foregroundColor(.accessibleSecondary)
                                }
                            }
                            .padding(16)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                            
                            // Summary Stats
                            InteractiveSummaryStatsView(
                                goal: goal, 
                                dashboardTotal: dashboardTotal,
                                dashboardProgress: dashboardProgress,
                                viewModel: viewModel
                            )
                            
                            // Balance History
                            if viewModel.balanceHistoryState.isLoading {
                                ChartSkeletonView(height: 120, type: .line)
                                } else if let error = viewModel.balanceHistoryState.error {
                                CompactChartErrorView(
                                    error: error,
                                    onRetry: viewModel.balanceHistoryState.canRetry ? {
                                        Task {
                                            await viewModel.retryBalanceHistory(for: goal, modelContext: modelContext)
                                        }
                                    } : nil
                                )
                            } else if !viewModel.balanceHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Balance History")
                                            .font(.headline)
                                        MetricTooltips.balanceHistory
                                        
                                        Spacer()
                                        
                                        // Expand button for detailed view
                                        Button(action: {
                                            showingBalanceHistoryDetail = true
                                        }) {
                                            HStack(spacing: 4) {
                                                Text("Expand")
                                                    .font(.caption)
                                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.accessiblePrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accessiblePrimaryBackground)
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    
                                    // Compact sparkline chart
                                    SparklineChartView(
                                        dataPoints: viewModel.balanceHistory,
                                        height: 60,
                                        showGradient: true
                                    )
                                    
                                    if let latest = viewModel.balanceHistory.last,
                                       let previous = viewModel.balanceHistory.dropLast().last {
                                        let change = latest.balance - previous.balance
                                        let changePercent = previous.balance > 0 ? (change / previous.balance) * 100 : 0
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                                .font(.caption)
                                            Text("\(String(format: "%.2f", abs(change))) (\(String(format: "%.1f", abs(changePercent)))%)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(change >= 0 ? AccessibleColors.success : AccessibleColors.error)
                                    }
                                }
                                .padding(16)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                            } else {
                                // Empty state for balance history
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Balance History")
                                            .font(.headline)
                                        MetricTooltips.balanceHistory
                                        Spacer()
                                    }
                                    
                                    VStack(spacing: 8) {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .font(.system(size: 32))
                                            .foregroundColor(.accessibleSecondary)
                                        
                                        Text("No balance history")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text("Start adding assets to track your progress!")
                                            .font(.caption)
                                            .foregroundColor(.accessibleSecondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(16)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable {
                        await loadAllGoalProgress()
                        await updateDashboard()
                        await viewModel.loadData(for: goal, modelContext: modelContext)
                    }
                    .onAppear {
                        Task {
                            await loadAllGoalProgress()
                            await updateDashboard()
                            await viewModel.loadData(for: goal, modelContext: modelContext)
                        }
                    }
                    .onChange(of: selectedGoalOrFirst?.assets) {
                        Task {
                            await updateDashboard()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarBackButtonHidden(false) // Fix navigation consistency
            .sheet(isPresented: $showingBalanceHistoryDetail) {
                if let goal = selectedGoalOrFirst {
                    BalanceHistoryDetailSheet(
                        goal: goal,
                        viewModel: viewModel
                    )
#if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
#endif
                }
            }
    }
    
    @MainActor
    private func updateDashboard() async {
        guard let goal = selectedGoalOrFirst else {
            dashboardTotal = 0.0
            dashboardProgress = 0.0
            return
        }
        
        dashboardTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        dashboardProgress = await GoalCalculationService.getProgress(for: goal)
    }
    
    @MainActor
    private func loadAllGoalProgress() async {
        for goal in goals {
            let progress = await GoalCalculationService.getProgress(for: goal)
            goalProgressData[goal.id] = progress
        }
    }
}

// MARK: - Interactive Summary Stats View
struct InteractiveSummaryStatsView: View {
    let goal: Goal
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showingTransactionDetails = false
    @State private var showingAssetBreakdown = false
    @State private var showingProgressDetails = false
    @State private var hoveredCard: String? = nil
    
    // Animated values for smooth transitions
    @State private var animatedAssetCount: Int = 0
    @State private var animatedTransactionCount: Int = 0
    @State private var animatedProgress: Double = 0
    @State private var animatedStreak: Int = 0
    
    // Card visibility for staggered animations
    @State private var showCards = false
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            // Assets Card
            InteractiveStatCard(
                title: "Assets",
                value: "\(animatedAssetCount)",
                icon: "bitcoinsign.circle.fill",
                color: AccessibleColors.chartColor(at: 0),
                subtitle: viewModel.isLoading ? "Loading..." : "Types",
                isHovered: hoveredCard == "assets"
            ) {
                showingAssetBreakdown = true
            }
            .onHover { hovering in
                hoveredCard = hovering ? "assets" : nil
            }
            .opacity(showCards ? 1 : 0)
            .offset(y: showCards ? 0 : 20)
            .animation(.easeOut(duration: 0.6), value: showCards)
            
            // Transactions Card  
            InteractiveStatCard(
                title: "Transactions",
                value: "\(animatedTransactionCount)",
                icon: "arrow.left.arrow.right.circle.fill",
                color: AccessibleColors.chartColor(at: 1),
                subtitle: "Total",
                isHovered: hoveredCard == "transactions"
            ) {
                showingTransactionDetails = true
            }
            .onHover { hovering in
                hoveredCard = hovering ? "transactions" : nil
            }
            .opacity(showCards ? 1 : 0)
            .offset(y: showCards ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.1), value: showCards)
            
            // Progress Card
            InteractiveStatCard(
                title: "Progress",
                value: "\(Int(animatedProgress * 100))%",
                icon: "target",
                color: animatedProgress >= 0.75 ? AccessibleColors.success : animatedProgress >= 0.5 ? AccessibleColors.warning : AccessibleColors.error,
                subtitle: "Complete",
                isHovered: hoveredCard == "progress"
            ) {
                showingProgressDetails = true
            }
            .onHover { hovering in
                hoveredCard = hovering ? "progress" : nil
            }
            .opacity(showCards ? 1 : 0)
            .offset(y: showCards ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.2), value: showCards)
            
            // Streak Card
            InteractiveStatCard(
                title: "Streak",
                value: "\(animatedStreak)",
                icon: "flame.fill",
                color: animatedStreak > 0 ? .accessibleStreak : .accessibleSecondary,
                subtitle: animatedStreak == 1 ? "Day" : "Days",
                isHovered: hoveredCard == "streak"
            ) {
                // No action for streak card - informational only
            }
            .onHover { hovering in
                hoveredCard = hovering ? "streak" : nil
            }
            .opacity(showCards ? 1 : 0)
            .offset(y: showCards ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: showCards)
        }
        .onAppear {
            // Show cards with staggered animation
            showCards = true
            
            // Initial animation on appear
            withAnimation(.easeInOut(duration: 0.8).delay(0.4)) {
                animatedAssetCount = goal.assets.count
                animatedProgress = dashboardProgress
            }
            // Delay transaction count and streak until viewModel data is likely loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    animatedTransactionCount = viewModel.transactionCount
                    animatedStreak = viewModel.streak
                }
            }
        }
        .onChange(of: goal.assets.count) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedAssetCount = newValue
            }
        }
        .onChange(of: viewModel.transactionCount) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedTransactionCount = newValue
            }
        }
        .onChange(of: viewModel.isLoading) { oldValue, newValue in
            // When loading completes, ensure we have the latest transaction data
            if oldValue && !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        animatedTransactionCount = viewModel.transactionCount
                        animatedStreak = viewModel.streak
                    }
                }
            }
        }
        .onChange(of: dashboardProgress) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = newValue
            }
        }
        .onChange(of: viewModel.streak) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedStreak = newValue
            }
        }
        .sheet(isPresented: $showingAssetBreakdown) {
            AssetBreakdownSheet(goal: goal, viewModel: viewModel)
#if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#endif
        }
        .sheet(isPresented: $showingTransactionDetails) {
            RecentTransactionsSheet(goal: goal, viewModel: viewModel)
#if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#endif
        }
        .sheet(isPresented: $showingProgressDetails) {
            ProgressDetailsSheet(
                goal: goal, 
                dashboardTotal: dashboardTotal,
                dashboardProgress: dashboardProgress,
                viewModel: viewModel
            )
#if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
        }
    }
}

// MARK: - Interactive Stat Card
struct InteractiveStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String
    let isHovered: Bool
    let action: (() -> Void)?
    
    init(title: String, value: String, icon: String, color: Color, subtitle: String, isHovered: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.subtitle = subtitle
        self.isHovered = isHovered
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    
                    Spacer()
                    
                    if action != nil {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                            .opacity(isHovered ? 1.0 : 0.6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(value)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.6), value: value)
                        Spacer()
                    }
                    
                    HStack {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isHovered ? color.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: isHovered ? color.opacity(0.2) : .black.opacity(0.1), 
                radius: isHovered ? 12 : 8, 
                x: 0, 
                y: isHovered ? 4 : 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(action == nil)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Detail Sheets

struct AssetBreakdownSheet: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.assetComposition.isEmpty {
                        // Chart section
                        VStack(spacing: 12) {
                            CompactAssetCompositionView(
                                assetCompositions: viewModel.assetComposition,
                                size: 150
                            )
                            .padding(.top, 8)
                            
                            Text("Asset Distribution")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                        }
                        
                        // Asset list section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Breakdown")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(viewModel.assetComposition) { asset in
                                    HStack {
                                        Circle()
                                            .fill(asset.color)
                                            .frame(width: 12, height: 12)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(asset.currency)
                                                .font(.headline)
                                                .fontWeight(.medium)
                                            Text("Portfolio allocation")
                                                .font(.caption)
                                                .foregroundColor(.accessibleSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(String(format: "%.2f", asset.value)) \(goal.currency)")
                                                .font(.headline)
                                                .fontWeight(.medium)
                                            Text("\(String(format: "%.1f", asset.percentage))%")
                                                .font(.caption)
                                                .foregroundColor(.accessibleSecondary)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            VStack(spacing: 16) {
                                Image(systemName: "bitcoinsign.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.accessibleSecondary)
                                
                                Text("No Assets Yet")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("Add cryptocurrency assets to see the breakdown")
                                    .font(.subheadline)
                                    .foregroundColor(.accessibleSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Asset Breakdown")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct RecentTransactionsSheet: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var recentTransactions: [Transaction] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !recentTransactions.isEmpty {
                        // Header
                        HStack {
                            Text("Recent Transactions")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Transaction list
                        VStack(spacing: 8) {
                            ForEach(recentTransactions.prefix(10)) { transaction in
                                HStack {
                                    // Icon and currency
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: transaction.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                                .foregroundColor(transaction.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                                            
                                            Text(transaction.asset.currency)
                                                .font(.headline)
                                                .fontWeight(.medium)
                                        }
                                        
                                        Text(transaction.date.formatted(.dateTime.month().day().year().hour().minute()))
                                            .font(.caption)
                                            .foregroundColor(.accessibleSecondary)
                                        
                                        if let comment = transaction.comment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.caption2)
                                                .foregroundColor(.accessibleSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Amount and type
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(transaction.amount >= 0 ? "+" : "")\(String(format: "%.4f", transaction.amount))")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(transaction.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                                        
                                        Text(transaction.amount >= 0 ? "Purchase" : "Sale")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                (transaction.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                                                    .opacity(0.1)
                                            )
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        if recentTransactions.count > 10 {
                            Text("Showing most recent 10 transactions")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                                .padding(.top)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            VStack(spacing: 16) {
                                Image(systemName: "arrow.left.arrow.right.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.accessibleSecondary)
                                
                                Text("No Transactions Yet")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("Transactions will appear here once you start adding them to your assets")
                                    .font(.subheadline)
                                    .foregroundColor(.accessibleSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Recent Activity")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadRecentTransactions()
            }
        }
    }
    
    private func loadRecentTransactions() {
        // Get all transactions for this goal's assets, sorted by date
        let goalAssets = goal.assets
        let allTransactions = goalAssets.flatMap { $0.transactions }
        recentTransactions = Array(allTransactions.sorted { $0.date > $1.date })
    }
}

struct ProgressDetailsSheet: View {
    let goal: Goal
    let dashboardTotal: Double
    let dashboardProgress: Double
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large progress ring with context
                    VStack(spacing: 16) {
                        ProgressRingView(
                            progress: dashboardProgress,
                            current: dashboardTotal,
                            target: goal.targetAmount,
                            currency: goal.currency,
                            lineWidth: 20,
                            showLabels: true
                        )
                        .frame(height: 200)
                        
                        // Quick summary
                        HStack(spacing: 16) {
                            VStack {
                                Text("\(Int(dashboardProgress * 100))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(dashboardProgress >= 0.75 ? AccessibleColors.success : dashboardProgress >= 0.5 ? AccessibleColors.warning : AccessibleColors.error)
                                Text("Complete")
                                    .font(.caption)
                                    .foregroundColor(.accessibleSecondary)
                            }
                            
                            VStack {
                                Text("\(goal.daysRemaining)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(goal.daysRemaining < 30 ? AccessibleColors.error : .primary)
                                Text("Days Left")
                                    .font(.caption)
                                    .foregroundColor(.accessibleSecondary)
                            }
                            
                            if viewModel.dailyTarget > 0 {
                                VStack {
                                    Text("\(String(format: "%.0f", viewModel.dailyTarget))")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text("Daily Target")
                                        .font(.caption)
                                        .foregroundColor(.accessibleSecondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Detailed progress breakdown
                    VStack(spacing: 16) {
                        HStack {
                            Text("Breakdown")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            ProgressDetailRow(
                                title: "Current Amount",
                                value: "\(String(format: "%.2f", dashboardTotal)) \(goal.currency)",
                                color: .primary
                            )
                            
                            ProgressDetailRow(
                                title: "Target Amount",
                                value: "\(String(format: "%.2f", goal.targetAmount)) \(goal.currency)",
                                color: AccessibleColors.success
                            )
                            
                            let remaining = goal.targetAmount - dashboardTotal
                            ProgressDetailRow(
                                title: "Remaining",
                                value: "\(String(format: "%.2f", remaining)) \(goal.currency)",
                                color: remaining > 0 ? AccessibleColors.warning : AccessibleColors.success
                            )
                            
                            Divider()
                            
                            ProgressDetailRow(
                                title: "Start Date",
                                value: goal.startDate.formatted(.dateTime.month().day().year()),
                                color: .accessibleSecondary
                            )
                            
                            ProgressDetailRow(
                                title: "Target Date",
                                value: goal.deadline.formatted(.dateTime.month().day().year()),
                                color: .accessibleSecondary
                            )
                            
                            ProgressDetailRow(
                                title: "Days Remaining",
                                value: "\(goal.daysRemaining) days",
                                color: goal.daysRemaining < 30 ? AccessibleColors.error : .primary
                            )
                            
                            if viewModel.dailyTarget > 0 {
                                Divider()
                                
                                ProgressDetailRow(
                                    title: "Daily Target",
                                    value: "\(String(format: "%.2f", viewModel.dailyTarget)) \(goal.currency)",
                                    color: AccessibleColors.chartColor(at: 2)
                                )
                                
                                let weeklyTarget = viewModel.dailyTarget * 7
                                ProgressDetailRow(
                                    title: "Weekly Target",
                                    value: "\(String(format: "%.2f", weeklyTarget)) \(goal.currency)",
                                    color: AccessibleColors.chartColor(at: 3)
                                )
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Progress Details")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ProgressDetailRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.accessibleSecondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Compact Goal Button
struct CompactGoalButton: View {
    let goal: Goal
    let progress: Double
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(goal.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? .primary : .primary)
                    .lineLimit(1)
                
                // Progress percentage with better contrast
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(progressColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(progressColor.opacity(0.15))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AccessibleColors.primaryInteractive.opacity(0.15) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected ? AccessibleColors.primaryInteractive : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private var progressColor: Color {
        if progress >= 0.75 {
            return AccessibleColors.success
        } else if progress >= 0.5 {
            return AccessibleColors.warning
        } else if progress > 0 {
            return AccessibleColors.error
        } else {
            return .accessibleSecondary
        }
    }
}

// MARK: - Balance History Detail Sheet

struct BalanceHistoryDetailSheet: View {
    let goal: Goal
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Full-size line chart
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Balance History")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        if !viewModel.balanceHistory.isEmpty {
                            // Large detailed chart
                            LineChartView(
                                dataPoints: viewModel.balanceHistory,
                                timeRange: .month,
                                animateOnAppear: true
                            )
                            .frame(height: 300)
                            .padding(.vertical)
                            
                            // Statistics section
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Statistics")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 16) {
                                    // Current Balance
                                    StatisticCard(
                                        title: "Current Balance",
                                        value: "\(String(format: "%.2f", viewModel.balanceHistory.last?.balance ?? 0)) \(goal.currency)",
                                        icon: "dollarsign.circle.fill",
                                        color: .accessiblePrimary
                                    )
                                    
                                    // Starting Balance
                                    StatisticCard(
                                        title: "Starting Balance",
                                        value: "\(String(format: "%.2f", viewModel.balanceHistory.first?.balance ?? 0)) \(goal.currency)",
                                        icon: "flag.circle.fill",
                                        color: .accessibleSecondary
                                    )
                                    
                                    // Total Change
                                    let totalChange = (viewModel.balanceHistory.last?.balance ?? 0) - (viewModel.balanceHistory.first?.balance ?? 0)
                                    StatisticCard(
                                        title: "Total Change",
                                        value: "\(totalChange >= 0 ? "+" : "")\(String(format: "%.2f", totalChange)) \(goal.currency)",
                                        icon: totalChange >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                                        color: totalChange >= 0 ? AccessibleColors.success : AccessibleColors.error
                                    )
                                    
                                    // Percentage Change
                                    let startBalance = viewModel.balanceHistory.first?.balance ?? 1
                                    let percentChange = startBalance > 0 ? (totalChange / startBalance) * 100 : 0
                                    StatisticCard(
                                        title: "Percentage Change",
                                        value: "\(percentChange >= 0 ? "+" : "")\(String(format: "%.1f", percentChange))%",
                                        icon: "percent.circle.fill",
                                        color: percentChange >= 0 ? AccessibleColors.success : AccessibleColors.error
                                    )
                                }
                            }
                            
                            // Goal progress section
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Goal Progress")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Target Amount")
                                            .font(.subheadline)
                                            .foregroundColor(.accessibleSecondary)
                                        Spacer()
                                        Text("\(String(format: "%.2f", goal.targetAmount)) \(goal.currency)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    let currentBalance = viewModel.balanceHistory.last?.balance ?? 0
                                    let progress = goal.targetAmount > 0 ? currentBalance / goal.targetAmount : 0
                                    let remaining = goal.targetAmount - currentBalance
                                    
                                    HStack {
                                        Text("Progress")
                                            .font(.subheadline)
                                            .foregroundColor(.accessibleSecondary)
                                        Spacer()
                                        Text("\(Int(progress * 100))%")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(progress >= 0.75 ? AccessibleColors.success : progress >= 0.5 ? AccessibleColors.warning : AccessibleColors.error)
                                    }
                                    
                                    HStack {
                                        Text("Remaining")
                                            .font(.subheadline)
                                            .foregroundColor(.accessibleSecondary)
                                        Spacer()
                                        Text("\(String(format: "%.2f", max(0, remaining))) \(goal.currency)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(remaining <= 0 ? AccessibleColors.success : .primary)
                                    }
                                    
                                    // Progress bar
                                    ProgressView(value: min(progress, 1.0))
                                        .progressViewStyle(LinearProgressViewStyle())
                                        .scaleEffect(y: 2)
                                }
                                .padding()
                                .background(.regularMaterial)
                                .cornerRadius(12)
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 60))
                                    .foregroundColor(.accessibleSecondary)
                                
                                Text("No Balance History")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("Balance history will appear here as you add transactions and track your progress over time.")
                                    .font(.subheadline)
                                    .foregroundColor(.accessibleSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical, 40)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Balance History")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Statistic Card

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Crypto Portfolio", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    return SimpleDashboardView()
        .modelContainer(container)
}
