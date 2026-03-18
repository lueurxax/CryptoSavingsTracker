//
//  SharedGoalRowView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct SharedGoalRowView: View {
    let goal: FamilySharedGoalSummary
    let onTap: (() -> Void)?

    init(goal: FamilySharedGoalSummary, onTap: (() -> Void)? = nil) {
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

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.goalName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    FamilySharingStatusChip(
                        text: goal.state.displayTitle,
                        systemImage: goal.state.systemImage,
                        tint: goal.state.tint
                    )
                }

                HStack(spacing: 10) {
                    Text(goal.ownerChip)
                    Text("•")
                    Text(goal.currentMonthSummary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

                ProgressView(value: goal.progress)
                    .tint(goal.state.tint)

                HStack {
                    Text(goal.formattedCurrent)
                    Spacer(minLength: 8)
                    Text("of")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(goal.formattedTarget)
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
                .fill(goal.state.tint.opacity(0.12))
                .frame(width: 48, height: 48)

            Text(goal.emoji ?? "🎯")
                .font(.title3)
        }
    }

    private var accessibilityLabel: Text {
        Text(goal.goalName)
            + Text(", ")
            + Text(goal.ownerChip)
            + Text(", ")
            + Text(goal.state.displayTitle)
            + Text(", ")
            + Text(goal.currentMonthSummary)
    }
}

private extension FamilySharedGoalSummary {
    var uiTestIdentifier: String {
        id.replacingOccurrences(of: "|", with: "-")
    }
}
