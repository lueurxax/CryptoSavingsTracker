//
//  GoalFormSupport.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 15/03/2026.
//

import SwiftUI

struct GoalFormInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AccessibleColors.error)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(AccessibleColors.error)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GoalFormBottomActionBar: View {
    let validationIssues: [String]
    let saveErrorMessage: String?
    let isSaving: Bool
    let primaryButtonTitle: String
    let primaryButtonIdentifier: String
    let focusedFieldIdentifier: String?
    let onRetry: (() -> Void)?
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let saveErrorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(AccessibleColors.error)
                            .padding(.top, 1)

                        Text(saveErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    if let onRetry {
                        Button("Retry") {
                            onRetry()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AccessibleColors.primaryInteractive)
                        .accessibilityIdentifier("goalFormRetryButton")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AccessibleColors.errorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("goalFormSaveError")
            } else if !validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review this goal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AccessibleColors.error)

                    ForEach(validationIssues, id: \.self) { issue in
                        GoalFormInlineError(message: issue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AccessibleColors.errorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("goalFormValidationSummary")
                .accessibilityValue(focusedFieldIdentifier ?? "none")
            }

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(primaryButtonTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSaving ? Color.gray : AccessibleColors.primaryInteractive)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)
            .accessibilityIdentifier(primaryButtonIdentifier)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: -2)
        .accessibilityIdentifier("goalFormBottomActionBar")
    }
}

struct GoalFormUITestHooks: View {
    let focusedFieldIdentifier: String?

    var body: some View {
        if UITestFlags.isEnabled {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(focusedFieldIdentifier ?? "none")
                .accessibilityIdentifier("goalFormFocusedField")
        }
    }
}
