//
//  StaleDraftBanner.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Unified Monthly Planning Architecture
//  Handles stale draft plans with pagination and clear action consequences
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Banner component for managing stale draft plans from past months
struct StaleDraftBanner: View {
    let stalePlans: [MonthlyPlan]
    let onMarkCompleted: (MonthlyPlan) -> Void
    let onMarkSkipped: (MonthlyPlan) -> Void
    let onDelete: (MonthlyPlan) -> Void

    @State private var showingDetails = false
    @State private var currentPage = 0
    private let itemsPerPage = 5

    private var baselineStroke: Color {
        #if os(iOS)
        return Color(UIColor.separator).opacity(0.55)
        #elseif os(macOS)
        return Color(NSColor.separatorColor).opacity(0.55)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }

    private var totalPages: Int {
        max(1, (stalePlans.count + itemsPerPage - 1) / itemsPerPage)
    }

    private var currentPagePlans: [MonthlyPlan] {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, stalePlans.count)
        guard startIndex < stalePlans.count else { return [] }
        return Array(stalePlans[startIndex..<endIndex])
    }

    var body: some View {
        Group {
            if !stalePlans.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Header button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingDetails.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AccessibleColors.warning)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stalePlans.count) stale draft plan\(stalePlans.count == 1 ? "" : "s") from past months")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Tap to review and resolve")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding()
                        .background(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(baselineStroke, lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AccessibleColors.warning)
                                .frame(width: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if showingDetails {
                        VStack(alignment: .leading, spacing: 12) {
                            // Info box explaining consequences
                            VStack(alignment: .leading, spacing: 6) {
                                Text("What do these actions mean?")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AccessibleColors.success)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Mark Completed**: Count as fulfilled (contributed the planned amount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "forward.fill")
                                        .foregroundStyle(AccessibleColors.warning)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Mark Skipped**: Count as intentionally skipped (didn't contribute)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(AccessibleColors.error)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Delete**: Remove plan entirely (no record of this month)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(baselineStroke, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Paginated plan list
                            ForEach(currentPagePlans, id: \.id) { plan in
                                StalePlanRow(
                                    plan: plan,
                                    onMarkCompleted: { onMarkCompleted(plan) },
                                    onMarkSkipped: { onMarkSkipped(plan) },
                                    onDelete: { onDelete(plan) }
                                )
                            }

                            // Pagination controls
                            if totalPages > 1 {
                                HStack {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if currentPage > 0 {
                                                currentPage -= 1
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .foregroundStyle(currentPage == 0 ? Color.secondary.opacity(0.5) : Color.primary)
                                    }
                                    .disabled(currentPage == 0)
                                    .buttonStyle(.plain)

                                    Spacer()

                                    HStack(spacing: 4) {
                                        ForEach(0..<totalPages, id: \.self) { page in
                                            Circle()
                                                .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                                                .frame(width: 6, height: 6)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if currentPage < totalPages - 1 {
                                                currentPage += 1
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(currentPage >= totalPages - 1 ? Color.secondary.opacity(0.5) : Color.primary)
                                    }
                                    .disabled(currentPage >= totalPages - 1)
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else {
                EmptyView()
            }
        }
    }
}

/// Individual row for a stale plan
struct StalePlanRow: View {
    let plan: MonthlyPlan
    let onMarkCompleted: () -> Void
    let onMarkSkipped: () -> Void
    let onDelete: () -> Void

    @State private var showingActionSheet = false
    @State private var hovering = false

    private var baselineStroke: Color {
        #if os(iOS)
        return Color(UIColor.separator).opacity(0.55)
        #elseif os(macOS)
        return Color(NSColor.separatorColor).opacity(0.55)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }

    // Get goal name from relationship or use "Unknown Goal"
    private var goalName: String {
        // This would need to be passed in or fetched via relationship
        "Goal"  // Placeholder - in real usage, this would come from plan relationship
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(AccessibleColors.warningBackground)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatMonthLabel(plan.monthLabel))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Text("Planned: \(plan.formattedEffectiveAmount())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action menu
            Menu {
                Button {
                    onMarkCompleted()
                } label: {
                    Label("Mark as Completed", systemImage: "checkmark.circle")
                }

                Button {
                    onMarkSkipped()
                } label: {
                    Label("Mark as Skipped", systemImage: "forward.fill")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Plan", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .scaleEffect(hovering ? 1.1 : 1.0)
            }
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hovering = isHovering
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(baselineStroke, lineWidth: 1)
        )
    }

    private func formatMonthLabel(_ monthLabel: String) -> String {
        // Convert "2025-01" to "January 2025"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthLabel) else {
            return monthLabel
        }

        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Preview
