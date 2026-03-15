//
//  CompactGoalRequirementRow.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 15/03/2026.
//

import SwiftUI

/// iPhone-only compact wrapper that keeps the shared GoalRequirementRow untouched for macOS.
struct CompactGoalRequirementRow: View {
    let requirement: MonthlyRequirement
    let flexState: MonthlyPlan.FlexState
    let adjustedAmount: Double?
    let showBudgetIndicator: Bool
    let onToggleProtection: () -> Void
    let onToggleSkip: () -> Void
    let onSetCustomAmount: ((Double?) -> Void)?

    @State private var showingGoalActions = false
    @State private var showingCustomAmountSheet = false

    private var effectiveAmount: Double {
        adjustedAmount ?? requirement.requiredMonthly
    }

    private var deadlineCopy: String {
        if requirement.monthsRemaining <= 0 {
            return "Overdue"
        }
        if requirement.monthsRemaining == 1 {
            return "1 month left"
        }
        return "\(requirement.monthsRemaining) months left"
    }

    private var progressCopy: String {
        "\(Int((min(max(requirement.progress, 0), 1) * 100).rounded()))% funded"
    }

    private var stateSummaryCopy: String? {
        if flexState == .skipped {
            return "Skipped this month"
        }

        if adjustedAmount != nil {
            return "Custom amount applied"
        }

        if flexState == .protected {
            return "Amount locked"
        }

        if showBudgetIndicator {
            return "From budget"
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                statusBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.goalName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button("Goal Actions") {
                    showingGoalActions = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AccessibleColors.primaryInteractive)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AccessibleColors.primaryInteractive.opacity(0.08))
                .clipShape(Capsule())
                .accessibilityIdentifier("goalActionsButton_\(requirement.goalId.uuidString)")
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatAmount(effectiveAmount, currency: requirement.currency))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(flexState == .skipped ? .secondary : .primary)

                    if let stateSummaryCopy {
                        Text(stateSummaryCopy)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    compactMetric(title: "Progress", value: progressCopy, color: statusColor)
                    compactMetric(
                        title: "Deadline",
                        value: deadlineCopy,
                        color: requirement.monthsRemaining <= 2 ? AccessibleColors.warning : .secondary
                    )
                }
            }

            ProgressView(value: min(max(requirement.progress, 0), 1))
                .tint(statusColor)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.planningRowCornerRadius)
                .fill(VisualComponentTokens.financeSurfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.planningRowCornerRadius)
                .stroke(VisualComponentTokens.financeSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VisualComponentTokens.planningRowCornerRadius))
        .sheet(isPresented: $showingGoalActions) {
            GoalActionsSheet(
                requirement: requirement,
                flexState: flexState,
                adjustedAmount: adjustedAmount,
                onToggleProtection: {
                    onToggleProtection()
                    showingGoalActions = false
                },
                onToggleSkip: {
                    onToggleSkip()
                    showingGoalActions = false
                },
                onRequestCustomAmount: {
                    showingGoalActions = false
                    showingCustomAmountSheet = true
                },
                onClearCustomAmount: {
                    onSetCustomAmount?(nil)
                    showingGoalActions = false
                },
                onClose: {
                    showingGoalActions = false
                }
            )
        }
        .sheet(isPresented: $showingCustomAmountSheet) {
            CustomAmountSheet(
                goalName: requirement.goalName,
                currency: requirement.currency,
                requiredAmount: requirement.requiredMonthly,
                currentCustomAmount: adjustedAmount,
                onSave: { amount in
                    onSetCustomAmount?(amount)
                    showingCustomAmountSheet = false
                },
                onCancel: {
                    showingCustomAmountSheet = false
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: requirement.status.systemImageName)
                .font(.caption.weight(.semibold))
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func compactMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }

    private var statusColor: Color {
        switch requirement.status {
        case .completed, .onTrack:
            return AccessibleColors.success
        case .attention:
            return AccessibleColors.warning
        case .critical:
            return AccessibleColors.error
        }
    }

    private var statusMessage: String {
        switch requirement.status {
        case .completed:
            return "Goal completed"
        case .onTrack:
            return "On track to meet deadline"
        case .attention:
            return "Goals changed, review this plan"
        case .critical:
            return "Requires immediate attention"
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = [
            requirement.goalName,
            formatAmount(effectiveAmount, currency: requirement.currency),
            progressCopy,
            deadlineCopy,
            requirement.status.displayName
        ]

        if let stateSummaryCopy {
            parts.append(stateSummaryCopy)
        }

        return parts.joined(separator: ", ")
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount.rounded()))"
    }
}

private struct GoalActionsSheet: View {
    let requirement: MonthlyRequirement
    let flexState: MonthlyPlan.FlexState
    let adjustedAmount: Double?
    let onToggleProtection: () -> Void
    let onToggleSkip: () -> Void
    let onRequestCustomAmount: () -> Void
    let onClearCustomAmount: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(requirement.goalName)
                            .font(.headline)
                        Text("Monthly plan: \(formatAmount(adjustedAmount ?? requirement.requiredMonthly, currency: requirement.currency))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(requirement.timeRemainingDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section("Goal Actions") {
                    Button(action: onToggleProtection) {
                        Label(
                            flexState == .protected ? "Unlock amount" : "Lock amount",
                            systemImage: flexState == .protected ? "lock.open" : "lock"
                        )
                    }

                    Button(action: onToggleSkip) {
                        Label(
                            flexState == .skipped ? "Include this month" : "Skip this month",
                            systemImage: flexState == .skipped ? "play.fill" : "forward.fill"
                        )
                    }

                    Button(action: onRequestCustomAmount) {
                        Label(
                            adjustedAmount != nil ? "Edit custom amount" : "Set custom amount",
                            systemImage: "dollarsign.circle"
                        )
                    }

                    if adjustedAmount != nil {
                        Button(role: .destructive, action: onClearCustomAmount) {
                            Label("Clear custom amount", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Goal Actions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount.rounded()))"
    }
}
