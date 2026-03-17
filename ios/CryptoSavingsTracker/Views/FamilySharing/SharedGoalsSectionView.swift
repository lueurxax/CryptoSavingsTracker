//
//  SharedGoalsSectionView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalsSectionView: View {
    let sections: [FamilyShareOwnerSection]
    let onGoalSelected: (FamilySharedGoalSummary) -> Void
    let onPrimaryAction: (FamilyShareOwnerSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                FamilySharingCard(
                    title: section.ownerName,
                    systemImage: "person.2.fill",
                    tint: section.isCurrentOwner ? AccessibleColors.primaryInteractive : AccessibleColors.secondaryInteractive
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if section.isCurrentOwner {
                            FamilySharingBadge(
                                text: "Your family set",
                                systemImage: "person.crop.circle",
                                tint: AccessibleColors.primaryInteractive
                            )
                        }

                        if section.state != .active || section.goals.isEmpty {
                            FamilySharingStateBanner(
                                title: section.state.displayTitle,
                                subtitle: section.summaryCopy ?? section.state.supportingCopy,
                                systemImage: section.state.systemImage,
                                tint: section.state.tint
                            )
                        }

                        if let primaryActionTitle = section.primaryActionTitle,
                           section.state != .active || section.goals.isEmpty {
                            Button(primaryActionTitle) {
                                onPrimaryAction(section)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("sharedGoalsPrimaryAction-\(section.id)")
                        }

                        if section.goals.isEmpty {
                            Text("No shared goals are visible in this goal set yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
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
        }
        .accessibilityIdentifier("sharedGoalsSectionContent")
    }
}
