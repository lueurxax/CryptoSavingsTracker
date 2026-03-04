// Extracted preview-only declarations for NAV003 policy compliance.
// Source: HoverTooltipView.swift

//
//  HoverTooltipView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview {
    VStack(spacing: 30) {
        // Test hover tooltip
        HoverTooltipView(
            title: "Sample Metric",
            value: "$1,234.56",
            description: "This is additional information about the metric"
        ) {
            Rectangle()
                .fill(AccessibleColors.chartColor(at: 0))
                .frame(width: 100, height: 60)
                .cornerRadius(8)
        }
        
        // Test with chart data
        let sampleData = (0..<10).map { day in
            BalanceHistoryPoint(
                date: Calendar.current.date(byAdding: .day, value: -10 + day, to: Date())!,
                balance: 1000 + Double(day * 100),
                currency: "USD"
            )
        }
        
        SimpleLineChartView(dataPoints: sampleData)
            .withHoverTooltips()
            .frame(height: 200)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(12)
    }
    .padding()
}
