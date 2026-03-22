//
//  SharedGoalsSectionView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalsSectionView: View {
    let section: FamilyShareInviteeSectionProjection
    let onGoalSelected: (FamilyShareInviteeGoalProjection) -> Void
    let onPrimaryAction: (FamilyShareInviteeSectionProjection) -> Void
    @EnvironmentObject private var familyShareCoordinator: FamilyShareAcceptanceCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let freshnessLabel = makeFreshnessLabel() {
                FamilyShareFreshnessHeaderView(
                    label: freshnessLabel,
                    namespaceName: section.ownerIdentity.displayName,
                    onRetry: {
                        onPrimaryAction(section)
                    }
                )
                .accessibilityIdentifier("sharedGoalsFreshnessHeader-\(section.uiTestIdentifier)")
            } else {
                Text(section.ownerIdentity.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sharedGoalsFreshnessHeader-\(section.uiTestIdentifier)")
            }

            if showsEscalatedStateBanner {
                FamilySharingStateBanner(
                    title: section.state.displayTitle,
                    subtitle: section.summaryCopy ?? section.state.supportingCopy,
                    systemImage: section.state.systemImage,
                    tint: section.state.tint
                )
                .accessibilityIdentifier("sharedGoalsStateBanner-\(section.uiTestIdentifier)")
            }

            if section.goals.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.state == .removedOrNoLongerShared
                        ? "This shared goal set is no longer available."
                        : "No shared goals in this group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sharedGoalsEmptyState-\(section.uiTestIdentifier)")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(section.goals) { goal in
                        SharedGoalRowView(goal: goal) {
                            onGoalSelected(goal)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .onAppear {
            familyShareCoordinator.noteSharedSectionBecameVisible(section.namespaceID)
        }
        .accessibilityIdentifier("sharedGoalsSectionContent-\(section.uiTestIdentifier)")
    }

    /// Build freshness label from section freshness metadata.
    /// Prefers server-assigned `projectionServerTimestamp` over device-local `publishedAt`
    /// per Section 6.6.1 canonical clock source.
    private func makeFreshnessLabel() -> FamilyShareFreshnessLabel? {
        // Use server timestamp when available (canonical), fall back to device-local publishedAt
        let canonicalPublishTime = section.projectionServerTimestamp ?? section.publishedAt
        guard let publishedAt = canonicalPublishTime else { return nil }
        let tierOverride: FamilyShareFreshnessTier?
        switch section.state {
        case .temporarilyUnavailable:
            tierOverride = .temporarilyUnavailable
        case .removedOrNoLongerShared, .revoked:
            tierOverride = .removedOrNoLongerShared
        default:
            tierOverride = nil
        }
        return FamilyShareFreshnessLabel(
            publishedAt: publishedAt,
            rateSnapshotAt: section.rateSnapshotTimestamp,
            substate: familyShareCoordinator.freshnessSubstate(for: section.namespaceID),
            lastChecked: familyShareCoordinator.freshnessLastChecked(for: section.namespaceID),
            tierOverride: tierOverride,
            namespaceKey: section.namespaceID.namespaceKey
        )
    }

    private var showsEscalatedStateBanner: Bool {
        switch section.state {
        case .invitePendingAcceptance, .revoked, .removedOrNoLongerShared:
            return true
        case .emptySharedDataset, .active, .stale, .temporarilyUnavailable:
            return false
        }
    }
}

private extension FamilyShareInviteeSectionProjection {
    var uiTestIdentifier: String {
        namespaceID.namespaceKey.replacingOccurrences(of: "|", with: "-")
    }
}
