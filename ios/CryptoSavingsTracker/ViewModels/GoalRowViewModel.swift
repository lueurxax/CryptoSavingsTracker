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
    
    /// Status badge information - only shows for exceptional states
    /// Returns nil for normal "in progress" goals to reduce visual noise
    var statusBadge: (text: String, color: Color, icon: String)? {
        let progress = asyncProgress
        if progress >= 1.0 {
            return ("Achieved", AccessibleColors.success, "checkmark.circle.fill")
        } else if progress >= 0.75 {
            return ("Almost There", AccessibleColors.success, "star.fill")
        } else if goal.daysRemaining < 30 && progress < 0.9 {
            return ("Urgent", AccessibleColors.error, "exclamationmark.triangle.fill")
        } else if goal.daysRemaining < 60 && progress < 0.5 {
            return ("Behind", AccessibleColors.warning, "exclamationmark.circle.fill")
        }
        // Return nil for normal progress - no badge needed
        return nil
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
    
    /// Formatted current/target amount text with proper currency symbols
    var amountText: String {
        let currentFormatted = formatAmount(asyncCurrentTotal, currency: goal.currency)
        let targetFormatted = formatAmount(goal.targetAmount, currency: goal.currency)
        return "\(currentFormatted) / \(targetFormatted)"
    }

    /// Time remaining in human-readable format (days, months, or years)
    var timeRemainingText: String {
        let days = goal.daysRemaining
        if days < 0 {
            return "Overdue"
        } else if days == 0 {
            return "Due today"
        } else if days == 1 {
            return "1 day left"
        } else if days < 14 {
            return "\(days) days left"
        } else if days < 60 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") left"
        } else if days < 365 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s") left"
        } else {
            let years = Double(days) / 365.0
            if years < 2 {
                let months = days / 30
                return "\(months) months left"
            } else {
                return String(format: "%.1f years left", years)
            }
        }
    }

    /// Legacy property for compatibility - prefer timeRemainingText
    var daysRemainingText: String {
        timeRemainingText
    }

    /// Whether time remaining should show urgency
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
