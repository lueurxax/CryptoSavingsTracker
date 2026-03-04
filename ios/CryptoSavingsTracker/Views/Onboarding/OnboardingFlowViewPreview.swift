// Extracted preview-only declarations for NAV003 policy compliance.
// Source: OnboardingFlowView.swift

import SwiftUI
import SwiftData

#Preview {
    OnboardingFlowView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
