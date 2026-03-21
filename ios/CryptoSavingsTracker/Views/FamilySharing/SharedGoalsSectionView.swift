//
//  SharedGoalsSectionView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalsOwnerHeaderView: View {
    let section: FamilyShareInviteeSectionProjection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(section.ownerIdentity.displayName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("sharedGoalsOwnerHeader-\(section.uiTestIdentifier)")
    }
}

struct SharedGoalsSectionView: View {
    let section: FamilyShareInviteeSectionProjection
    let onGoalSelected: (FamilyShareInviteeGoalProjection) -> Void
    let onPrimaryAction: (FamilyShareInviteeSectionProjection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section.showsStateBanner {
                FamilySharingStateBanner(
                    title: section.state.displayTitle,
                    subtitle: section.summaryCopy ?? section.state.supportingCopy,
                    systemImage: section.state.systemImage,
                    tint: section.state.tint
                )
                .accessibilityIdentifier("sharedGoalsStateBanner-\(section.uiTestIdentifier)")

                if let primaryActionTitle = section.primaryActionTitle {
                    Button(primaryActionTitle) {
                        onPrimaryAction(section)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sharedGoalsPrimaryAction-\(section.uiTestIdentifier)")
                }
            }

            if section.goals.isEmpty {
                Text("No shared goals are visible in this goal set yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityIdentifier("sharedGoalsSectionContent-\(section.uiTestIdentifier)")
    }
}

private extension FamilyShareInviteeSectionProjection {
    var uiTestIdentifier: String {
        namespaceID.namespaceKey.replacingOccurrences(of: "|", with: "-")
    }
}
