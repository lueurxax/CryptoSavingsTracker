//
//  BudgetNoticesView.swift
//  CryptoSavingsTracker
//
//  Budget migration and recalculation notices.
//

import SwiftUI

struct BudgetNoticesView: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    let onRecalculate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if viewModel.showBudgetMigrationNotice {
                noticeCard(
                    title: "Budget Applied",
                    message: "Your budget has been applied to this plan. You can now adjust individual goals.",
                    primaryAction: ("Got it", { viewModel.dismissBudgetMigrationNotice() }),
                    secondaryAction: nil
                )
            }

            if viewModel.showBudgetRecalculationPrompt {
                noticeCard(
                    title: "Budget Needs Review",
                    message: "Your goals or month changed. Recalculate budget allocations?",
                    primaryAction: ("Recalculate", onRecalculate),
                    secondaryAction: ("Keep current", { viewModel.acknowledgeBudgetRecalculationPrompt() })
                )
            }
        }
    }

    private func noticeCard(
        title: String,
        message: String,
        primaryAction: (String, () -> Void),
        secondaryAction: (String, () -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button(primaryAction.0, action: primaryAction.1)
                    .buttonStyle(.borderedProminent)

                if let secondaryAction {
                    Button(secondaryAction.0, action: secondaryAction.1)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
