//
//  AllocationPieChart.swift
//  CryptoSavingsTracker
//

import SwiftUI
import Charts

struct AllocationPieChart: View {
    let allocations: [(goal: Goal, percentage: Double)]
    let unallocatedPercentage: Double
    
    // Define colors for up to 10 goals plus unallocated
    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .teal, .indigo, .mint, .cyan, .brown
    ]
    
    private var platformBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    private var chartData: [(label: String, value: Double, color: Color)] {
        var data: [(label: String, value: Double, color: Color)] = []
        
        // Add allocated goals
        for (index, item) in allocations.enumerated() where item.percentage > 0 {
            data.append((
                label: item.goal.name,
                value: item.percentage,
                color: colors[index % colors.count]
            ))
        }
        
        // Add unallocated portion if any
        if unallocatedPercentage > 0 {
            data.append((
                label: "Unallocated",
                value: unallocatedPercentage,
                color: .gray.opacity(0.5)
            ))
        }
        
        return data
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Pie Chart
            ZStack {
                if chartData.isEmpty {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Text("No allocations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                } else {
                    GeometryReader { geometry in
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let radius = min(geometry.size.width, geometry.size.height) / 2
                        
                        ZStack {
                            ForEach(Array(chartData.enumerated()), id: \.offset) { index, item in
                                PieSlice(
                                    startAngle: startAngle(for: index),
                                    endAngle: endAngle(for: index),
                                    color: item.color
                                )
                            }
                            
                            // Center hole for donut effect
                            Circle()
                                .fill(Color(platformBackgroundColor))
                                .frame(width: radius * 0.6, height: radius * 0.6)
                                .position(center)
                            
                            // Center text showing total
                            VStack(spacing: 2) {
                                Text("\(Int((1.0 - unallocatedPercentage) * 100))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("Allocated")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .position(center)
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding()
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chartData, id: \.label) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 12, height: 12)
                        
                        Text(item.label)
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(Int(item.value * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func startAngle(for index: Int) -> Angle {
        let precedingPercentages = chartData.prefix(index).map(\.value).reduce(0, +)
        return Angle(degrees: precedingPercentages * 360 - 90)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let includingPercentages = chartData.prefix(index + 1).map(\.value).reduce(0, +)
        return Angle(degrees: includingPercentages * 360 - 90)
    }
}

struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        
        return path
    }
    
    var body: some View {
        self.fill(color)
    }
}