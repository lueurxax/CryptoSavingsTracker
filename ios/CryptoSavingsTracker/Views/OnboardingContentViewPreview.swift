// Extracted preview-only declarations for NAV003 policy compliance.
// Source: OnboardingContentView.swift

//
//  OnboardingContentView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData

#Preview {
    OnboardingContentView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
