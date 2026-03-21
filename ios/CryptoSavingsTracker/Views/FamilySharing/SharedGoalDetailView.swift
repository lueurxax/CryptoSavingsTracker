//
//  SharedGoalDetailView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalDetailView: View {
    let goal: FamilyShareInviteeGoalProjection
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stateBanner
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
                    .fill(goal.lifecycleState.tint.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(goal.emoji ?? "🎯")
                            .font(.title2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.goalName)
                        .font(.title.bold())
                    Text(goal.ownershipLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                FamilySharingStatusChip(
                    text: goal.lifecycleState.displayTitle,
                    systemImage: lifecycleSystemImage,
                    tint: goal.lifecycleState.tint
                )
                FamilySharingBadge(
                    text: "Read-only",
                    systemImage: "hand.raised.fill",
                    tint: AccessibleColors.secondaryInteractive
                )
            }
        }
    }

    private var stateBanner: some View {
        FamilySharingCard(
            title: stateBannerTitle,
            systemImage: goal.shareState.systemImage,
            tint: goal.shareState.tint
        ) {
            Text(goal.shareState == .active ? "Invitees can view this goal but cannot edit it." : goal.shareState.supportingCopy)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("sharedGoalDetailStateBanner-\(goal.id)")
    }

    private var stateBannerTitle: String {
        goal.shareState == .active ? "Read-only" : goal.shareState.displayTitle
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                FamilyShareMetricPill(title: "Current", value: goal.formattedCurrent, tint: goal.lifecycleState.tint)
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
                    Text("Status")
                        .font(.headline)
                    Text(goal.lifecycleState.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let detailSummary = goal.detailSummary {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Latest shared summary")
                            .font(.headline)
                        Text(detailSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    private var lifecycleSystemImage: String {
        switch goal.lifecycleState {
        case .current: return "clock.arrow.circlepath"
        case .onTrack: return "checkmark.circle"
        case .justStarted: return "sparkles"
        case .achieved: return "checkmark.circle.fill"
        case .expired: return "calendar.badge.exclamationmark"
        }
    }
}
