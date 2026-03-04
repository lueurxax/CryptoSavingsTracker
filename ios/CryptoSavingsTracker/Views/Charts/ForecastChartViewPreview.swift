// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ForecastChartView.swift

//
//  ForecastChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview("Forecast Chart") {
    let historicalData = (0..<60).map { day in
        BalanceHistoryPoint(
            date: Calendar.current.date(byAdding: .day, value: -60 + day, to: Date())!,
            balance: 3000 + Double(day) * 40 + Double.random(in: -200...200),
            currency: "USD"
        )
    }
    
    let forecastData = (1..<90).map { day in
        let baseValue = 6000.0
        let trend = Double(day) * 35
        
        return ForecastPoint(
            date: Calendar.current.date(byAdding: .day, value: day, to: Date())!,
            optimistic: baseValue + trend + 500,
            realistic: baseValue + trend,
            pessimistic: baseValue + trend - 500
        )
    }
    
    return ForecastChartView(
        historicalData: historicalData,
        forecastData: forecastData,
        targetValue: 10000,
        targetDate: Calendar.current.date(byAdding: .day, value: 90, to: Date())!,
        currency: "USD"
    )
    .padding()
}
