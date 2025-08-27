//
//  ChartDataModels+ChartPoint.swift
//  CryptoSavingsTracker
//
//  Extensions to make chart data models conform to ChartPoint protocol
//

import Foundation

// MARK: - ChartPoint Conformances

extension BalanceHistoryPoint: ChartPoint {}

extension HeatmapDay: ChartPoint {
    // Value property already defined in the main struct
}