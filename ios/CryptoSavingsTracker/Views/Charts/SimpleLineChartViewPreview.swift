// Extracted preview-only declarations for NAV003 policy compliance.
// Source: SimpleLineChartView.swift

//
//  SimpleLineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview {
    let sampleData = (0..<30).map { day in
        BalanceHistoryPoint(
            date: Calendar.current.date(byAdding: .day, value: -30 + day, to: Date())!,
            balance: 5000 + Double.random(in: -500...1500) + (Double(day) * 50),
            currency: "USD"
        )
    }
    
    VStack(spacing: 20) {
        SimpleLineChartView(dataPoints: sampleData)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(12)
        
        SimpleLineChartView(dataPoints: sampleData, height: 80)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
    }
    .padding()
}
