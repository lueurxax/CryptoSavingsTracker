//
//  HelpTooltip.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

/// A reusable tooltip component that provides contextual help for metrics and UI elements
struct HelpTooltip: View {
    let title: String
    let description: String
    let icon: String
    @State private var showTooltip = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    init(title: String, description: String, icon: String = "questionmark.circle") {
        self.title = title
        self.description = description
        self.icon = icon
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showTooltip.toggle()
            }
        }) {
            Image(systemName: icon)
                .foregroundColor(AccessibleColors.tertiaryText)
                .font(.caption)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Help: \(title)")
        .accessibilityHint("Double tap to show explanation")
        .popover(isPresented: $showTooltip, arrowEdge: .top) {
            TooltipContent(title: title, description: description)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Content view for the tooltip popover
struct TooltipContent: View {
    let title: String
    let description: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AccessibleColors.tertiaryText)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Close help")
            }
            
            Text(description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: 300)
        .background(AccessibleColors.lightBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

/// Predefined tooltip content for common metrics
struct MetricTooltips {
    // Progress Ring tooltips
    static let currentTotal = HelpTooltip(
        title: "Current Total",
        description: "The combined value of all your cryptocurrency assets in this goal, converted to your chosen currency using current exchange rates."
    )
    
    static let progress = HelpTooltip(
        title: "Progress Percentage",
        description: "How close you are to reaching your savings goal. Colors change from red (0-25%) to green (75-100%) to show your progress visually."
    )
    
    // Dashboard metrics tooltips
    static let dailyTarget = HelpTooltip(
        title: "Daily Target",
        description: "The amount you need to save each day to reach your goal by the deadline. This is calculated as: (Target Amount - Current Total) ÷ Days Remaining."
    )
    
    static let daysRemaining = HelpTooltip(
        title: "Days Remaining",
        description: "Number of days left until your goal deadline. The color turns red when less than 30 days remain as a reminder to increase your savings rate."
    )
    
    static let streak = HelpTooltip(
        title: "Savings Streak",
        description: "Number of consecutive days you've made transactions toward this goal. Maintaining a streak helps build consistent saving habits."
    )
    
    // Chart tooltips
    static let balanceHistory = HelpTooltip(
        title: "Balance History",
        description: "Shows how your total portfolio value has changed over time. The line represents the combined value of all assets in your chosen currency."
    )
    
    static let assetComposition = HelpTooltip(
        title: "Asset Breakdown",
        description: "Visual representation of how your portfolio is distributed across different cryptocurrencies. Each color represents a different asset."
    )
    
    static let forecast = HelpTooltip(
        title: "Goal Forecast",
        description: "Projections of whether you'll reach your goal based on current savings trends. Shows optimistic, realistic, and pessimistic scenarios."
    )
    
    static let heatmap = HelpTooltip(
        title: "Activity Heatmap",
        description: "Calendar view showing your transaction activity. Darker colors indicate days with more transaction volume. Helps identify saving patterns."
    )
    
    static let transactionCount = HelpTooltip(
        title: "Transaction Count",
        description: "Total number of buy/sell transactions recorded for this goal. Includes both manual entries and imported blockchain transactions."
    )
    
    // Forecast specific tooltips
    static let requiredDaily = HelpTooltip(
        title: "Required Daily Savings",
        description: "Based on your current progress and time remaining, this is the daily amount needed to reach your goal on schedule."
    )
    
    static let shortfall = HelpTooltip(
        title: "Projected Shortfall",
        description: "The estimated amount you'll be short of your goal if current trends continue. Consider increasing your savings rate or extending your deadline."
    )
    
    // Exchange rate tooltips
    static let exchangeRates = HelpTooltip(
        title: "Exchange Rates",
        description: "All cryptocurrency values are converted to your goal currency using real-time exchange rates from CoinGecko. Rates update automatically."
    )
}

/// Helper view to add tooltips to any content
struct TooltipModifier: ViewModifier {
    let tooltip: HelpTooltip
    
    func body(content: Content) -> some View {
        HStack(spacing: 4) {
            content
            tooltip
        }
    }
}

extension View {
    /// Adds a help tooltip next to the view
    func helpTooltip(_ tooltip: HelpTooltip) -> some View {
        modifier(TooltipModifier(tooltip: tooltip))
    }
    
    /// Convenience method for common metric tooltips
    func helpTooltip(title: String, description: String, icon: String = "questionmark.circle") -> some View {
        helpTooltip(HelpTooltip(title: title, description: description, icon: icon))
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Current Total: $5,000")
            .helpTooltip(MetricTooltips.currentTotal)
        
        Text("Daily Target: $50")
            .helpTooltip(MetricTooltips.dailyTarget)
        
        Text("Days Remaining: 45")
            .helpTooltip(MetricTooltips.daysRemaining)
    }
    .padding()
}