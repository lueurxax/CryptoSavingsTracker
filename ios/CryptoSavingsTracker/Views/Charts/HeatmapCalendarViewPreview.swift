// Extracted preview-only declarations for NAV003 policy compliance.
// Source: HeatmapCalendarView.swift

//
//  HeatmapCalendarView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

#Preview("Heatmap Calendar") {
    let sampleData = (0..<365).compactMap { dayOffset -> HeatmapDay? in
        guard let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
        
        let value = Double.random(in: 0...100)
        let intensity = value / 100.0
        let transactionCount = Int.random(in: 0...15) // Random transaction count for preview
        
        return HeatmapDay(date: date, value: value, intensity: intensity, transactionCount: transactionCount)
    }
    
    return VStack(spacing: 20) {
        HeatmapCalendarView(heatmapData: sampleData)
        
        HStack(spacing: 16) {
            CompactHeatmapView(heatmapData: sampleData, timeRange: 30, size: 120)
            CompactHeatmapView(heatmapData: sampleData, timeRange: 60, size: 180)
        }
    }
    .padding()
}
