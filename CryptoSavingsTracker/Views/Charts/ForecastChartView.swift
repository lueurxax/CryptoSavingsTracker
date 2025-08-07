//
//  ForecastChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct ForecastChartView: View {
    let historicalData: [BalanceHistoryPoint]
    let forecastData: [ForecastPoint]
    let targetValue: Double
    let targetDate: Date
    let currency: String
    let showConfidenceInterval: Bool
    let animateOnAppear: Bool
    
    @State private var selectedForecastType: ForecastType = .realistic
    
    init(
        historicalData: [BalanceHistoryPoint],
        forecastData: [ForecastPoint],
        targetValue: Double,
        targetDate: Date,
        currency: String,
        showConfidenceInterval: Bool = true,
        animateOnAppear: Bool = true
    ) {
        self.historicalData = historicalData
        self.forecastData = forecastData
        self.targetValue = targetValue
        self.targetDate = targetDate
        self.currency = currency
        self.showConfidenceInterval = showConfidenceInterval
        self.animateOnAppear = animateOnAppear
    }
    
    enum ForecastType: String, CaseIterable {
        case optimistic = "Optimistic"
        case realistic = "Realistic"
        case pessimistic = "Pessimistic"
        
        var color: Color {
            switch self {
            case .optimistic: return .green
            case .realistic: return .blue
            case .pessimistic: return .red
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Goal Forecast")
                        .font(.headline)
                    MetricTooltips.forecast
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target: \(String(format: "%.2f", targetValue)) \(currency)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Deadline: \(targetDate, format: .dateTime.day().month().year())")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                    }
                    
                    Spacer()
                    
                    // Forecast type selector
                    Picker("Forecast Type", selection: $selectedForecastType) {
                        ForEach(ForecastType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 240, minHeight: 44)
                }
            }
            
            // Simple forecast display using line chart for historical + selected forecast
            let combinedData = historicalData + forecastData.map { point in
                let selectedValue: Double
                switch selectedForecastType {
                case .optimistic: selectedValue = point.optimistic
                case .realistic: selectedValue = point.realistic
                case .pessimistic: selectedValue = point.pessimistic
                }
                
                return BalanceHistoryPoint(
                    date: point.date,
                    balance: selectedValue,
                    currency: currency
                )
            }
            
            SimpleLineChartView(
                dataPoints: combinedData,
                height: 300,
                showAxes: true,
                showGradient: true
            )
            
            // Target line indicator (visual overlay)
            HStack {
                Text("Target: \(String(format: "%.0f", targetValue)) \(currency)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(AccessibleColors.success)
                    .cornerRadius(4)
                Spacer()
            }
            
            // Forecast analysis
            VStack(alignment: .leading, spacing: 12) {
                Text("Forecast Analysis")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(ForecastType.allCases, id: \.self) { type in
                        VStack(spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(type.color)
                                    .frame(width: 8, height: 8)
                                Text(type.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            if let lastForecast = forecastData.last {
                                let value = getValue(for: type, from: lastForecast)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(String(format: "%.0f", value)) \(currency)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    let shortfall = max(0, targetValue - value)
                                    if shortfall > 0 {
                                        Text("Shortfall: \(String(format: "%.0f", shortfall))")
                                            .font(.caption2)
                                            .foregroundColor(AccessibleColors.error)
                                    } else {
                                        Text("Goal achieved!")
                                            .font(.caption2)
                                            .foregroundColor(AccessibleColors.success)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(type.color.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedForecastType == type ? type.color : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            
            // Required daily savings
            if let lastHistorical = historicalData.last {
                let currentValue = lastHistorical.balance
                let daysRemaining = max(1, Int(targetDate.timeIntervalSinceNow / 86400))
                let requiredDaily = max(0, (targetValue - currentValue) / Double(daysRemaining))
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Required Daily Savings")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                            MetricTooltips.requiredDaily
                        }
                        Text("\(String(format: "%.2f", requiredDaily)) \(currency)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Days Remaining")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                        Text("\(daysRemaining)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(daysRemaining < 30 ? AccessibleColors.warning : .primary)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.03))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func getValue(for type: ForecastType, from forecast: ForecastPoint) -> Double {
        switch type {
        case .optimistic: return forecast.optimistic
        case .realistic: return forecast.realistic
        case .pessimistic: return forecast.pessimistic
        }
    }
}

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