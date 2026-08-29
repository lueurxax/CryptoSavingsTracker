//
//  SimplePieChart.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SimplePieChart: View {
    let allocations: [(goal: Goal, percentage: Double, chartPercentage: Double)]
    let pendingReviewPercentage: Double
    let pendingReviewChartPercentage: Double
    let finishedReservedPercentage: Double
    let finishedReservedChartPercentage: Double
    let unallocatedPercentage: Double
    let unallocatedChartPercentage: Double
    
    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .teal, .indigo, .mint, .cyan, .brown
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Simple pie chart representation
            ZStack {
                ForEach(Array(allocations.enumerated()), id: \.offset) { index, item in
                    Circle()
                        .trim(from: trimFrom(for: index), to: trimTo(for: index))
                        .stroke(colors[index % colors.count], lineWidth: 40)
                        .rotationEffect(.degrees(-90))
                }

                if pendingReviewChartPercentage > 0 {
                    Circle()
                        .trim(
                            from: activeAllocatedChartPercentage,
                            to: min(
                                1,
                                activeAllocatedChartPercentage + pendingReviewChartPercentage
                            )
                        )
                        .stroke(AccessibleColors.error, lineWidth: 40)
                        .rotationEffect(.degrees(-90))
                }

                if finishedReservedChartPercentage > 0 {
                    Circle()
                        .trim(
                            from: activeAllocatedChartPercentage + pendingReviewChartPercentage,
                            to: min(
                                1,
                                activeAllocatedChartPercentage
                                    + pendingReviewChartPercentage
                                    + finishedReservedChartPercentage
                            )
                        )
                        .stroke(AccessibleColors.warning, lineWidth: 40)
                        .rotationEffect(.degrees(-90))
                }
                
                if unallocatedChartPercentage > 0 {
                    Circle()
                        .trim(from: 1.0 - unallocatedChartPercentage, to: 1.0)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 40)
                        .rotationEffect(.degrees(-90))
                }
                
                // Center text
                VStack(spacing: 2) {
                    Text(
                        allocatedDisplayPercentage,
                        format: .percent.precision(.fractionLength(0...1))
                    )
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Allocated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 150)
            .padding()
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(allocations.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colors[index % colors.count])
                            .frame(width: 12, height: 12)
                        
                        Text(item.goal.name)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(
                            item.percentage,
                            format: .percent.precision(.fractionLength(0...1))
                        )
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }

                if pendingReviewPercentage > 0 {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AccessibleColors.error)
                            .frame(width: 12, height: 12)

                        Label("Pending review", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)

                        Spacer()

                        Text(
                            pendingReviewPercentage,
                            format: .percent.precision(.fractionLength(0...1))
                        )
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }

                if finishedReservedPercentage > 0 {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AccessibleColors.warning)
                            .frame(width: 12, height: 12)

                        Label("Reserved as spent", systemImage: "lock.fill")
                            .font(.caption)

                        Spacer()

                        Text(
                            finishedReservedPercentage,
                            format: .percent.precision(.fractionLength(0...1))
                        )
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                if unallocatedPercentage > 0 {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        
                        Text("Unallocated")
                            .font(.caption)
                            .italic()
                        
                        Spacer()
                        
                        Text(
                            unallocatedPercentage,
                            format: .percent.precision(.fractionLength(0...1))
                        )
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func trimFrom(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return allocations.prefix(index).map(\.chartPercentage).reduce(0, +)
    }
    
    private func trimTo(for index: Int) -> CGFloat {
        return allocations.prefix(index + 1).map(\.chartPercentage).reduce(0, +)
    }

    private var activeAllocatedChartPercentage: Double {
        min(1, allocations.map(\.chartPercentage).reduce(0, +))
    }

    private var allocatedDisplayPercentage: Double {
        allocations.map(\.percentage).reduce(0, +)
            + pendingReviewPercentage
            + finishedReservedPercentage
    }
}
