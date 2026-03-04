// Extracted preview-only declarations for NAV003 policy compliance.
// Source: AddGoalView.swift

import SwiftUI
import SwiftData

#Preview {
    AddGoalView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
