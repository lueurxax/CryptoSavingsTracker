//
//  SharedGoalsSectionView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalsOwnerHeaderView: View {
    let section: FamilyShareOwnerSection

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.ownerName)
                    .font(.headline)

                Text(section.summaryCopy ?? section.state.supportingCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if section.isCurrentOwner {
                    FamilySharingBadge(
                        text: "You",
                        systemImage: "person.crop.circle",
                        tint: AccessibleColors.primaryInteractive
                    )
                }

                FamilySharingStatusChip(
                    text: section.state.displayTitle,
                    systemImage: section.state.systemImage,
                    tint: section.state.tint
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("sharedGoalsOwnerHeader-\(section.uiTestIdentifier)")
    }
}

struct SharedGoalsSectionView: View {
    let section: FamilyShareOwnerSection
    let onGoalSelected: (FamilySharedGoalSummary) -> Void
    let onPrimaryAction: (FamilyShareOwnerSection) -> Void

    var body: some View {
        FamilySharingCard(
            title: nil,
            systemImage: nil,
            tint: section.isCurrentOwner ? AccessibleColors.primaryInteractive : AccessibleColors.secondaryInteractive
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if UITestFlags.isEnabled {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 1)
                        .accessibilityIdentifier("sharedGoalsOwnerHeader-\(section.uiTestIdentifier)")
                }

                FamilySharingSectionHeader(
                    title: section.ownerName,
                    subtitle: section.summaryCopy ?? section.state.supportingCopy,
                    tint: section.isCurrentOwner ? AccessibleColors.primaryInteractive : AccessibleColors.secondaryInteractive
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sharedGoalsOwnerHeader-\(section.uiTestIdentifier)")

                if section.state != .active || section.goals.isEmpty {
                    if UITestFlags.isEnabled {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 1)
                            .accessibilityIdentifier("sharedGoalsStateBanner-\(section.uiTestIdentifier)")
                    }

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
                } else {
                    VStack(spacing: 12) {
                        ForEach(section.goals) { goal in
                            SharedGoalRowView(
                                goal: goal,
                                onTap: {
                                    onGoalSelected(goal)
                                }
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("sharedGoalsSectionContent-\(section.uiTestIdentifier)")
    }
}

private extension FamilyShareOwnerSection {
    var uiTestIdentifier: String {
        id.replacingOccurrences(of: "|", with: "-")
    }
}
