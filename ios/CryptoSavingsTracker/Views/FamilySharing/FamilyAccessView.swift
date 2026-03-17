//
//  FamilyAccessView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct FamilyAccessView: View {
    let model: FamilyAccessModel
    let onShareWithFamily: () -> Void
    let onRefresh: () -> Void
    let onShowScopePreview: () -> Void
    let onShowParticipants: () -> Void

    @State private var isShowingScopePreview = false
    @State private var isShowingParticipants = false

    init(
        model: FamilyAccessModel,
        onShareWithFamily: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onShowScopePreview: @escaping () -> Void,
        onShowParticipants: @escaping () -> Void
    ) {
        self.model = model
        self.onShareWithFamily = onShareWithFamily
        self.onRefresh = onRefresh
        self.onShowScopePreview = onShowScopePreview
        self.onShowParticipants = onShowParticipants
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                FamilySharingStateBanner(
                    title: model.state.displayTitle,
                    subtitle: model.state.supportingCopy,
                    systemImage: model.state.systemImage,
                    tint: model.state.tint
                )

                scopePreviewCard
                participantPreviewCard
                sharedGoalsPreviewCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isShowingScopePreview) {
            FamilyShareScopePreviewSheet(
                model: model.scopePreview,
                onContinue: {
                    isShowingScopePreview = false
                    onShareWithFamily()
                },
                onCancel: {
                    isShowingScopePreview = false
                }
            )
        }
        .sheet(isPresented: $isShowingParticipants) {
            FamilyShareParticipantsView(
                participants: model.participants,
                onRevokeParticipant: { _ in },
                onRetryParticipant: { _ in },
                onDismiss: {
                    isShowingParticipants = false
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Family Access")
                .font(.largeTitle.bold())

            Text(model.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    isShowingScopePreview = true
                    onShowScopePreview()
                } label: {
                    Label("Share with Family", systemImage: "person.2.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }

    private var scopePreviewCard: some View {
        FamilySharingCard(
            title: "Scope Preview",
            systemImage: "eye",
            tint: AccessibleColors.primaryInteractive
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.scopePreview.summaryPoints.enumerated()), id: \.offset) { _, point in
                    Label(point, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Review details") {
                    isShowingScopePreview = true
                    onShowScopePreview()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var participantPreviewCard: some View {
        FamilySharingCard(
            title: "Participants",
            systemImage: "person.3.fill",
            tint: AccessibleColors.secondaryInteractive
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if model.participants.isEmpty {
                    Text("No family members have been invited yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.participants.prefix(3)) { participant in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(participant.state.tint.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(participant.initials)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(participant.state.tint)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(participant.emailOrAlias ?? participant.state.displayTitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                FamilySharingStatusChip(
                                    text: participant.state.displayTitle,
                                    systemImage: participant.state.systemImage,
                                    tint: participant.state.tint
                                )
                            }
                        }
                    }
                }

                Button("Manage Participants") {
                    isShowingParticipants = true
                    onShowParticipants()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var sharedGoalsPreviewCard: some View {
        FamilySharingCard(
            title: "Shared Goals",
            systemImage: "tray.full",
            tint: AccessibleColors.success
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.ownerSections.prefix(2)) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(section.ownerName)
                                .font(.headline)
                            if section.isCurrentOwner {
                                FamilySharingBadge(
                                    text: "You",
                                    systemImage: "person.crop.circle",
                                    tint: AccessibleColors.primaryInteractive
                                )
                            }
                            Spacer(minLength: 0)
                        }

                        Text("\(section.goals.count) goal\(section.goals.count == 1 ? "" : "s") shared")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

