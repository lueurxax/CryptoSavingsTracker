//
//  ChartDataModels.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftUI

// MARK: - Balance History
struct BalanceHistoryPoint: Identifiable, ChartPoint {
    let id = UUID()
    let date: Date
    let balance: Double
    let currency: String
    
    // ChartPoint conformance
    var value: Double { balance }
    var displayValue: String { String(format: "%.2f", balance) }
    var accessibilityLabel: String {
        "Balance on \(date.formatted(.dateTime.month().day())): \(displayValue) \(currency)"
    }
}

// MARK: - Asset Composition
struct AssetComposition: Identifiable {
    let id = UUID()
    let currency: String
    let value: Double
    let percentage: Double
    let color: Color
}

// MARK: - Progress Data
struct ProgressData {
    let current: Double
    let target: Double
    let percentage: Double
    let daysRemaining: Int
    let averageDailyRequired: Double
    let projectedCompletion: Date?
    
    var progressColor: Color {
        switch percentage {
        case 0..<0.25:
            return .red
        case 0.25..<0.5:
            return .orange
        case 0.5..<0.75:
            return .yellow
        case 0.75..<1.0:
            return .green
        default:
            return .blue
        }
    }
}

// MARK: - Forecast Data
struct ForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let optimistic: Double
    let realistic: Double
    let pessimistic: Double
}

// MARK: - Heatmap Data
struct HeatmapDay: Identifiable, ChartPoint {
    let id = UUID()
    let date: Date
    let value: Double
    let intensity: Double // 0.0 to 1.0
    let transactionCount: Int // Number of transactions on this day
    
    // ChartPoint conformance
    var displayValue: String { "\(transactionCount) txns" }
    var accessibilityLabel: String {
        "\(date.formatted(.dateTime.month().day())): \(transactionCount) transactions, \(String(format: "%.1f", value)) volume"
    }
    
    var color: Color {
        if transactionCount == 0 {
            return AccessibleColors.lightBackground
        }
        
        // Use accessible colors based on transaction count with intensity scaling
        let baseColor: Color
        switch transactionCount {
        case 1:
            baseColor = AccessibleColors.chartColor(at: 0) // Blue
        case 2:
            baseColor = AccessibleColors.chartColor(at: 1) // Green  
        case 3:
            baseColor = AccessibleColors.chartColor(at: 2) // Orange
        case 4:
            baseColor = AccessibleColors.chartColor(at: 3) // Purple
        case 5...9:
            baseColor = AccessibleColors.chartColor(at: 4) // Red
        default: // 10+
            baseColor = AccessibleColors.achievement // High activity gold
        }
        
        // Scale opacity based on intensity (0.3 minimum for visibility, up to 1.0)
        return baseColor.opacity(0.3 + (intensity * 0.7))
    }
}

// MARK: - Dashboard Widget Types
enum DashboardWidgetType: String, CaseIterable {
    case progressRing = "Progress Ring"
    case lineChart = "Balance History"
    case stackedBar = "Asset Composition"
    case forecast = "Forecast"
    case heatmap = "Activity Heatmap"
    case summary = "Summary Stats"
    
    var icon: String {
        switch self {
        case .progressRing: return "chart.pie.fill"
        case .lineChart: return "chart.line.uptrend.xyaxis"
        case .stackedBar: return "chart.bar.fill"
        case .forecast: return "chart.line.uptrend.xyaxis.circle.fill"
        case .heatmap: return "square.grid.3x3.fill"
        case .summary: return "list.bullet.rectangle.fill"
        }
    }
}

// MARK: - Dashboard Widget Configuration
struct DashboardWidget: Identifiable {
    let id = UUID()
    let type: DashboardWidgetType
    var size: WidgetSize = .medium
    var position: Int
    
    enum WidgetSize {
        case small  // 1x1
        case medium // 2x1
        case large  // 2x2
        case full   // Full width
        
        var columns: Int {
            switch self {
            case .small: return 1
            case .medium: return 2
            case .large: return 2
            case .full: return 4
            }
        }
        
        var rows: Int {
            switch self {
            case .small: return 1
            case .medium: return 1
            case .large: return 2
            case .full: return 1
            }
        }
    }
}

// MARK: - Chart Time Range
enum ChartTimeRange: String, CaseIterable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"
    
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .all: return nil
        }
    }
    
    func filterDate(from endDate: Date) -> Date? {
        guard let days = days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: endDate)
    }
}