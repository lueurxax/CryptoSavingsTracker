//
//  SparklineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// Compact sparkline chart for dashboard overview
struct SparklineChartView: View {
    let dataPoints: [BalanceHistoryPoint]
    let height: CGFloat
    let showGradient: Bool
    
    @State private var animationProgress: Double = 0
    @State private var hoveredPoint: BalanceHistoryPoint?
    
    init(
        dataPoints: [BalanceHistoryPoint],
        height: CGFloat = 40,
        showGradient: Bool = true
    ) {
        self.dataPoints = dataPoints
        self.height = height
        self.showGradient = showGradient
    }
    
    private var sortedPoints: [BalanceHistoryPoint] {
        dataPoints.sorted { $0.date < $1.date }
    }
    
    private var minValue: Double {
        sortedPoints.map { $0.balance }.min() ?? 0
    }
    
    private var maxValue: Double {
        sortedPoints.map { $0.balance }.max() ?? 100
    }
    
    private var valueRange: Double {
        maxValue - minValue
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !sortedPoints.isEmpty && valueRange > 0 {
                    let points = chartPoints(in: geometry.size)
                    
                    // Gradient area fill
                    if showGradient {
                        gradientArea(points: points, size: geometry.size)
                    }
                    
                    // Main sparkline
                    sparkline(points: points)
                    
                    // Interactive overlay for desktop
                    #if os(macOS)
                    interactiveOverlay(points: points, size: geometry.size)
                    #endif
                }
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).delay(0.2)) {
                animationProgress = 1.0
            }
        }
        .onChange(of: dataPoints.count) { oldValue, newValue in
            // Animate when new data points are added
            withAnimation(.easeInOut(duration: 0.8)) {
                animationProgress = 1.0
            }
        }
    }
    
    @ViewBuilder
    private func gradientArea(points: [CGPoint], size: CGSize) -> some View {
        Path { path in
            guard let firstPoint = points.first else { return }
            
            // Start from bottom-left
            path.move(to: CGPoint(x: firstPoint.x, y: size.height))
            path.addLine(to: firstPoint)
            
            // Add all points
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            
            // Close to bottom-right
            if let lastPoint = points.last {
                path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
            }
            
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [
                    AccessibleColors.chartColor(at: 0).opacity(0.3),
                    AccessibleColors.chartColor(at: 0).opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }
    
    @ViewBuilder
    private func sparkline(points: [CGPoint]) -> some View {
        Path { path in
            guard let firstPoint = points.first else { return }
            
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .trim(from: 0, to: animationProgress)
        .stroke(
            LinearGradient(
                colors: [
                    AccessibleColors.chartColor(at: 0),
                    AccessibleColors.chartColor(at: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }
    
    @ViewBuilder
    private func interactiveOverlay(points: [CGPoint], size: CGSize) -> some View {
        ForEach(Array(zip(points.indices, points)), id: \.0) { index, point in
            let dataPoint = sortedPoints[index]
            
            Circle()
                .fill(Color.clear)
                .frame(width: 16, height: 16)
                .position(point)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        hoveredPoint = dataPoint
                    case .ended:
                        hoveredPoint = nil
                    }
                }
        }
        
        // Hover indicator
        if let hoveredPoint = hoveredPoint,
           let pointIndex = sortedPoints.firstIndex(where: { $0.id == hoveredPoint.id }),
           pointIndex < points.count {
            let point = points[pointIndex]
            
            VStack {
                Circle()
                    .fill(AccessibleColors.chartColor(at: 0))
                    .frame(width: 6, height: 6)
                    .shadow(color: AccessibleColors.chartColor(at: 0).opacity(0.5), radius: 2)
                
                // Mini tooltip
                Text(String(format: "%.0f", hoveredPoint.balance))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(AccessibleColors.chartColor(at: 0))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.regularMaterial)
                    .cornerRadius(4)
                    .shadow(radius: 2)
            }
            .position(x: point.x, y: max(point.y - 20, 15))
        }
    }
    
    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !sortedPoints.isEmpty, valueRange > 0 else { return [] }
        
        return sortedPoints.enumerated().map { index, point in
            let x = size.width * CGFloat(index) / CGFloat(max(sortedPoints.count - 1, 1))
            let normalizedValue = (point.balance - minValue) / valueRange
            let y = size.height * (1.0 - normalizedValue)
            
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Animated Progress Ring for Goals Cards
struct AnimatedProgressRingView: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat
    
    @State private var animatedProgress: Double = 0
    
    init(progress: Double, lineWidth: CGFloat = 4, size: CGFloat = 32) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(
                    AccessibleColors.chartColor(at: 0).opacity(0.2),
                    lineWidth: lineWidth
                )
            
            // Progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            AccessibleColors.chartColor(at: 0),
                            AccessibleColors.chartColor(at: 1)
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            // Progress percentage
            Text("\(Int(progress * 100))%")
                .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        // Sample data for sparkline
        let sampleData = (0..<20).map { day in
            BalanceHistoryPoint(
                date: Calendar.current.date(byAdding: .day, value: day, to: Date().addingTimeInterval(-86400 * 20))!,
                balance: 1000 + Double(day * 50 + Int.random(in: -100...200)),
                currency: "USD"
            )
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance History")
                .font(.headline)
            
            SparklineChartView(
                dataPoints: sampleData,
                height: 60,
                showGradient: true
            )
            
            Text("+$234.56 (12.3%)")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        
        // Animated progress ring examples
        HStack(spacing: 20) {
            VStack {
                AnimatedProgressRingView(progress: 0.65)
                Text("Goal 1")
                    .font(.caption)
            }
            
            VStack {
                AnimatedProgressRingView(progress: 0.23)
                Text("Goal 2")
                    .font(.caption)
            }
            
            VStack {
                AnimatedProgressRingView(progress: 0.89)
                Text("Goal 3")
                    .font(.caption)
            }
        }
    }
    .padding()
}