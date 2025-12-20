//
//  DetailViewType.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation

/// Enum representing different detail view types available for goals
enum DetailViewType: CaseIterable {
    case details, dashboard
    
    var title: String {
        switch self {
        case .details: return "Details"
        case .dashboard: return "Dashboard"
        }
    }
    
    var icon: String {
        switch self {
        case .details: return "info.circle"
        case .dashboard: return "chart.bar.fill"
        }
    }
}