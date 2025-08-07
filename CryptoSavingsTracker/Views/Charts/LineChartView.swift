//
//  LineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// Fallback implementation using SimpleLineChartView for broader compatibility
struct LineChartView: View {
    let dataPoints: [BalanceHistoryPoint]
    @State private var selectedTimeRange: ChartTimeRange
    let showGrid: Bool
    let showLegend: Bool
    let animateOnAppear: Bool
    
    init(
        dataPoints: [BalanceHistoryPoint],
        timeRange: ChartTimeRange = .month,
        showGrid: Bool = true,
        showLegend: Bool = true,
        animateOnAppear: Bool = true
    ) {
        self.dataPoints = dataPoints
        self._selectedTimeRange = State(initialValue: timeRange)
        self.showGrid = showGrid
        self.showLegend = showLegend
        self.animateOnAppear = animateOnAppear
    }
    
    private var filteredData: [BalanceHistoryPoint] {
        guard let startDate = selectedTimeRange.filterDate(from: Date()) else {
            return dataPoints
        }
        return dataPoints.filter { $0.date >= startDate }
    }
    
    private var currency: String {
        filteredData.first?.currency ?? "USD"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Balance History")
                            .font(.headline)
                        MetricTooltips.balanceHistory
                    }
                    
                    if let latest = filteredData.last {
                        Text("\(latest.balance, specifier: "%.2f") \(currency)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if filteredData.count > 1 {
                            let previous = filteredData[filteredData.count - 2].balance
                            let change = latest.balance - previous
                            let changePercent = previous > 0 ? (change / previous) * 100 : 0
                            
                            HStack(spacing: 4) {
                                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption)
                                Text("\(abs(change), specifier: "%.2f") (\(abs(changePercent), specifier: "%.1f")%)")
                                    .font(.caption)
                            }
                            .foregroundColor(change >= 0 ? .green : .red)
                        }
                    }
                }
                
                Spacer()
                
                // Time range selector
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(ChartTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 200, minHeight: 44)
            }
            
            // Chart using SimpleLineChartView
            SimpleLineChartView(
                dataPoints: filteredData,
                height: 250,
                showAxes: showGrid,
                showGradient: true
            )
            
            // Legend
            if showLegend && filteredData.count > 1 {
                HStack(spacing: 16) {
                    Label("Min: \(filteredData.map { $0.balance }.min() ?? 0, specifier: "%.2f")", systemImage: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    
                    Label("Max: \(filteredData.map { $0.balance }.max() ?? 0, specifier: "%.2f")", systemImage: "arrow.up.to.line")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    
                    Label("Avg: \(filteredData.map { $0.balance }.reduce(0, +) / Double(filteredData.count), specifier: "%.2f")", systemImage: "minus")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// Simplified line chart for compact views
struct CompactLineChartView: View {
    let dataPoints: [BalanceHistoryPoint]
    let height: CGFloat
    let showAxes: Bool
    
    init(
        dataPoints: [BalanceHistoryPoint],
        height: CGFloat = 100,
        showAxes: Bool = false
    ) {
        self.dataPoints = dataPoints
        self.height = height
        self.showAxes = showAxes
    }
    
    var body: some View {
        SimpleLineChartView(
            dataPoints: dataPoints,
            height: height,
            showAxes: showAxes,
            showGradient: false
        )
    }
}

#Preview("Line Chart") {
    let sampleData = (0..<30).map { day in
        BalanceHistoryPoint(
            date: Calendar.current.date(byAdding: .day, value: -30 + day, to: Date())!,
            balance: 5000 + Double.random(in: -500...1500) + (Double(day) * 50),
            currency: "USD"
        )
    }
    
    VStack(spacing: 20) {
        LineChartView(dataPoints: sampleData)
        
        CompactLineChartView(dataPoints: sampleData)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
    }
    .padding()
}