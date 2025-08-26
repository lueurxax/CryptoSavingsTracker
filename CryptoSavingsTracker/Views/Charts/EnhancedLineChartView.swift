//
//  EnhancedLineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// Enhanced line chart with better axis labeling, grid lines, and hover tooltips
struct EnhancedLineChartView: View, InteractiveChart {
    let dataPoints: [BalanceHistoryPoint]
    let targetValue: Double
    let currency: String
    let height: CGFloat
    
    @State var selectedPoint: BalanceHistoryPoint?
    @State var hoveredPoint: BalanceHistoryPoint?
    @State private var hoverLocation: CGPoint = .zero
    @State private var showingPointDetails = false
    @State private var isDragging: Bool = false
    
    init(
        dataPoints: [BalanceHistoryPoint],
        targetValue: Double,
        currency: String,
        height: CGFloat = 200
    ) {
        self.dataPoints = dataPoints
        self.targetValue = targetValue
        self.currency = currency
        self.height = height
    }
    
    private var sortedPoints: [BalanceHistoryPoint] {
        dataPoints.sorted { $0.date < $1.date }
    }
    
    private var minValue: Double {
        min(sortedPoints.map { $0.balance }.min() ?? 0, 0)
    }
    
    private var maxValue: Double {
        max(sortedPoints.map { $0.balance }.max() ?? targetValue, targetValue)
    }
    
    private var valueRange: Double {
        maxValue - minValue
    }
    
    private var chartPadding: CGFloat { 50 }
    
    var body: some View {
        GeometryReader { geometry in
            let chartWidth = geometry.size.width - chartPadding * 2
            let chartHeight = height - chartPadding
            
            ZStack {
                // Background
                Rectangle()
                    .fill(Color.gray.opacity(0.02))
                    .cornerRadius(8)
                
                // Grid lines and labels
                gridLinesAndLabels(chartWidth: chartWidth, chartHeight: chartHeight)
                
                if !sortedPoints.isEmpty {
                    // Target line
                    targetLine(chartWidth: chartWidth, chartHeight: chartHeight)
                    
                    // Data line with gradient
                    dataLine(chartWidth: chartWidth, chartHeight: chartHeight)
                    
                    // Data points with hover interaction
                    dataPointsWithHover(chartWidth: chartWidth, chartHeight: chartHeight)

                    // Crosshair + tooltip for active point (hovered or selected)
                    if let active = hoveredPoint ?? selectedPoint {
                        crosshairAndTooltip(for: active,
                                            chartWidth: chartWidth,
                                            chartHeight: chartHeight)
                    }
                }
                
                // Axis labels
                axisLabels(chartWidth: chartWidth, chartHeight: chartHeight)
            }
            // Drag interaction across the chart area (iOS/macOS)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !sortedPoints.isEmpty else { return }
                        let x = min(max(value.location.x, chartPadding), chartPadding + chartWidth)
                        let ratio = (x - chartPadding) / chartWidth
                        let idx = max(0, min(sortedPoints.count - 1, Int(round(ratio * CGFloat(sortedPoints.count - 1)))))
                        let active = sortedPoints[idx]
                        selectedPoint = active
                        isDragging = true
                        // Update hover location for tooltip positioning
                        let pts = chartPoints(chartWidth: chartWidth, chartHeight: chartHeight)
                        if idx < pts.count { hoverLocation = pts[idx] }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: height + 30) // Extra space for axis labels
    }
    
    @ViewBuilder
    private func gridLinesAndLabels(chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        // Horizontal grid lines (Y-axis)
        let majorYSteps = 5
        let minorYSteps = 10
        
        ForEach(0...minorYSteps, id: \.self) { step in
            let isMajor = step % (minorYSteps / majorYSteps) == 0
            let y = chartPadding + (chartHeight * CGFloat(step) / CGFloat(minorYSteps))
            let value = maxValue - (valueRange * Double(step) / Double(minorYSteps))
            
            HStack {
                // Y-axis value labels (only for major grid lines)
                if isMajor {
                    Text(formatAxisValue(value))
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                        .frame(width: 40, alignment: .trailing)
                } else {
                    Spacer()
                        .frame(width: 40)
                }
                
                // Grid line
                Path { path in
                    path.move(to: CGPoint(x: chartPadding, y: y))
                    path.addLine(to: CGPoint(x: chartPadding + chartWidth, y: y))
                }
                .stroke(
                    isMajor ? Color.gray.opacity(0.3) : Color.gray.opacity(0.15),
                    style: StrokeStyle(lineWidth: isMajor ? 1 : 0.5, dash: isMajor ? [] : [2, 2])
                )
                
                Spacer()
            }
        }
        
        // Vertical grid lines (X-axis) - major intervals only
        if sortedPoints.count > 1 {
            let majorXSteps = min(4, sortedPoints.count - 1)
            
            ForEach(0...majorXSteps, id: \.self) { step in
                let x = chartPadding + (chartWidth * CGFloat(step) / CGFloat(majorXSteps))
                let _ = Int(Double(sortedPoints.count - 1) * Double(step) / Double(majorXSteps))
                
                VStack {
                    Spacer()
                    
                    // Grid line
                    Path { path in
                        path.move(to: CGPoint(x: x, y: chartPadding))
                        path.addLine(to: CGPoint(x: x, y: chartPadding + chartHeight))
                    }
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
            }
        }
    }
    
    @ViewBuilder
    private func targetLine(chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        let targetY = chartPadding + chartHeight * (1 - (targetValue - minValue) / valueRange)
        
        ZStack {
            // Target line
            Path { path in
                path.move(to: CGPoint(x: chartPadding, y: targetY))
                path.addLine(to: CGPoint(x: chartPadding + chartWidth, y: targetY))
            }
            .stroke(
                AccessibleColors.success,
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            
            // Target label
            HStack {
                Spacer()
                Text("Target: \(String(format: "%.0f", targetValue)) \(currency)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(AccessibleColors.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AccessibleColors.success.opacity(0.1))
                    .cornerRadius(4)
            }
            .position(x: chartPadding + chartWidth - 80, y: targetY - 15)
        }
    }
    
    @ViewBuilder
    private func dataLine(chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        let points = chartPoints(chartWidth: chartWidth, chartHeight: chartHeight)
        
        // Area gradient
        Path { path in
            if let firstPoint = points.first {
                path.move(to: CGPoint(x: firstPoint.x, y: chartPadding + chartHeight))
                path.addLine(to: firstPoint)
                
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                
                if let lastPoint = points.last {
                    path.addLine(to: CGPoint(x: lastPoint.x, y: chartPadding + chartHeight))
                }
                path.closeSubpath()
            }
        }
        .fill(
            LinearGradient(
                colors: [AccessibleColors.chartColor(at: 0).opacity(0.2), AccessibleColors.chartColor(at: 0).opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        
        // Main line
        Path { path in
            if let firstPoint = points.first {
                path.move(to: firstPoint)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
        .stroke(
            LinearGradient(
                colors: [AccessibleColors.chartColor(at: 0), AccessibleColors.chartColor(at: 3)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }
    
    @ViewBuilder
    private func dataPointsWithHover(chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        let points = chartPoints(chartWidth: chartWidth, chartHeight: chartHeight)
        
        let hitSize: CGFloat = 44 // larger hit area for easier hover/select
        ForEach(Array(zip(points.indices, points)), id: \.0) { index, point in
            let dataPoint = sortedPoints[index]
            
            ZStack {
                // Larger invisible hover area
                Circle()
                    .fill(Color.clear)
                    .frame(width: hitSize, height: hitSize)
                    .chartInteraction(
                        point: dataPoint,
                        onInteraction: onInteraction
                    )
                
                // Visible data point
                Circle()
                    .fill(selectedPoint?.id == dataPoint.id ? AccessibleColors.primaryInteractive : AccessibleColors.chartColor(at: 0))
                    .frame(
                        width: selectedPoint?.id == dataPoint.id ? 10 : (hoveredPoint?.id == dataPoint.id ? 8 : 6),
                        height: selectedPoint?.id == dataPoint.id ? 10 : (hoveredPoint?.id == dataPoint.id ? 8 : 6)
                    )
                    .shadow(color: AccessibleColors.chartColor(at: 0).opacity(0.3), radius: 2)
                    .overlay(
                        Circle()
                            .stroke(
                                selectedPoint?.id == dataPoint.id ? Color.white : Color.clear,
                                lineWidth: 2
                            )
                    )
            }
            .position(point)
            .animation(.easeInOut(duration: 0.15), value: hoveredPoint?.id == dataPoint.id)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPoint?.id == dataPoint.id)
        }
    }
    
    @ViewBuilder
    private func hoverTooltip(for point: BalanceHistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date.formatted(.dateTime.month().day().year()))
                .font(.caption)
                .fontWeight(.medium)
            Text("\(String(format: "%.2f", point.balance)) \(currency)")
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(AccessibleColors.chartColor(at: 0))
            let progress = targetValue > 0 ? (point.balance / targetValue) * 100 : 0
            Text("\(String(format: "%.1f", progress))% of target")
                .font(.caption2)
                .foregroundColor(.accessibleSecondary)
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func crosshairAndTooltip(for point: BalanceHistoryPoint,
                                     chartWidth: CGFloat,
                                     chartHeight: CGFloat) -> some View {
        let points = chartPoints(chartWidth: chartWidth, chartHeight: chartHeight)
        if let idx = sortedPoints.firstIndex(where: { $0.id == point.id }), idx < points.count {
            let p = points[idx]
            // Vertical guide line
            Path { path in
                path.move(to: CGPoint(x: p.x, y: chartPadding))
                path.addLine(to: CGPoint(x: p.x, y: chartPadding + chartHeight))
            }
            .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            
            // Floating tooltip positioned near the point with clamping
            hoverTooltip(for: point)
                .position(
                    x: min(max(p.x, chartPadding + 70), chartPadding + chartWidth - 70),
                    y: max(p.y - 40, 30)
                )
                .zIndex(1000)
        }
    }
    
    @ViewBuilder
    private func axisLabels(chartWidth: CGFloat, chartHeight: CGFloat) -> some View {
        VStack {
            Spacer()
            
            HStack {
                // Y-axis label
                VStack {
                    Text("Amount")
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                        .rotationEffect(.degrees(-90))
                    Text("(\(currency))")
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20)
                
                VStack {
                    Spacer()
                    
                    // X-axis dates
                    // X-axis tick labels: show all if <= 8 points, else ~6 evenly spaced
                    HStack(spacing: 0) {
                        let count = sortedPoints.count
                        let indices: [Int] = {
                            if count <= 8 { return Array(0..<count) }
                            let slots = 6
                            return (0...slots).map { i in Int(round(Double(count - 1) * Double(i) / Double(slots))) }
                        }()
                        ForEach(indices, id: \.self) { i in
                            let dateText = sortedPoints[i].date.formatted(.dateTime.month(.abbreviated).day())
                            Text(dateText)
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                                .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : (i == indices.last ? .trailing : .center))
                        }
                    }
                    .padding(.horizontal, chartPadding)
                    .padding(.top, 8)
                
                    // X-axis label
                    Text("Date")
                        .font(.caption2)
                        .foregroundColor(.accessibleSecondary)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    private func chartPoints(chartWidth: CGFloat, chartHeight: CGFloat) -> [CGPoint] {
        guard !sortedPoints.isEmpty, valueRange > 0 else { return [] }
        
        return sortedPoints.enumerated().map { index, point in
            let x = chartPadding + (chartWidth * CGFloat(index) / CGFloat(max(sortedPoints.count - 1, 1)))
            let normalizedValue = (point.balance - minValue) / valueRange
            let y = chartPadding + chartHeight * (1.0 - normalizedValue)
            
            return CGPoint(x: x, y: y)
        }
    }
    
    private func formatAxisValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        } else if value >= 100 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    // MARK: - InteractiveChart Implementation
    func onInteraction(_ event: ChartInteractionEvent) {
        switch event {
        case .tap(let point):
            if let balancePoint = point as? BalanceHistoryPoint {
                selectedPoint = selectedPoint?.id == balancePoint.id ? nil : balancePoint
                interactionFeedback(for: event)
            }
        case .longPress(let point):
            if let balancePoint = point as? BalanceHistoryPoint {
                selectedPoint = balancePoint
                showingPointDetails = true
                interactionFeedback(for: event)
            }
        case .hover(let point):
            if let balancePoint = point as? BalanceHistoryPoint {
                hoveredPoint = balancePoint
                // Update hover location for tooltip positioning
                // hoverLocation is dynamically computed in crosshairAndTooltip using geometry
            } else {
                hoveredPoint = nil
            }
        case .doubleTap(let point):
            if let balancePoint = point as? BalanceHistoryPoint {
                selectedPoint = balancePoint
                showingPointDetails = true
                interactionFeedback(for: event)
            }
        default:
            break
        }
    }
}

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
