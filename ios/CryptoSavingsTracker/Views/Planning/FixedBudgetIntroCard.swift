//
//  FixedBudgetIntroCard.swift
//  CryptoSavingsTracker
//
//  Introduces Fixed Budget Mode to users who haven't seen it yet
//

import SwiftUI

/// A promotional card introducing Fixed Budget Mode to users
struct FixedBudgetIntroCard: View {
    let onLearnMore: () -> Void
    let onTryIt: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with dismiss button
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .font(.title3)

                Text("New: Fixed Budget Mode")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss intro card")
            }

            // Description
            Text("Set one monthly savings amount, and we'll optimize which goals to fund first based on deadlines.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Perfect for users with fixed salaries who want predictable monthly payments.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Action buttons
            HStack {
                Button("Learn More", action: onLearnMore)
                    .font(.subheadline)
                    .foregroundStyle(AccessibleColors.primaryInteractive)

                Spacer()

                Button(action: onTryIt) {
                    Text("Try It")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack {
        FixedBudgetIntroCard(
            onLearnMore: {},
            onTryIt: {},
            onDismiss: {}
        )
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
