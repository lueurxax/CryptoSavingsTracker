//
//  SharedGoalDetailView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalDetailView: View {
    let goal: FamilySharedGoalSummary
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if goal.state == .active {
                    header
                    stateBanner
                } else {
                    stateBanner
                    header
                }
                metricsGrid
                detailsCard
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(goal.goalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onDismiss)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(goal.state.tint.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(goal.emoji ?? "🎯")
                            .font(.title2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.goalName)
                        .font(.title.bold())
                    Text(goal.ownerChip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            FamilySharingBadge(
                text: "Read only",
                systemImage: "hand.raised.fill",
                tint: AccessibleColors.secondaryInteractive
            )
        }
    }

    private var stateBanner: some View {
        FamilySharingCard(
            title: goal.state.displayTitle,
            systemImage: goal.state.systemImage,
            tint: goal.state.tint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(goal.state.supportingCopy)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if goal.state != .active {
                    FamilySharingBadge(
                        text: goal.state.primaryActionTitle,
                        systemImage: goal.state.systemImage,
                        tint: goal.state.tint
                    )
                }
            }
        }
        .accessibilityIdentifier("sharedGoalDetailStateBanner-\(goal.id)")
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                FamilyShareMetricPill(title: "Current", value: goal.formattedCurrent, tint: goal.state.tint)
                FamilyShareMetricPill(title: "Target", value: goal.formattedTarget, tint: AccessibleColors.primaryInteractive)
                FamilyShareMetricPill(title: "Deadline", value: goal.deadline.formatted(date: .abbreviated, time: .omitted), tint: AccessibleColors.secondaryInteractive)
                FamilyShareMetricPill(title: "Updated", value: goal.lastUpdatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown", tint: AccessibleColors.primaryInteractive)
            }
        }
    }

    private var detailsCard: some View {
        FamilySharingCard(
            title: "Shared Details",
            systemImage: "doc.text.magnifyingglass",
            tint: AccessibleColors.primaryInteractive
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Contribution Summary")
                        .font(.headline)
                    Text(goal.contributionSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Month")
                        .font(.headline)
                    Text(goal.currentMonthSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Access")
                        .font(.headline)
                    Text("Invitees can view goals only. Editing, import, planning, and export actions are intentionally unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
