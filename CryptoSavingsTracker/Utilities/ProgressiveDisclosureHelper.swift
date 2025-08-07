//
//  ProgressiveDisclosureHelper.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData

/// Helper for progressive disclosure of features based on user experience and data
struct ProgressiveDisclosureHelper {
    let modelContext: ModelContext?
    let onboardingManager: OnboardingManager
    
    init(modelContext: ModelContext? = nil, onboardingManager: OnboardingManager = OnboardingManager.shared) {
        self.modelContext = modelContext
        self.onboardingManager = onboardingManager
    }
    
    // MARK: - Feature Visibility
    
    /// Should show advanced chart types (heatmap, forecast, etc.)
    var shouldShowAdvancedCharts: Bool {
        return onboardingManager.shouldShowAdvancedFeatures() && hasTransactionData
    }
    
    /// Should show detailed analytics and metrics
    var shouldShowDetailedAnalytics: Bool {
        return onboardingManager.shouldShowAdvancedFeatures() || hasMultipleGoals
    }
    
    /// Should show bulk operations and advanced management
    var shouldShowAdvancedManagement: Bool {
        return onboardingManager.shouldShowAdvancedFeatures() && hasMultipleAssets
    }
    
    /// Should show forecasting and prediction features
    var shouldShowForecastFeatures: Bool {
        return onboardingManager.shouldShowAdvancedFeatures() && hasSignificantHistory
    }
    
    /// Should show portfolio comparison and benchmarking
    var shouldShowBenchmarking: Bool {
        return onboardingManager.shouldShowAdvancedFeatures() && hasMultipleGoals
    }
    
    // MARK: - Data State Checks
    
    private var hasTransactionData: Bool {
        guard let context = modelContext else { return false }
        let request = FetchDescriptor<Transaction>()
        return (try? context.fetchCount(request)) ?? 0 > 0
    }
    
    private var hasMultipleGoals: Bool {
        guard let context = modelContext else { return false }
        let request = FetchDescriptor<Goal>()
        return (try? context.fetchCount(request)) ?? 0 > 1
    }
    
    private var hasMultipleAssets: Bool {
        guard let context = modelContext else { return false }
        let request = FetchDescriptor<Asset>()
        return (try? context.fetchCount(request)) ?? 0 > 2
    }
    
    private var hasSignificantHistory: Bool {
        guard let context = modelContext else { return false }
        let request = FetchDescriptor<Transaction>()
        let count = (try? context.fetchCount(request)) ?? 0
        return count > 5 // Need at least 5 transactions for meaningful predictions
    }
    
    // MARK: - UI Helpers
    
    /// Get appropriate widget set for dashboard based on user level
    func getDashboardWidgets() -> [DashboardWidget] {
        var widgets: [DashboardWidget] = [
            DashboardWidget(type: .summary, size: .full, position: 0),
            DashboardWidget(type: .progressRing, size: .medium, position: 1)
        ]
        
        if shouldShowAdvancedCharts {
            widgets.append(DashboardWidget(type: .lineChart, size: .large, position: 2))
            
            if hasMultipleAssets {
                widgets.append(DashboardWidget(type: .stackedBar, size: .medium, position: 3))
            }
            
            if shouldShowForecastFeatures {
                widgets.append(DashboardWidget(type: .forecast, size: .large, position: 4))
            }
            
            widgets.append(DashboardWidget(type: .heatmap, size: .full, position: 5))
        }
        
        return widgets
    }
    
    /// Get simplified navigation items for new users
    func getNavigationItems() -> [NavigationItem] {
        var items: [NavigationItem] = [
            NavigationItem(title: "Goals", icon: "target", isCore: true),
            NavigationItem(title: "Dashboard", icon: "chart.bar.fill", isCore: true)
        ]
        
        if shouldShowAdvancedManagement {
            items.append(NavigationItem(title: "Portfolio", icon: "folder.fill", isCore: false))
        }
        
        if shouldShowDetailedAnalytics {
            items.append(NavigationItem(title: "Analytics", icon: "chart.line.uptrend.xyaxis", isCore: false))
        }
        
        return items
    }
}

// MARK: - Supporting Types
struct NavigationItem {
    let title: String
    let icon: String
    let isCore: Bool
}

// Use existing DashboardWidget from ChartDataModels.swift

// Use existing DashboardWidgetType from ChartDataModels.swift

// MARK: - SwiftUI View Modifiers for Progressive Disclosure

extension View {
    /// Show view only if user should see advanced features
    func showForAdvancedUsers(helper: ProgressiveDisclosureHelper) -> some View {
        self.opacity(helper.shouldShowAdvancedCharts ? 1 : 0)
            .disabled(!helper.shouldShowAdvancedCharts)
    }
    
    /// Show view only if user has sufficient data
    func showWithData(helper: ProgressiveDisclosureHelper) -> some View {
        self.opacity(helper.shouldShowDetailedAnalytics ? 1 : 0)
            .disabled(!helper.shouldShowDetailedAnalytics)
    }
    
    /// Gradually reveal view as user progresses
    func progressiveReveal(helper: ProgressiveDisclosureHelper, threshold: ProgressiveThreshold) -> some View {
        let shouldShow: Bool
        
        switch threshold {
        case .hasTransactions:
            shouldShow = helper.onboardingManager.hasTransactionData()
        case .hasMultipleGoals:
            shouldShow = helper.shouldShowDetailedAnalytics
        case .isAdvancedUser:
            shouldShow = helper.shouldShowAdvancedCharts
        case .hasSignificantHistory:
            shouldShow = helper.shouldShowForecastFeatures
        }
        
        return self
            .opacity(shouldShow ? 1 : 0.3)
            .disabled(!shouldShow)
            .animation(.easeInOut(duration: 0.3), value: shouldShow)
    }
}

enum ProgressiveThreshold {
    case hasTransactions
    case hasMultipleGoals
    case isAdvancedUser
    case hasSignificantHistory
}