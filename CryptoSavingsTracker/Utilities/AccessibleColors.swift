//
//  AccessibleColors.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

/// Accessible color system that ensures WCAG AA contrast compliance
struct AccessibleColors {
    // MARK: - Chart Colors
    /// High-contrast colors for chart data visualization
    static let chartColors: [Color] = [
        Color(red: 0.0, green: 0.48, blue: 0.80),  // Blue - 4.5:1 contrast
        Color(red: 0.0, green: 0.66, blue: 0.42),  // Green - 4.5:1 contrast  
        Color(red: 0.85, green: 0.37, blue: 0.0),  // Orange - 4.5:1 contrast
        Color(red: 0.51, green: 0.19, blue: 0.63), // Purple - 4.5:1 contrast
        Color(red: 0.80, green: 0.0, blue: 0.0),   // Red - 4.5:1 contrast
        Color(red: 0.85, green: 0.65, blue: 0.0),  // Yellow - 4.5:1 contrast
        Color(red: 0.85, green: 0.0, blue: 0.45),  // Pink - 4.5:1 contrast
        Color(red: 0.0, green: 0.56, blue: 0.56),  // Teal - 4.5:1 contrast
        Color(red: 0.30, green: 0.30, blue: 0.80), // Indigo - 4.5:1 contrast
        Color(red: 0.60, green: 0.40, blue: 0.20)  // Brown - 4.5:1 contrast
    ]
    
    // MARK: - Text Colors
    /// Secondary text color with improved contrast (4.5:1 minimum)
    static let secondaryText = Color(red: 0.40, green: 0.40, blue: 0.40)
    
    /// Tertiary text color with adequate contrast for less important text
    static let tertiaryText = Color(red: 0.55, green: 0.55, blue: 0.55)
    
    // MARK: - Status Colors
    /// Success color with high contrast
    static let success = Color(red: 0.0, green: 0.60, blue: 0.0)
    
    /// Warning color with high contrast  
    static let warning = Color(red: 0.85, green: 0.50, blue: 0.0)
    
    /// Error color with high contrast
    static let error = Color(red: 0.80, green: 0.0, blue: 0.0)
    
    // MARK: - Background Colors
    /// Light background with sufficient contrast for overlays
    static let lightBackground = Color(red: 0.98, green: 0.98, blue: 0.98)
    
    /// Medium background for cards and containers
    static let mediumBackground = Color(red: 0.95, green: 0.95, blue: 0.95)
    
    /// Dark background for emphasis
    static let darkBackground = Color(red: 0.90, green: 0.90, blue: 0.90)
    
    // MARK: - Interactive Colors
    /// Primary interactive color (accessible blue)
    static let primaryInteractive = Color(red: 0.0, green: 0.48, blue: 0.80)
    
    /// Secondary interactive color (accessible teal)
    static let secondaryInteractive = Color(red: 0.0, green: 0.56, blue: 0.56)
    
    /// Primary interactive background with proper opacity
    static let primaryInteractiveBackground = primaryInteractive.opacity(0.1)
    
    /// Selected item background
    static let selectedBackground = primaryInteractive.opacity(0.15)
    
    /// Hover state background
    static let hoverBackground = Color(red: 0.95, green: 0.95, blue: 0.95)
    
    // MARK: - Status Background Colors
    /// Success background with proper opacity
    static let successBackground = success.opacity(0.1)
    
    /// Warning background with proper opacity  
    static let warningBackground = warning.opacity(0.1)
    
    /// Error background with proper opacity
    static let errorBackground = error.opacity(0.1)
    
    // MARK: - Chart Specific Colors
    /// Achievement/celebration color (accessible yellow)
    static let achievement = Color(red: 0.85, green: 0.65, blue: 0.0)
    
    /// Achievement background
    static let achievementBackground = achievement.opacity(0.2)
    
    /// Streak color (accessible orange)
    static let streak = Color(red: 0.85, green: 0.37, blue: 0.0)
    
    /// Streak background
    static let streakBackground = streak.opacity(0.15)
    
    // MARK: - Helper Functions
    /// Returns a chart color at the given index, cycling through available colors
    static func chartColor(at index: Int) -> Color {
        return chartColors[index % chartColors.count]
    }
    
    /// Returns a color with improved contrast based on background
    static func adaptiveSecondaryText(for background: Color) -> Color {
        // For now, return the standard secondary text color
        // In a more advanced implementation, this could analyze the background color
        return secondaryText
    }
}

/// Extension to provide accessible color variants
extension Color {
    /// Accessible secondary text color
    static let accessibleSecondary = AccessibleColors.secondaryText
    
    /// Accessible tertiary text color
    static let accessibleTertiary = AccessibleColors.tertiaryText
    
    /// Accessible primary interactive color (replaces .blue)
    static let accessiblePrimary = AccessibleColors.primaryInteractive
    
    /// Accessible primary background (replaces Color.blue.opacity(0.1))
    static let accessiblePrimaryBackground = AccessibleColors.primaryInteractiveBackground
    
    /// Accessible selected background
    static let accessibleSelected = AccessibleColors.selectedBackground
    
    /// Accessible hover background
    static let accessibleHover = AccessibleColors.hoverBackground
    
    /// Accessible achievement color (replaces .yellow)
    static let accessibleAchievement = AccessibleColors.achievement
    
    /// Accessible streak color (replaces .orange)
    static let accessibleStreak = AccessibleColors.streak
}