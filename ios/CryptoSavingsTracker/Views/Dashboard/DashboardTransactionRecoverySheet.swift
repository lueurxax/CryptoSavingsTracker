//
//  DashboardTransactionRecoverySheet.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct DashboardTransactionRecoverySheet: View {
    let goalName: String
    let hasAssets: Bool
    let primaryActionTitle: String
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: hasAssets ? "list.bullet.circle" : "bitcoinsign.circle")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AccessibleColors.primaryInteractive)

                VStack(spacing: 8) {
                    Text(DashboardAccessibilityCopy.transactionRecoveryTitle(hasAssets: hasAssets))
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(
                        DashboardAccessibilityCopy.transactionRecoveryMessage(
                            goalName: goalName,
                            hasAssets: hasAssets
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(
                        DashboardAccessibilityCopy.transactionRecoveryMessage(
                            goalName: goalName,
                            hasAssets: hasAssets
                        )
                    )
                }

                Button(primaryActionTitle) {
                    onPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(primaryActionTitle)
                .accessibilityHint(DashboardAccessibilityCopy.transactionRecoveryPrimaryActionHint(hasAssets: hasAssets))
                .accessibilityIdentifier("dashboard.transaction_recovery.primary")

                Text(DashboardAccessibilityCopy.transactionRecoveryFooter(hasAssets: hasAssets))
                    .font(.footnote)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(DashboardAccessibilityCopy.transactionRecoveryFooter(hasAssets: hasAssets))
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                    }
                    .accessibilityHint(DashboardAccessibilityCopy.transactionRecoveryDismissHint(hasAssets: hasAssets))
                    .accessibilityIdentifier("dashboard.transaction_recovery.dismiss")
                }
            }
        }
    }
}
