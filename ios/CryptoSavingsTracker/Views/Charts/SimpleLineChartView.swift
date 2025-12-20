//
//  SimpleLineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// MARK: - Safe Array Access Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Simple line chart implementation without Charts framework dependency
struct SimpleLineChartView: View {
    let dataPoints: [BalanceHistoryPoint]
    let height: CGFloat
    let showAxes: Bool
    let showGradient: Bool
    
    @State private var animationProgress: Double = 0
    
    init(
        dataPoints: [BalanceHistoryPoint],
        height: CGFloat = 200,
        showAxes: Bool = true,
        showGradient: Bool = true
    ) {
        self.dataPoints = dataPoints
        self.height = height
        self.showAxes = showAxes
        self.showGradient = showGradient
    }
    
    private var minValue: Double {
        dataPoints.map { $0.balance }.min() ?? 0
    }
    
    private var maxValue: Double {
        dataPoints.map { $0.balance }.max() ?? 100
    }
    
    private var valueRange: Double {
        maxValue - minValue
    }
    
    private var accessibilityDescription: String {
        let trend: String
        if let first = dataPoints.first, let last = dataPoints.last, dataPoints.count > 1 {
            trend = last.balance > first.balance ? "increasing" : "decreasing"
        } else {
            trend = "stable"
        }
        let latest = dataPoints.last?.balance ?? 0
        let currency = dataPoints.first?.currency ?? "USD"
        return "Chart showing \(trend) balance over time. Current value: \(String(format: "%.2f", latest)) \(currency). Range: \(String(format: "%.2f", minValue)) to \(String(format: "%.2f", maxValue))"
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - (showAxes ? 60 : 0) // Account for Y-axis labels
            let chartHeight = height
            let chartOffsetX: CGFloat = showAxes ? 60 : 0
            
            ZStack {
                // Background
                if showAxes {
                    // Grid lines
                    Path { path in
                        let steps = 5
                        for i in 0...steps {
                            let y = chartHeight * Double(i) / Double(steps)
                            path.move(to: CGPoint(x: chartOffsetX, y: y))
                            path.addLine(to: CGPoint(x: chartOffsetX + width, y: y))
                        }
                    }
                    .stroke(AccessibleColors.tertiaryText.opacity(0.4), lineWidth: 0.5)
                }
                
                if !dataPoints.isEmpty {
                    // Area gradient (if enabled)
                    if showGradient {
                        Path { path in
                            let points = chartPoints(in: CGSize(width: width, height: chartHeight))
                            
                            if let firstPoint = points.first {
                                path.move(to: CGPoint(x: firstPoint.x + chartOffsetX, y: chartHeight))
                                path.addLine(to: CGPoint(x: firstPoint.x + chartOffsetX, y: firstPoint.y))
                                
                                for point in points.dropFirst() {
                                    let animatedY = chartHeight - (chartHeight - point.y) * animationProgress
                                    path.addLine(to: CGPoint(x: point.x + chartOffsetX, y: animatedY))
                                }
                                
                                if let lastPoint = points.last {
                                    path.addLine(to: CGPoint(x: lastPoint.x + chartOffsetX, y: chartHeight))
                                }
                                path.closeSubpath()
                            }
                        }
                        .fill(
                            LinearGradient(
                                colors: [AccessibleColors.chartColor(at: 0).opacity(0.3), AccessibleColors.chartColor(at: 0).opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Line path
                    Path { path in
                        let points = chartPoints(in: CGSize(width: width, height: chartHeight))
                        
                        if let firstPoint = points.first {
                            path.move(to: CGPoint(x: firstPoint.x + chartOffsetX, y: firstPoint.y))
                            
                            for point in points.dropFirst() {
                                let animatedY = chartHeight - (chartHeight - point.y) * animationProgress
                                path.addLine(to: CGPoint(x: point.x + chartOffsetX, y: animatedY))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [AccessibleColors.chartColor(at: 0), AccessibleColors.chartColor(at: 3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Data points with hover tooltips for desktop
                    ForEach(Array(chartPoints(in: CGSize(width: width, height: chartHeight)).enumerated()), id: \.offset) { index, point in
                        let animatedY = chartHeight - (chartHeight - point.y) * animationProgress
                        let dataPoint = dataPoints[safe: index]
                        
                        #if os(macOS)
                        if let data = dataPoint {
                            let hoverData = ChartPointHover(
                                index: index,
                                value: data.balance,
                                date: data.date,
                                currency: data.currency,
                                label: "Balance",
                                additionalInfo: nil
                            )
                            
                            HoverTooltipView(
                                title: hoverData.title,
                                value: hoverData.formattedValue,
                                description: hoverData.description
                            ) {
                                ZStack {
                                    // Hover area
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 16, height: 16)
                                    
                                    // Visible point
                                    Circle()
                                        .fill(AccessibleColors.chartColor(at: 0))
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .position(x: point.x + chartOffsetX, y: animatedY)
                        } else {
                            Circle()
                                .fill(AccessibleColors.chartColor(at: 0))
                                .frame(width: 4, height: 4)
                                .position(x: point.x + chartOffsetX, y: animatedY)
                        }
                        #else
                        Circle()
                            .fill(AccessibleColors.chartColor(at: 0))
                            .frame(width: 4, height: 4)
                            .position(x: point.x + chartOffsetX, y: animatedY)
                        #endif
                    }
                }
                
                // Axes labels (if enabled)
                if showAxes && !dataPoints.isEmpty {
                    // Y-axis title and currency
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Text("(\(dataPoints.first?.currency ?? "USD"))")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Spacer()
                    }
                    .frame(width: 50, alignment: .leading)
                    .position(x: 25, y: 15)
                    
                    // Y-axis values
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", maxValue))
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Spacer()
                        Text(String(format: "%.0f", minValue + valueRange/2))
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Spacer()
                        Text(String(format: "%.0f", minValue))
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                    }
                    .frame(width: 50)
                    .position(x: 50, y: chartHeight/2)
                    
                    // X-axis labels  
                    HStack {
                        if let first = dataPoints.first {
                            Text(first.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                        Spacer()
                        Text("Date")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                        Spacer()
                        if let last = dataPoints.last {
                            Text(last.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .position(x: chartOffsetX + width/2, y: chartHeight + 15)
                }
            }
        }
        .frame(height: height + (showAxes ? 30 : 0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Line Chart")
        .accessibilityValue(accessibilityDescription)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                animationProgress = 1.0
            }
        }
    }
    
    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !dataPoints.isEmpty, valueRange > 0 else { return [] }
        
        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        
        return sortedPoints.enumerated().map { index, point in
            let x = size.width * Double(index) / Double(max(sortedPoints.count - 1, 1))
            let normalizedValue = (point.balance - minValue) / valueRange
            let y = size.height * (1.0 - normalizedValue)
            
            return CGPoint(x: x, y: y)
        }
    }
}

// CompactLineChartView is defined in LineChartView.swift

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