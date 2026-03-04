// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ProgressRingView.swift

//
//  ProgressRingView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview("Progress Ring") {
    VStack(spacing: 20) {
        ProgressRingView(
            progress: 0.75,
            current: 7500,
            target: 10000,
            currency: "USD"
        )
        .frame(width: 200, height: 200)
        
        ProgressRingView(
            progress: 1.25,
            current: 12500,
            target: 10000,
            currency: "EUR"
        )
        .frame(width: 200, height: 200)
        
        HStack(spacing: 20) {
            CompactProgressRingView(progress: 0.3, size: 60)
            CompactProgressRingView(progress: 0.6, size: 60)
            CompactProgressRingView(progress: 0.9, size: 60)
            CompactProgressRingView(progress: 1.2, size: 60)
        }
    }
    .padding()
}
