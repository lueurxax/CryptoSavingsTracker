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
    let goalNamesByID: [UUID: String]
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

                                Text("Review each draft and decide how to handle it")
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
                    .accessibilityIdentifier("staleDraftBannerToggle")

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

                                    Text("**Mark completed**: Keep this draft as fulfilled for that month")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "forward.fill")
                                        .foregroundStyle(AccessibleColors.warning)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Mark skipped**: Keep the month in history but mark it as intentionally skipped")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(AccessibleColors.error)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Delete**: Remove the draft entirely with no historical record for that month")
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
                                    goalName: goalNamesByID[plan.goalId] ?? "Unknown goal",
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
    let goalName: String
    let onMarkCompleted: () -> Void
    let onMarkSkipped: () -> Void
    let onDelete: () -> Void

    @State private var showingResolveActions = false
    @State private var showingDeleteConfirmation = false
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

    private var monthTitle: String {
        formatMonthLabel(plan.monthLabel)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AccessibleColors.warning)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(goalName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(monthTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Planned: \(plan.formattedEffectiveAmount())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Resolve") {
                showingResolveActions = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AccessibleColors.primaryInteractive)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AccessibleColors.primaryInteractive.opacity(0.08))
            .clipShape(Capsule())
            .accessibilityIdentifier("staleDraftResolve_\(plan.id.uuidString)")
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
        .accessibilityIdentifier("staleDraftRow_\(plan.id.uuidString)")
        .confirmationDialog(
            "Resolve \(goalName) draft for \(monthTitle)",
            isPresented: $showingResolveActions,
            titleVisibility: .visible
        ) {
            Button("Mark completed") {
                onMarkCompleted()
            }

            Button("Mark skipped") {
                onMarkSkipped()
            }

            Button("Delete draft", role: .destructive) {
                showingDeleteConfirmation = true
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how to handle the saved draft for \(goalName) in \(monthTitle).")
        }
        .alert(
            "Delete \(goalName) draft for \(monthTitle)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Draft", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the draft for \(monthTitle) with no historical record kept.")
        }
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
