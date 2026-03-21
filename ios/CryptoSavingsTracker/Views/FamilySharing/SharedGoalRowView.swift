//
//  SharedGoalRowView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalRowView: View {
    let goal: FamilyShareInviteeGoalProjection
    let onTap: (() -> Void)?

    init(goal: FamilyShareInviteeGoalProjection, onTap: (() -> Void)? = nil) {
        self.goal = goal
        self.onTap = onTap
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            rowContent
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("sharedGoalRow-\(goal.uiTestIdentifier)")
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 14) {
            goalIcon

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(goal.goalName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Spacer(minLength: 0)

                    if let rowLifecycleChipTitle = goal.lifecycleState.defaultRowChipTitle {
                        FamilySharingStatusChip(
                            text: rowLifecycleChipTitle,
                            systemImage: lifecycleSystemImage,
                            tint: goal.lifecycleState.tint
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(goal.ownershipLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)

                ProgressView(value: goal.progress)
                    .tint(goal.lifecycleState.tint)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(goal.formattedCurrent)
                        Spacer(minLength: 8)
                        Text("of")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(goal.formattedTarget)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.formattedCurrent)
                        HStack(spacing: 4) {
                            Text("of")
                                .foregroundStyle(.secondary)
                            Text(goal.formattedTarget)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .fill(VisualComponentTokens.dashboardCardPrimaryFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .stroke(VisualComponentTokens.dashboardCardStroke, lineWidth: 1)
        )
        .accessibilityIdentifier("sharedGoalRow-\(goal.uiTestIdentifier).content")
    }

    private var goalIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(goal.lifecycleState.tint.opacity(0.12))
                .frame(width: 48, height: 48)

            Text(goal.emoji ?? "🎯")
                .font(.title3)
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

    private var accessibilityLabel: Text {
        var label = Text(goal.goalName)
            + Text(", ")
            + Text(goal.ownershipLine)

        if let rowLifecycleChipTitle = goal.lifecycleState.defaultRowChipTitle {
            label = label + Text(", ") + Text(rowLifecycleChipTitle)
        }

        label = label
            + Text(", ")
            + Text("\(goal.formattedCurrent) of \(goal.formattedTarget)")

        return label
    }
}

private extension FamilyShareInviteeGoalProjection {
    var uiTestIdentifier: String {
        id.replacingOccurrences(of: "|", with: "-")
    }
}
