//
//  GoalRowViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//
//  Purpose: Centralized business logic for goal row display across all platforms
//  This ViewModel eliminates duplication between iOS and macOS goal display components

import Foundation
import SwiftUI
import Combine

/// ViewModel for unified goal row display across all platforms
@MainActor
class GoalRowViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var asyncProgress: Double = 0
    @Published var asyncCurrentTotal: Double = 0
    @Published var displayEmoji: String?
    @Published var progressAnimation: Double = 0
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    @Published var shimmerOffset: Double = -0.5
    @Published var hasLoadedInitialData = false
    
    // MARK: - Properties
    let goal: Goal
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(goal: Goal) {
        self.goal = goal
        self.displayEmoji = goal.emoji
        
        // Start shimmer animation
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.5
        }
        
        // Listen for refresh notifications
        NotificationCenter.default.publisher(for: .goalProgressRefreshed)
            .sink { [weak self] notification in
                guard let self = self else { return }
                // If this is a global refresh or specific to this goal, refresh data
                if notification.object == nil || (notification.object as? Goal)?.id == self.goal.id {
                    Task {
                        await self.refreshData()
                    }
                }
            }
            .store(in: &cancellables)

        // Refresh when goal data changes (e.g., allocations updated)
        NotificationCenter.default.publisher(for: .goalUpdated)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if notification.object == nil || (notification.object as? Goal)?.id == self.goal.id {
                    Task {
                        await self.refreshData()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Computed Properties
    
    /// Status badge information based on progress
    var statusBadge: (text: String, color: Color, icon: String) {
        let progress = asyncProgress
        if progress >= 1.0 {
            return ("Achieved", AccessibleColors.success, "checkmark.circle.fill")
        } else if progress >= 0.75 {
            return ("On Track", AccessibleColors.success, "circle.fill")
        } else if goal.daysRemaining < 30 {
            return ("Behind", AccessibleColors.error, "exclamationmark.circle.fill")
        } else {
            return ("In Progress", AccessibleColors.warning, "clock.fill")
        }
    }
    
    /// Progress bar color based on progress percentage
    var progressBarColor: Color {
        let progress = asyncProgress
        if progress >= 0.75 {
            return AccessibleColors.success
        } else if progress >= 0.5 {
            return AccessibleColors.warning
        } else {
            return AccessibleColors.error
        }
    }
    
    /// Formatted progress percentage text
    var progressPercentageText: String {
        "\(Int(asyncProgress * 100))% complete"
    }
    
    /// Formatted current/target amount text
    var amountText: String {
        "\(String(format: "%.0f", asyncCurrentTotal)) / \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)"
    }
    
    /// Days remaining text with urgency
    var daysRemainingText: String {
        "\(goal.daysRemaining) days left"
    }
    
    /// Whether days remaining should show urgency
    var isUrgent: Bool {
        goal.daysRemaining < 30
    }
    
    // MARK: - Public Methods
    
    /// Load currency-converted progress data asynchronously
    func loadAsyncProgress() async {
        // Prevent duplicate initial loads
        guard !isLoading else { return }
        
        isLoading = true
        hasError = false
        
        // Use the proper service that does currency conversion
        let newProgress = await GoalCalculationService.getProgress(for: goal)
        let newTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        
        await MainActor.run {
            // Update emoji if it changed
            if displayEmoji != goal.emoji {
                displayEmoji = goal.emoji
            }
            
            // Only update if values actually changed to prevent unnecessary animations
            let progressChanged = abs(asyncProgress - newProgress) > 0.01
            let totalChanged = abs(asyncCurrentTotal - newTotal) > 0.01
            
            if progressChanged || totalChanged || !hasLoadedInitialData {
                asyncProgress = newProgress
                asyncCurrentTotal = newTotal
                
                withAnimation(.easeOut(duration: 0.8)) {
                    progressAnimation = newProgress
                }
                
                hasLoadedInitialData = true
            }
            
            isLoading = false
        }
    }
    
    /// Refresh all data
    func refreshData() async {
        await loadAsyncProgress()
    }
    
    /// Format currency amount for display
    func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) \(currency)"
    }
}

// MARK: - Style Configuration

/// Style configuration for UnifiedGoalRowView
enum GoalRowStyle {
    case compact      // macOS sidebar style - minimal info
    case detailed     // iOS list style - full information
    case minimal      // Future: widgets, overview screens
    case card         // Future: card-based layouts
    
    var showsDescription: Bool {
        switch self {
        case .detailed, .card:
            return true
        case .compact, .minimal:
            return false
        }
    }
    
    var showsStatusBadge: Bool {
        switch self {
        case .detailed, .card:
            return true
        case .compact, .minimal:
            return false
        }
    }
    
    var progressBarHeight: CGFloat {
        switch self {
        case .detailed, .card:
            return 4
        case .compact:
            return 3
        case .minimal:
            return 2
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
        case .detailed, .card:
            return 12
        case .compact:
            return 2
        case .minimal:
            return 4
        }
    }
    
    var emojiSize: Font {
        switch self {
        case .detailed, .card:
            return .title2
        case .compact:
            return .title3
        case .minimal:
            return .caption
        }
    }
}
