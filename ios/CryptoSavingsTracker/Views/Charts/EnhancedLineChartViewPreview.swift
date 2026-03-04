// Extracted preview-only declarations for NAV003 policy compliance.
// Source: EnhancedLineChartView.swift

//
//  EnhancedLineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview {
    let sampleData = (0..<10).map { day in
        BalanceHistoryPoint(
            date: Calendar.current.date(byAdding: .day, value: day, to: Date().addingTimeInterval(-86400 * 10))!,
            balance: Double(day * 200 + Int.random(in: -50...150)),
            currency: "USD"
        )
    }
    
    VStack(spacing: 20) {
        EnhancedLineChartView(
            dataPoints: sampleData,
            targetValue: 2000,
            currency: "USD"
        )
        .frame(height: 200)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        
        // Empty state example
        EnhancedLineChartView(
            dataPoints: [],
            targetValue: 2000,
            currency: "USD"
        )
        .frame(height: 200)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    .padding()
}
