// Extracted preview-only declarations for NAV003 policy compliance.
// Source: AddGoalView.swift

import SwiftUI
import SwiftData

#Preview("Add Goal Default") {
    AddGoalView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}

#Preview("Add Goal Invalid") {
    AddGoalView(
        previewState: .init(
            name: "",
            currency: "",
            targetAmount: "",
            hasAttemptedSubmit: true,
            showValidationWarnings: true
        )
    )
    .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}

#Preview("Add Goal Save Error") {
    AddGoalView(
        previewState: .init(
            name: "Family Travel",
            currency: "USD",
            targetAmount: "4500",
            saveErrorMessage: "Unable to save this goal right now. Please try again."
        )
    )
    .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}

#Preview("Add Goal Dynamic Type") {
    AddGoalView(
        previewState: .init(
            name: "",
            currency: "",
            targetAmount: "",
            hasAttemptedSubmit: true,
            showValidationWarnings: true
        )
    )
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
    .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
