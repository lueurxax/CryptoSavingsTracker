//
//  UnifiedGoalRowView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//
//  Purpose: Single, configurable goal row component that works across all platforms
//  Replaces both GoalRowView (iOS) and GoalSidebarRow (macOS) with style-based configuration

import SwiftUI
import SwiftData

/// Unified goal row view that adapts to different platforms and contexts
struct UnifiedGoalRowView: View {
    // MARK: - Properties
    let goal: Goal
    let style: GoalRowStyle
    let refreshTrigger: UUID
    
    @StateObject private var viewModel: GoalRowViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initialization
    init(goal: Goal, style: GoalRowStyle = .detailed, refreshTrigger: UUID = UUID()) {
        self.goal = goal
        self.style = style
        self.refreshTrigger = refreshTrigger
        self._viewModel = StateObject(wrappedValue: GoalRowViewModel(goal: goal))
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: style == .compact ? 8 : 12) {
            // Emoji or icon
            emojiView
            
            // Main content - takes full width, no trailing chevron
            VStack(alignment: .leading, spacing: style == .compact ? 4 : 8) {
                // Primary row with name and optional status
                primaryRow

                // Secondary row with details (no percentage text)
                if style != .minimal {
                    secondaryRow
                }

                // Progress bar (this is the only progress indicator needed)
                progressBar

                // Optional description
                if style.showsDescription, let description = goal.goalDescription, !description.isEmpty {
                    descriptionView(description)
                }
            }
        }
        .padding(.vertical, style.verticalPadding)
        .contentShape(Rectangle())
        .task {
            await viewModel.loadAsyncProgress()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshData()
            }
        }
        .onChange(of: goal.allocatedAssets.count) { _, _ in
            Task {
                await viewModel.refreshData()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(goal.goalDescription ?? "Tap to view goal details")
    }
    
    // MARK: - View Components
    
    private var emojiView: some View {
        Group {
            if let emoji = viewModel.displayEmoji, !emoji.isEmpty {
                Text(emoji)
                    .font(style.emojiSize)
                    .frame(width: emojiFrameSize, height: emojiFrameSize)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "target")
                    .font(style == .compact ? .caption : .title2)
                    .foregroundColor(.accessibleSecondary)
                    .frame(width: emojiFrameSize, height: emojiFrameSize)
                    .accessibilityHidden(true)
            }
        }
    }
    
    private var primaryRow: some View {
        HStack {
            Text(goal.name)
                .font(style == .compact ? .headline : .headline)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // Status badge only shown for exceptional states (achieved, urgent, behind)
            if style.showsStatusBadge, let badge = viewModel.statusBadge {
                statusBadgeView(badge)
            } else if style == .compact {
                // Compact style shows time remaining instead
                Text(viewModel.timeRemainingText)
                    .font(.caption2)
                    .foregroundColor(viewModel.isUrgent ? .red : .secondary)
            }
        }
    }
    
    private var secondaryRow: some View {
        HStack(spacing: style == .compact ? 8 : 16) {
            if style == .detailed {
                // Time remaining with icon
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isUrgent ? "exclamationmark.triangle.fill" : "calendar")
                        .font(.caption2)
                        .foregroundColor(viewModel.isUrgent ? AccessibleColors.error : .accessibleSecondary)

                    Text(viewModel.timeRemainingText)
                        .font(.subheadline)
                        .foregroundColor(viewModel.isUrgent ? AccessibleColors.error : .accessibleSecondary)
                }
            } else if style == .compact {
                // Compact style shows target amount with proper formatting
                Text("Target: \(viewModel.formatAmount(goal.targetAmount, currency: goal.currency))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Amount only - progress bar shows percentage visually
            if style == .detailed {
                Text(viewModel.amountText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if viewModel.isLoading && !viewModel.hasLoadedInitialData {
                    // Show shimmer effect while loading
                    RoundedRectangle(cornerRadius: style == .compact ? 1 : 2)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: style.progressBarHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: style == .compact ? 1 : 2)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.gray.opacity(0.1),
                                            Color.gray.opacity(0.3),
                                            Color.gray.opacity(0.1)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * 0.3, height: style.progressBarHeight)
                                .offset(x: geometry.size.width * viewModel.shimmerOffset)
                                .animation(
                                    Animation.linear(duration: 1.5)
                                        .repeatForever(autoreverses: false),
                                    value: viewModel.shimmerOffset
                                )
                        )
                } else {
                    // Background track
                    RoundedRectangle(cornerRadius: style == .compact ? 1 : 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: style.progressBarHeight)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: style == .compact ? 1 : 2)
                        .fill(viewModel.progressBarColor)
                        .frame(width: max(0, geometry.size.width * viewModel.progressAnimation), height: style.progressBarHeight)
                        .animation(.easeInOut(duration: 0.6), value: viewModel.progressAnimation)
                }
            }
        }
        .frame(height: style.progressBarHeight)
    }
    
    private func statusBadgeView(_ badge: (text: String, color: Color, icon: String)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: badge.icon)
                .font(.caption2)
                .foregroundColor(badge.color)

            Text(badge.text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(badge.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badge.color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func descriptionView(_ description: String) -> some View {
        Text(description)
            .font(.caption)
            .foregroundColor(.accessibleSecondary)
            .lineLimit(2)
            .truncationMode(.tail)
    }
    
    // MARK: - Helper Properties
    
    private var emojiFrameSize: CGFloat {
        switch style {
        case .detailed, .card:
            return 32
        case .compact:
            return 20
        case .minimal:
            return 16
        }
    }
    
    private var accessibilityLabel: String {
        "\(viewModel.displayEmoji ?? "") \(goal.name)"
    }

    private var accessibilityValue: String {
        let progress = Int(viewModel.asyncProgress * 100)
        var value = "\(progress) percent complete, \(viewModel.timeRemainingText)"
        if let badge = viewModel.statusBadge {
            value += ", \(badge.text)"
        }
        return value
    }
}

// MARK: - Platform-Specific Extensions

extension UnifiedGoalRowView {
    /// iOS-specific detailed style with all features
    static func iOS(goal: Goal, refreshTrigger: UUID = UUID()) -> UnifiedGoalRowView {
        UnifiedGoalRowView(goal: goal, style: .detailed, refreshTrigger: refreshTrigger)
    }
    
    /// macOS-specific compact sidebar style
    static func macOS(goal: Goal, refreshTrigger: UUID = UUID()) -> UnifiedGoalRowView {
        UnifiedGoalRowView(goal: goal, style: .compact, refreshTrigger: refreshTrigger)
    }
    
    /// Minimal style for overviews and widgets
    static func minimal(goal: Goal, refreshTrigger: UUID = UUID()) -> UnifiedGoalRowView {
        UnifiedGoalRowView(goal: goal, style: .minimal, refreshTrigger: refreshTrigger)
    }
}

// MARK: - Preview Provider

#Preview("Detailed Style (iOS)") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(
        name: "Emergency Fund",
        currency: "USD",
        targetAmount: 5000,
        deadline: Date().addingTimeInterval(86400 * 90),
        emoji: "🛡️"
    )
    goal.goalDescription = "Build a safety net for unexpected expenses"
    container.mainContext.insert(goal)
    
    return List {
        UnifiedGoalRowView.iOS(goal: goal)
    }
    .modelContainer(container)
}

#Preview("Compact Style (macOS)") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(
        name: "Bitcoin Savings",
        currency: "BTC",
        targetAmount: 1.5,
        deadline: Date().addingTimeInterval(86400 * 180),
        emoji: "₿"
    )
    container.mainContext.insert(goal)
    
    return List {
        UnifiedGoalRowView.macOS(goal: goal)
    }
    .modelContainer(container)
}

#Preview("Minimal Style") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(
        name: "Vacation Fund",
        currency: "EUR",
        targetAmount: 3000,
        deadline: Date().addingTimeInterval(86400 * 60),
        emoji: "✈️"
    )
    container.mainContext.insert(goal)
    
    return VStack {
        UnifiedGoalRowView.minimal(goal: goal)
            .padding()
    }
    .modelContainer(container)
}