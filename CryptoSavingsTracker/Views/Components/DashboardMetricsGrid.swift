//
//  DashboardMetricsGrid.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct DashboardMetricsGrid: View {
    let goal: Goal
    @State private var currentTotal: Double = 0
    @State private var progress: Double = 0
    @State private var dailyTarget: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 12) {
            
            // Progress Metric
            MetricCard(
                title: "Progress",
                value: "\(Int(progress * 100))%",
                subtitle: "Complete",
                icon: "chart.pie.fill",
                color: progressColor,
                trend: progress > 0.5 ? .up : .neutral
            )
            
            // Days Remaining
            MetricCard(
                title: "Days Left",
                value: "\(goal.daysRemaining)",
                subtitle: "Until deadline",
                icon: daysRemainingIcon,
                color: daysRemainingColor,
                urgency: goal.daysRemaining < 30
            )
            
            // Current Value
            MetricCard(
                title: "Current",
                value: formatCurrency(currentTotal),
                subtitle: goal.currency,
                icon: "dollarsign.circle.fill",
                color: .accessiblePrimary,
                trend: currentTotal > goal.targetAmount * 0.5 ? .up : .neutral
            )
            
            // Daily Target
            MetricCard(
                title: "Daily Target",
                value: formatCurrency(dailyTarget),
                subtitle: "To reach goal",
                icon: "target",
                color: dailyTargetColor,
                isTarget: true
            )
        }
        .task {
            await updateMetrics()
        }
        .onChange(of: goal.allocations) { _, _ in
            Task {
                await updateMetrics()
            }
        }
    }
    
    private func updateMetrics() async {
        let total = await GoalCalculationService.getCurrentTotal(for: goal)
        let prog = await GoalCalculationService.getProgress(for: goal)
        let remaining = goal.targetAmount - total
        let days = max(goal.daysRemaining, 1)
        
        await MainActor.run {
            currentTotal = total
            progress = prog
            dailyTarget = remaining > 0 ? remaining / Double(days) : 0
            isLoading = false
        }
    }
    
    private var progressColor: Color {
        if progress >= 0.75 { return AccessibleColors.success }
        if progress >= 0.5 { return AccessibleColors.warning }
        return AccessibleColors.primaryInteractive
    }
    
    private var daysRemainingColor: Color {
        if goal.daysRemaining < 30 { return AccessibleColors.error }
        if goal.daysRemaining < 60 { return AccessibleColors.warning }
        return AccessibleColors.success
    }
    
    private var daysRemainingIcon: String {
        if goal.daysRemaining < 30 { return "exclamationmark.triangle.fill" }
        if goal.daysRemaining < 60 { return "clock.fill" }
        return "calendar"
    }
    
    private var dailyTargetColor: Color {
        if dailyTarget > currentTotal * 0.1 { return AccessibleColors.error }
        if dailyTarget > currentTotal * 0.05 { return AccessibleColors.warning }
        return AccessibleColors.success
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "%.1fK", amount / 1000)
        }
        return String(format: "%.0f", amount)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var trend: TrendDirection = .neutral
    var urgency: Bool = false
    var isTarget: Bool = false
    
    enum TrendDirection {
        case up, down, neutral
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return ""
            }
        }
        
        var color: Color {
            switch self {
            case .up: return AccessibleColors.success
            case .down: return AccessibleColors.error
            case .neutral: return .clear
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and trend
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                if trend != .neutral {
                    Image(systemName: trend.icon)
                        .font(.caption2)
                        .foregroundColor(trend.color)
                }
                
                if urgency {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(AccessibleColors.error)
                }
            }
            
            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if isTarget {
                    Image(systemName: "target")
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.7))
                }
            }
            
            // Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.accessibleSecondary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(urgency ? AccessibleColors.error.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 45))
    container.mainContext.insert(goal)
    
    return VStack {
        DashboardMetricsGrid(goal: goal)
        Spacer()
    }
    .padding()
    .modelContainer(container)
}