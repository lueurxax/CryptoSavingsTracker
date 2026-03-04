// Extracted preview-only declarations for NAV003 policy compliance.
// Source: EmptyStateView.swift

//
//  EmptyStateView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview {
    VStack(spacing: 40) {
        EmptyStateView.noGoals(onCreateGoal: {})
            .frame(height: 300)
        
        EmptyStateView.noAssets(onAddAsset: {})
            .frame(height: 300)
    }
    .padding()
}
