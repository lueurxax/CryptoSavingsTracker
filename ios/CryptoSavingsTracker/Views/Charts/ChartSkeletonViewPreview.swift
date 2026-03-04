// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ChartSkeletonView.swift

//
//  ChartSkeletonView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview {
    VStack(spacing: 20) {
        ChartSkeletonView(height: 200, type: .line)
        ChartSkeletonView(height: 150, type: .ring)
        ChartSkeletonView(height: 120, type: .bar)
        ChartSkeletonView(height: 100, type: .heatmap)
    }
    .padding()
}
