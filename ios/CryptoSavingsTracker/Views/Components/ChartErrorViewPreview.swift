// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ChartErrorView.swift

//
//  ChartErrorView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview("Chart Error View") {
    VStack(spacing: 20) {
        ChartErrorView(
            error: .dataUnavailable("No transactions found"),
            canRetry: true,
            onRetry: {}
        )
        
        ChartErrorView(
            error: .networkError("Unable to fetch exchange rates"),
            canRetry: true,
            onRetry: {}
        )
        
        CompactChartErrorView(
            error: .insufficientData(minimum: 5, actual: 2),
            onRetry: {}
        )
    }
    .padding()
}
