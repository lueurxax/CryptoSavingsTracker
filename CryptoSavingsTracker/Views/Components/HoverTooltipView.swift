//
//  HoverTooltipView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// MARK: - Hover Tooltip Component
struct HoverTooltipView<Content: View>: View {
    let content: Content
    let tooltipTitle: String
    let tooltipValue: String
    let tooltipDescription: String?
    
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    
    init(
        title: String,
        value: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tooltipTitle = title
        self.tooltipValue = value
        self.tooltipDescription = description
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = true
                        }
                    case .ended:
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = false
                        }
                    }
                }
            
            // Desktop-only tooltip
            #if os(macOS)
            if isHovering {
                tooltipContent
                    .position(
                        x: min(max(hoverLocation.x, 80), 400),
                        y: max(hoverLocation.y - 60, 30)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(1000)
            }
            #endif
        }
    }
    
    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tooltipTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(tooltipValue)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(AccessibleColors.chartColor(at: 0))
            
            if let description = tooltipDescription {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Chart Point Hover Data
struct ChartPointHover {
    let index: Int
    let value: Double
    let date: Date?
    let currency: String?
    let label: String?
    let additionalInfo: String?
    
    var formattedValue: String {
        if let currency = currency {
            return "\(String(format: "%.2f", value)) \(currency)"
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    var formattedDate: String {
        guard let date = date else { return "" }
        return date.formatted(.dateTime.month().day().year())
    }
    
    var title: String {
        return label ?? (date != nil ? "Balance" : "Value")
    }
    
    var description: String? {
        var parts: [String] = []
        
        if date != nil {
            parts.append(formattedDate)
        }
        
        if let info = additionalInfo {
            parts.append(info)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

// MARK: - Hover-enhanced Chart Components

extension SimpleLineChartView {
    func withHoverTooltips() -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let chartHeight = height
            let points = chartPoints(in: CGSize(width: width, height: chartHeight))
            
            ZStack {
                // Original chart content
                self
                
                // Invisible hover areas for each data point
                #if os(macOS)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let dataPoint = dataPoints[safe: index]
                    
                    if let data = dataPoint {
                        let hoverData = ChartPointHover(
                            index: index,
                            value: data.balance,
                            date: data.date,
                            currency: data.currency,
                            label: "Balance",
                            additionalInfo: nil
                        )
                        
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20, height: chartHeight)
                            .position(x: point.x, y: chartHeight / 2)
                            .overlay(
                                HoverTooltipView(
                                    title: hoverData.title,
                                    value: hoverData.formattedValue,
                                    description: hoverData.description
                                ) {
                                    Color.clear
                                }
                            )
                    }
                }
                #endif
            }
        }
        .frame(height: height + (showAxes ? 30 : 0))
    }
    
    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !dataPoints.isEmpty else { return [] }
        
        let minValue = dataPoints.map { $0.balance }.min() ?? 0
        let maxValue = dataPoints.map { $0.balance }.max() ?? 100
        let valueRange = maxValue - minValue
        
        guard valueRange > 0 else { return [] }
        
        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        
        return sortedPoints.enumerated().map { index, point in
            let x = size.width * Double(index) / Double(max(sortedPoints.count - 1, 1))
            let normalizedValue = (point.balance - minValue) / valueRange
            let y = size.height * (1.0 - normalizedValue)
            
            return CGPoint(x: x, y: y)
        }
    }
}

extension ProgressRingView {
    func withHoverTooltips() -> some View {
        HoverTooltipView(
            title: "Goal Progress",
            value: "\(Int(progress * 100))%",
            description: "Current: \(String(format: "%.2f", current)) \(currency) of \(String(format: "%.2f", target)) \(currency)"
        ) {
            self
        }
    }
}


// MARK: - Preview
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