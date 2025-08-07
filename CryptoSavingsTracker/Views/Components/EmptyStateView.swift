//
//  EmptyStateView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

/// A comprehensive empty state component that provides guidance and actions to users
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let primaryAction: EmptyStateAction?
    let secondaryAction: EmptyStateAction?
    let illustration: EmptyStateIllustration?
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    init(
        icon: String,
        title: String,
        description: String,
        primaryAction: EmptyStateAction? = nil,
        secondaryAction: EmptyStateAction? = nil,
        illustration: EmptyStateIllustration? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.illustration = illustration
    }
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        VStack(spacing: isCompact ? 16 : 24) {
            // Illustration or Icon
            Group {
                if let illustration = illustration {
                    illustration.view
                        .frame(width: isCompact ? 80 : 120, height: isCompact ? 80 : 120)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: isCompact ? 48 : 64))
                        .foregroundColor(AccessibleColors.tertiaryText)
                }
            }
            .padding(.top, isCompact ? 8 : 16)
            
            // Content
            VStack(spacing: isCompact ? 8 : 12) {
                Text(title)
                    .font(isCompact ? .title2 : .title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(isCompact ? .body : .title3)
                    .foregroundColor(AccessibleColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, isCompact ? 16 : 24)
            
            // Actions
            if primaryAction != nil || secondaryAction != nil {
                VStack(spacing: 12) {
                    if let primaryAction = primaryAction {
                        Button(action: primaryAction.action) {
                            HStack(spacing: 8) {
                                if let actionIcon = primaryAction.icon {
                                    Image(systemName: actionIcon)
                                        .font(.body)
                                }
                                Text(primaryAction.title)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(primaryAction.color)
                            .cornerRadius(8)
                        }
                        .accessibilityLabel(primaryAction.accessibilityLabel ?? primaryAction.title)
                    }
                    
                    if let secondaryAction = secondaryAction {
                        Button(action: secondaryAction.action) {
                            HStack(spacing: 8) {
                                if let actionIcon = secondaryAction.icon {
                                    Image(systemName: actionIcon)
                                        .font(.body)
                                }
                                Text(secondaryAction.title)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(secondaryAction.color)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(secondaryAction.color, lineWidth: 1)
                            )
                        }
                        .accessibilityLabel(secondaryAction.accessibilityLabel ?? secondaryAction.title)
                    }
                }
                .padding(.horizontal, isCompact ? 16 : 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, isCompact ? 24 : 32)
    }
}

/// Action configuration for empty states
struct EmptyStateAction {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void
    let accessibilityLabel: String?
    
    init(title: String, icon: String? = nil, color: Color = .blue, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Illustration options for empty states
enum EmptyStateIllustration {
    case chart
    case portfolio
    case transaction
    case goal
    case search
    
    @ViewBuilder
    var view: some View {
        switch self {
        case .chart:
            ChartIllustration()
        case .portfolio:
            PortfolioIllustration()
        case .transaction:
            TransactionIllustration()
        case .goal:
            GoalIllustration()
        case .search:
            SearchIllustration()
        }
    }
}

// MARK: - Illustration Views

struct ChartIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AccessibleColors.lightBackground)
                .stroke(AccessibleColors.tertiaryText.opacity(0.3), lineWidth: 1)
            
            VStack(spacing: 4) {
                // Simple line chart illustration
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 50))
                    path.addLine(to: CGPoint(x: 30, y: 30))
                    path.addLine(to: CGPoint(x: 50, y: 40))
                    path.addLine(to: CGPoint(x: 70, y: 20))
                    path.addLine(to: CGPoint(x: 90, y: 35))
                }
                .stroke(AccessibleColors.tertiaryText.opacity(0.5), lineWidth: 2)
                .frame(width: 80, height: 40)
                
                // X-axis indicators
                HStack {
                    ForEach(0..<5) { _ in
                        Circle()
                            .fill(AccessibleColors.tertiaryText.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
    }
}

struct PortfolioIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AccessibleColors.lightBackground)
                .stroke(AccessibleColors.tertiaryText.opacity(0.3), lineWidth: 1)
            
            // Pie chart segments
            ForEach(0..<3) { index in
                Circle()
                    .trim(from: Double(index) * 0.33, to: Double(index + 1) * 0.33)
                    .stroke(AccessibleColors.chartColor(at: index), lineWidth: 8)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct TransactionIllustration: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3) { index in
                HStack {
                    Circle()
                        .fill(index == 1 ? AccessibleColors.success : AccessibleColors.tertiaryText.opacity(0.3))
                        .frame(width: 6, height: 6)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AccessibleColors.tertiaryText.opacity(0.3))
                        .frame(width: 40, height: 4)
                    
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AccessibleColors.tertiaryText.opacity(0.3))
                        .frame(width: 20, height: 4)
                }
            }
        }
        .padding(8)
        .background(AccessibleColors.lightBackground)
        .cornerRadius(4)
    }
}

struct GoalIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AccessibleColors.lightBackground)
                .stroke(AccessibleColors.tertiaryText.opacity(0.3), lineWidth: 1)
            
            VStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 24))
                    .foregroundColor(AccessibleColors.tertiaryText.opacity(0.6))
                
                HStack {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < 1 ? AccessibleColors.success : AccessibleColors.tertiaryText.opacity(0.3))
                            .frame(width: 12, height: 4)
                    }
                }
            }
        }
    }
}

struct SearchIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AccessibleColors.lightBackground)
                .stroke(AccessibleColors.tertiaryText.opacity(0.3), lineWidth: 1)
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(AccessibleColors.tertiaryText.opacity(0.6))
        }
    }
}

// MARK: - Predefined Empty States

extension EmptyStateView {
    /// Empty state for when no goals exist
    static func noGoals(onCreateGoal: @escaping () -> Void, onStartOnboarding: (() -> Void)? = nil) -> EmptyStateView {
        // Check if user has completed onboarding
        let hasCompletedOnboarding = OnboardingManager.shared.hasCompletedOnboarding
        
        if hasCompletedOnboarding || onStartOnboarding == nil {
            // Show standard empty state for users who have completed onboarding
            return EmptyStateView(
                icon: "target",
                title: "No Savings Goals Yet",
                description: "Create your first cryptocurrency savings goal to start tracking your progress and building wealth.",
                primaryAction: EmptyStateAction(
                    title: "Create Your First Goal",
                    icon: "plus.circle.fill",
                    color: .blue,
                    accessibilityLabel: "Create your first savings goal",
                    action: onCreateGoal
                ),
                illustration: .goal
            )
        } else {
            // Show onboarding-focused empty state for new users
            return EmptyStateView(
                icon: "sparkles",
                title: "Welcome to CryptoSavings!",
                description: "Let's get you set up with a personalized savings goal. Our quick setup will help you choose the right cryptocurrencies and timeline.",
                primaryAction: EmptyStateAction(
                    title: "Start Quick Setup",
                    icon: "arrow.right.circle.fill",
                    color: .blue,
                    accessibilityLabel: "Start the guided setup process",
                    action: onStartOnboarding!
                ),
                secondaryAction: EmptyStateAction(
                    title: "Create Goal Manually",
                    icon: "plus.circle",
                    color: AccessibleColors.secondaryText,
                    accessibilityLabel: "Skip setup and create goal manually",
                    action: onCreateGoal
                ),
                illustration: .goal
            )
        }
    }
    
    /// Empty state for when no assets exist in a goal
    static func noAssets(onAddAsset: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "bitcoinsign.circle",
            title: "No Assets in Goal",
            description: "Add cryptocurrency assets to this goal to start tracking your portfolio and progress.",
            primaryAction: EmptyStateAction(
                title: "Add Your First Asset",
                icon: "plus.circle.fill",
                color: AccessibleColors.success,
                accessibilityLabel: "Add your first cryptocurrency asset",
                action: onAddAsset
            ),
            illustration: .portfolio
        )
    }
    
    /// Empty state for when no transactions exist
    static func noTransactions(onAddTransaction: @escaping () -> Void, onImportTransactions: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "arrow.left.arrow.right.circle",
            title: "No Transactions Yet",
            description: "Record your cryptocurrency purchases and sales to track your progress toward your savings goal.",
            primaryAction: EmptyStateAction(
                title: "Add Transaction",
                icon: "plus.circle.fill",
                color: .blue,
                accessibilityLabel: "Add a new transaction manually",
                action: onAddTransaction
            ),
            secondaryAction: EmptyStateAction(
                title: "Import from Blockchain",
                icon: "square.and.arrow.down",
                color: AccessibleColors.secondaryText,
                accessibilityLabel: "Import transactions from blockchain",
                action: onImportTransactions
            ),
            illustration: .transaction
        )
    }
    
    /// Empty state for chart data
    static func noChartData(chartType: String) -> EmptyStateView {
        EmptyStateView(
            icon: "chart.line.uptrend.xyaxis",
            title: "No Data to Display",
            description: "Add transactions to your assets to see \(chartType.lowercased()) data. Your chart will automatically update as you record activity.",
            illustration: .chart
        )
    }
    
    /// Empty state for search results
    static func noSearchResults(query: String, onClearSearch: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            description: "No cryptocurrencies match '\(query)'. Try searching with a different term or symbol.",
            primaryAction: EmptyStateAction(
                title: "Clear Search",
                icon: "xmark.circle",
                color: AccessibleColors.secondaryText,
                accessibilityLabel: "Clear search and show all cryptocurrencies",
                action: onClearSearch
            ),
            illustration: .search
        )
    }
    
    /// Empty state for activity/heatmap
    static func noActivity() -> EmptyStateView {
        EmptyStateView(
            icon: "calendar",
            title: "No Activity Yet",
            description: "Start making transactions to see your activity patterns. Consistent trading helps build good investment habits.",
            illustration: .chart
        )
    }
    
    /// Empty state for forecast data
    static func noForecastData() -> EmptyStateView {
        EmptyStateView(
            icon: "crystal.ball",
            title: "Insufficient Data for Forecast",
            description: "Add more transaction history to generate meaningful projections. We need at least a few data points to predict trends.",
            illustration: .chart
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        EmptyStateView.noGoals(onCreateGoal: {})
            .frame(height: 300)
        
        EmptyStateView.noAssets(onAddAsset: {})
            .frame(height: 300)
    }
    .padding()
}