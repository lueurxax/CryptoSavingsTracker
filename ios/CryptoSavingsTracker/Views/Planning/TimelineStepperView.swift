//
//  TimelineStepperView.swift
//  CryptoSavingsTracker
//
//  Created for Fixed Budget Planning - Timeline Visualization
//  Shows a horizontal timeline with goal segments and "You are here" indicator
//

import SwiftUI

/// A horizontal timeline visualization showing scheduled goal blocks with a "You are here" indicator.
struct TimelineStepperView: View {
    let blocks: [ScheduledGoalBlock]
    let currentPaymentNumber: Int

    private var totalPayments: Int {
        blocks.reduce(0) { $0 + $1.paymentCount }
    }

    private var progressFraction: Double {
        guard totalPayments > 0 else { return 0 }
        return Double(currentPaymentNumber) / Double(totalPayments)
    }

    var body: some View {
        if blocks.isEmpty || totalPayments == 0 {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                // "You are here" indicator
                youAreHereIndicator

                // Timeline track with goal segments
                timelineTrack

                // Goal labels below the timeline
                goalLabels
            }
        }
    }

    // MARK: - "You are here" Indicator

    private var youAreHereIndicator: some View {
        GeometryReader { geometry in
            let position = progressFraction * geometry.size.width

            HStack(spacing: 0) {
                Spacer()
                    .frame(width: max(0, position - 40))

                VStack(spacing: 2) {
                    Text("You are here")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)

                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .frame(width: 80)

                Spacer()
            }
        }
        .frame(height: 32)
    }

    // MARK: - Timeline Track

    private var timelineTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // Goal segments
                HStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        let width = geometry.size.width * CGFloat(block.paymentCount) / CGFloat(totalPayments)
                        Rectangle()
                            .fill(blockColor(for: index, isComplete: block.isComplete))
                            .frame(width: width, height: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Progress dot
                Circle()
                    .fill(Color.blue)
                    .frame(width: 16, height: 16)
                    .offset(x: progressFraction * geometry.size.width - 8)
                    .animation(.easeInOut(duration: 0.3), value: progressFraction)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Goal Labels

    private var goalLabels: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    let width = geometry.size.width * CGFloat(block.paymentCount) / CGFloat(totalPayments)

                    VStack(spacing: 2) {
                        // Emoji or icon
                        if let emoji = block.emoji, !emoji.isEmpty {
                            Text(emoji)
                                .font(.caption2)
                        }

                        // Goal name
                        Text(block.goalName)
                            .font(.caption2)
                            .foregroundStyle(block.isComplete ? .green : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Payment count
                        Text("\(block.paymentCount)mo")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 48)
    }

    // MARK: - Helpers

    private func blockColor(for index: Int, isComplete: Bool) -> Color {
        if isComplete {
            return .green
        }

        let colors: [Color] = [
            .blue,
            .purple,
            .orange,
            .pink,
            .teal,
            .indigo
        ]

        return colors[index % colors.count]
    }
}

/// Compact version of the timeline for smaller spaces.
struct CompactTimelineStepperView: View {
    let blocks: [ScheduledGoalBlock]
    let currentPaymentNumber: Int

    private var totalPayments: Int {
        blocks.reduce(0) { $0 + $1.paymentCount }
    }

    private var progressFraction: Double {
        guard totalPayments > 0 else { return 0 }
        return Double(currentPaymentNumber) / Double(totalPayments)
    }

    var body: some View {
        if blocks.isEmpty || totalPayments == 0 {
            EmptyView()
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with goal segments
                    HStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            let width = geometry.size.width * CGFloat(block.paymentCount) / CGFloat(totalPayments)
                            Rectangle()
                                .fill(blockColor(for: index, isComplete: block.isComplete).opacity(0.6))
                                .frame(width: width)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Progress overlay
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                        .frame(width: progressFraction * geometry.size.width)
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)
                }
            }
            .frame(height: 12)
        }
    }

    private func blockColor(for index: Int, isComplete: Bool) -> Color {
        if isComplete {
            return .green
        }

        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo]
        return colors[index % colors.count]
    }
}

// MARK: - Preview

#Preview("Timeline Stepper") {
    VStack(spacing: 20) {
        TimelineStepperView(
            blocks: [
                ScheduledGoalBlock(
                    id: UUID(),
                    goalId: UUID(),
                    goalName: "Emergency Fund",
                    emoji: "🏦",
                    paymentCount: 3,
                    estimatedStart: Date(),
                    estimatedEnd: Date().addingTimeInterval(86400 * 90),
                    isComplete: true
                ),
                ScheduledGoalBlock(
                    id: UUID(),
                    goalId: UUID(),
                    goalName: "Vacation",
                    emoji: "✈️",
                    paymentCount: 4,
                    estimatedStart: Date(),
                    estimatedEnd: Date().addingTimeInterval(86400 * 120),
                    isComplete: false
                ),
                ScheduledGoalBlock(
                    id: UUID(),
                    goalId: UUID(),
                    goalName: "New Car",
                    emoji: "🚗",
                    paymentCount: 6,
                    estimatedStart: Date(),
                    estimatedEnd: Date().addingTimeInterval(86400 * 180),
                    isComplete: false
                )
            ],
            currentPaymentNumber: 5
        )
        .padding()
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
        .cornerRadius(12)

        CompactTimelineStepperView(
            blocks: [
                ScheduledGoalBlock(
                    id: UUID(),
                    goalId: UUID(),
                    goalName: "Goal 1",
                    emoji: nil,
                    paymentCount: 3,
                    estimatedStart: Date(),
                    estimatedEnd: Date().addingTimeInterval(86400 * 90),
                    isComplete: true
                ),
                ScheduledGoalBlock(
                    id: UUID(),
                    goalId: UUID(),
                    goalName: "Goal 2",
                    emoji: nil,
                    paymentCount: 5,
                    estimatedStart: Date(),
                    estimatedEnd: Date().addingTimeInterval(86400 * 150),
                    isComplete: false
                )
            ],
            currentPaymentNumber: 4
        )
        .padding()
    }
    .padding()
}
