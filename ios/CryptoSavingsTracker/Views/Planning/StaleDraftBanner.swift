//
//  StaleDraftBanner.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Unified Monthly Planning Architecture
//  Handles stale draft plans with pagination and clear action consequences
//

import SwiftUI
import SwiftData

/// Banner component for managing stale draft plans from past months
struct StaleDraftBanner: View {
    let stalePlans: [MonthlyPlan]
    let onMarkCompleted: (MonthlyPlan) -> Void
    let onMarkSkipped: (MonthlyPlan) -> Void
    let onDelete: (MonthlyPlan) -> Void

    @State private var showingDetails = false
    @State private var currentPage = 0
    private let itemsPerPage = 5

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
                                .foregroundColor(.orange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stalePlans.count) stale draft plan\(stalePlans.count == 1 ? "" : "s") from past months")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Tap to review and resolve")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if showingDetails {
                        VStack(alignment: .leading, spacing: 12) {
                            // Info box explaining consequences
                            VStack(alignment: .leading, spacing: 6) {
                                Text("What do these actions mean?")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Mark Completed**: Count as fulfilled (contributed the planned amount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "forward.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Mark Skipped**: Count as intentionally skipped (didn't contribute)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                        .frame(width: 16)

                                    Text("**Delete**: Remove plan entirely (no record of this month)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color.blue.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                            )

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
                                            .foregroundColor(currentPage == 0 ? .secondary.opacity(0.5) : .primary)
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
                                            .foregroundColor(currentPage >= totalPages - 1 ? .secondary.opacity(0.5) : .primary)
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

    // Get goal name from relationship or use "Unknown Goal"
    private var goalName: String {
        // This would need to be passed in or fetched via relationship
        "Goal"  // Placeholder - in real usage, this would come from plan relationship
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(Color.orange.opacity(0.2))
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
                        .foregroundColor(.secondary)
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
                    .foregroundColor(hovering ? .primary : .secondary)
                    .scaleEffect(hovering ? 1.1 : 1.0)
            }
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hovering = isHovering
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(hovering ? 0.08 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
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

#Preview("Stale Draft Banner") {
    let plans: [MonthlyPlan] = (0..<12).map { index in
        let plan = MonthlyPlan(
            goalId: UUID(),
            monthLabel: "2025-\(String(format: "%02d", index + 1))",
            requiredMonthly: Double.random(in: 500...2000),
            remainingAmount: Double.random(in: 5000...20000),
            monthsRemaining: Int.random(in: 1...12),
            currency: "USD",
            status: .onTrack,
            state: .draft
        )
        return plan
    }

    return VStack {
        StaleDraftBanner(
            stalePlans: plans,
            onMarkCompleted: { plan in
                print("Mark completed: \(plan.monthLabel)")
            },
            onMarkSkipped: { plan in
                print("Mark skipped: \(plan.monthLabel)")
            },
            onDelete: { plan in
                print("Delete: \(plan.monthLabel)")
            }
        )
        .padding()

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
    .background(Color(NSColor.controlBackgroundColor))
    #else
    .background(Color(.systemBackground))
    #endif
}

#Preview("Single Stale Plan Row") {
    let plan = MonthlyPlan(
        goalId: UUID(),
        monthLabel: "2025-10",
        requiredMonthly: 1500,
        remainingAmount: 15000,
        monthsRemaining: 10,
        currency: "EUR",
        status: .onTrack,
        state: .draft
    )

    return StalePlanRow(
        plan: plan,
        onMarkCompleted: { print("Completed") },
        onMarkSkipped: { print("Skipped") },
        onDelete: { print("Deleted") }
    )
    .padding()
    .frame(width: 500)
    #if os(macOS)
    .background(Color(NSColor.controlBackgroundColor))
    #else
    .background(Color(.systemBackground))
    #endif
}
