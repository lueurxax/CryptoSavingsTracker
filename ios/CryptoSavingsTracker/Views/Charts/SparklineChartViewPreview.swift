// Extracted preview-only declarations for NAV003 policy compliance.
// Source: SparklineChartView.swift

//
//  SparklineChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

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
