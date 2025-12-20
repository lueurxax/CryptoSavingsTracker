//
//  EnhancedDashboardComponents.swift
//  CryptoSavingsTracker
//
//  Enhanced dashboard components with improved visuals and insights
//

import SwiftUI
import SwiftData

// MARK: - Enhanced Stat Card

struct EnhancedStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: TrendIndicator?
    let tooltip: HelpTooltip?
    
    enum TrendIndicator {
        case up(String)
        case down(String)
        case neutral(String)
        
        var color: Color {
            switch self {
            case .up: return AccessibleColors.success
            case .down: return AccessibleColors.error
            case .neutral: return AccessibleColors.warning
            }
        }
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "arrow.right"
            }
        }
        
        var text: String {
            switch self {
            case .up(let text), .down(let text), .neutral(let text):
                return text
            }
        }
    }
    
    init(title: String, value: String, icon: String, color: Color, trend: TrendIndicator? = nil, tooltip: HelpTooltip? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.trend = trend
        self.tooltip = tooltip
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Icon with colored background
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18, weight: .medium))
                }
                
                Spacer()
                
                if let tooltip = tooltip {
                    tooltip
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
                
                if let trend = trend {
                    HStack(spacing: 4) {
                        Image(systemName: trend.icon)
                            .font(.caption2)
                        Text(trend.text)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(trend.color)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.04), Color.gray.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Insights View

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let goal: Goal
    
    private var insights: [Insight] {
        generateInsights()
    }
    
    struct Insight: Identifiable {
        let id = UUID()
        let type: InsightType
        let message: String
        let actionText: String?
        let action: (() -> Void)?
        
        enum InsightType {
            case success
            case warning
            case info
            case tip
            
            var icon: String {
                switch self {
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .info: return "info.circle.fill"
                case .tip: return "lightbulb.fill"
                }
            }
            
            var color: Color {
                switch self {
                case .success: return AccessibleColors.success
                case .warning: return AccessibleColors.warning
                case .info: return AccessibleColors.primaryInteractive
                case .tip: return AccessibleColors.warning
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insights")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .foregroundColor(AccessibleColors.warning)
                    .font(.caption)
            }
            
            if insights.isEmpty {
                Text("Keep tracking your savings to unlock insights!")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(insights.prefix(3)) { insight in
                        InsightCard(insight: insight)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private func generateInsights() -> [Insight] {
        var insights: [Insight] = []
        
        // Daily target achievement insight
        if viewModel.dailyTarget > 0 {
            let currentTotal = viewModel.balanceHistory.last?.balance ?? 0
            let yesterdayTotal = viewModel.balanceHistory.dropLast().last?.balance ?? 0
            let todayProgress = currentTotal - yesterdayTotal
            
            if todayProgress >= viewModel.dailyTarget {
                let percentage = Int((todayProgress / viewModel.dailyTarget - 1) * 100)
                insights.append(Insight(
                    type: .success,
                    message: "You're \(percentage)% ahead of your daily target. Keep it up!",
                    actionText: nil,
                    action: nil
                ))
            } else if todayProgress > 0 {
                let percentage = Int((todayProgress / viewModel.dailyTarget) * 100)
                insights.append(Insight(
                    type: .info,
                    message: "You've achieved \(percentage)% of today's target",
                    actionText: nil,
                    action: nil
                ))
            }
        }
        
        // Portfolio diversification insight
        if viewModel.assetComposition.count > 0 {
            let maxAllocation = viewModel.assetComposition.first?.percentage ?? 0
            if maxAllocation > 80 {
                let assetName = viewModel.assetComposition.first?.currency ?? "asset"
                insights.append(Insight(
                    type: .warning,
                    message: "Your portfolio is \(Int(maxAllocation))% \(assetName). Consider diversifying",
                    actionText: "Add Asset",
                    action: nil
                ))
            } else if viewModel.assetComposition.count >= 3 {
                insights.append(Insight(
                    type: .success,
                    message: "Well diversified! You have \(viewModel.assetComposition.count) different assets",
                    actionText: nil,
                    action: nil
                ))
            }
        }
        
        // Streak insight
        if viewModel.streak > 7 {
            insights.append(Insight(
                type: .success,
                message: "🔥 \(viewModel.streak) day streak! You're on fire!",
                actionText: nil,
                action: nil
            ))
        } else if viewModel.streak > 3 {
            insights.append(Insight(
                type: .info,
                message: "Building momentum with a \(viewModel.streak) day streak",
                actionText: nil,
                action: nil
            ))
        }
        
        // Days remaining insight
        if viewModel.daysRemaining > 0 && viewModel.daysRemaining < 30 {
            insights.append(Insight(
                type: .warning,
                message: "Only \(viewModel.daysRemaining) days left to reach your goal",
                actionText: "View Progress",
                action: nil
            ))
        }
        
        // Transaction frequency tip
        if viewModel.recentTransactions.isEmpty {
            insights.append(Insight(
                type: .tip,
                message: "Start tracking your crypto savings by adding your first transaction",
                actionText: "Add Transaction",
                action: nil
            ))
        } else if viewModel.recentTransactions.count < 3 {
            insights.append(Insight(
                type: .tip,
                message: "Regular contributions help build wealth. Consider setting up recurring deposits",
                actionText: nil,
                action: nil
            ))
        }
        
        // Progress toward goal
        if let currentTotal = viewModel.balanceHistory.last?.balance {
            let progress = (currentTotal / goal.targetAmount) * 100
            if progress >= 75 && progress < 100 {
                insights.append(Insight(
                    type: .success,
                    message: "Almost there! You're \(Int(progress))% of the way to your goal",
                    actionText: nil,
                    action: nil
                ))
            } else if progress >= 100 {
                insights.append(Insight(
                    type: .success,
                    message: "🎉 Congratulations! You've reached your goal!",
                    actionText: "Set New Goal",
                    action: nil
                ))
            }
        }
        
        return insights
    }
}

private struct InsightCard: View {
    let insight: InsightsView.Insight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.type.icon)
                .foregroundColor(insight.type.color)
                .font(.system(size: 20))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let actionText = insight.actionText {
                    Button(action: insight.action ?? {}) {
                        Text(actionText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(insight.type.color)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(insight.type.color.opacity(0.1))
        )
    }
}

// MARK: - Enhanced Stats Grid

struct EnhancedStatsGrid: View {
    @ObservedObject var viewModel: DashboardViewModel
    let goal: Goal
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            EnhancedStatCard(
                title: "Daily Target",
                value: String(format: "$%.0f", viewModel.dailyTarget),
                icon: "target",
                color: AccessibleColors.primaryInteractive,
                trend: calculateDailyTargetTrend()
            )
            
            EnhancedStatCard(
                title: "Days Left",
                value: "\(viewModel.daysRemaining)",
                icon: "calendar",
                color: viewModel.daysRemaining < 30 ? AccessibleColors.warning : AccessibleColors.success,
                trend: nil
            )
            
            EnhancedStatCard(
                title: "Streak",
                value: "\(viewModel.streak) days",
                icon: "flame.fill",
                color: AccessibleColors.warning,
                trend: viewModel.streak > 0 ? .up("+\(viewModel.streak)") : nil
            )
            
            EnhancedStatCard(
                title: "Transactions",
                value: "\(viewModel.transactionCount)",
                icon: "arrow.left.arrow.right",
                color: AccessibleColors.chartColor(at: 2),
                trend: calculateTransactionTrend()
            )
        }
    }
    
    private func calculateDailyTargetTrend() -> EnhancedStatCard.TrendIndicator? {
        guard let currentBalance = viewModel.balanceHistory.last?.balance,
              viewModel.dailyTarget > 0 else { return nil }
        
        let progress = currentBalance / goal.targetAmount
        if progress > 0.8 {
            return .up("On track")
        } else if progress > 0.5 {
            return .neutral("Steady")
        } else {
            return .down("Behind")
        }
    }
    
    private func calculateTransactionTrend() -> EnhancedStatCard.TrendIndicator? {
        let recentCount = viewModel.recentTransactions.count
        if recentCount > 3 {
            return .up("Active")
        } else if recentCount > 0 {
            return .neutral("Moderate")
        }
        return nil
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    container.mainContext.insert(goal)
    
    let viewModel = DIContainer.shared.makeDashboardViewModel()
    
    return ScrollView {
        VStack(spacing: 16) {
            EnhancedStatsGrid(viewModel: viewModel, goal: goal)
            InsightsView(viewModel: viewModel, goal: goal)
        }
        .padding()
    }
    .modelContainer(container)
}
