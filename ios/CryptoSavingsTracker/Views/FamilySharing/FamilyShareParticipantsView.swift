//
//  FamilyShareParticipantsView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct FamilyShareParticipantsView: View {
    let participants: [FamilyShareParticipant]
    let onRevokeParticipant: (FamilyShareParticipant) -> Void
    let onRetryParticipant: (FamilyShareParticipant) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if participants.isEmpty {
                        emptyState
                    } else {
                        ForEach(participants) { participant in
                            participantRow(participant)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private var emptyState: some View {
        FamilySharingCard(
            title: "No Participants Yet",
            systemImage: "person.3",
            tint: AccessibleColors.secondaryInteractive
        ) {
            Text("Invite a family member to see the read-only shared goals list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func participantRow(_ participant: FamilyShareParticipant) -> some View {
        FamilySharingCard(
            title: participant.displayName,
            systemImage: participant.state.systemImage,
            tint: participant.state.tint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(participant.state.tint.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(participant.initials)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(participant.state.tint)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(participant.emailOrAlias ?? "No address available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let lastUpdatedAt = participant.lastUpdatedAt {
                            Text("Updated \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    FamilySharingStatusChip(
                        text: participant.state.displayTitle,
                        systemImage: participant.state.systemImage,
                        tint: participant.state.tint
                    )
                }

                HStack(spacing: 10) {
                    if participant.state == .active {
                        Button("Revoke Access") {
                            onRevokeParticipant(participant)
                        }
                        .buttonStyle(.bordered)
                    }

                    if participant.state == .pending || participant.state == .failed {
                        Button("Retry") {
                            onRetryParticipant(participant)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

