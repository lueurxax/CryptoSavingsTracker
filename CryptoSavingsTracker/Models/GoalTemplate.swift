//
//  GoalTemplate.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftUI

/// Pre-configured goal templates with smart defaults
struct GoalTemplate: Identifiable, Hashable {
    let id = UUID()
    let type: GoalType
    let name: String
    let description: String
    let icon: String
    let color: Color
    let defaultAmount: Double
    let defaultTimeframe: Int // days
    let recommendedAssets: [AssetRecommendation]
    let difficulty: TemplateDifficulty
    let tags: [String]
    
    var currency: String { "USD" } // Default currency
    
    static let allTemplates: [GoalTemplate] = [
        // Beginner-friendly templates
        GoalTemplate(
            type: .emergency,
            name: "Emergency Fund",
            description: "Build a safety net with stable cryptocurrencies for unexpected expenses",
            icon: "shield.fill",
            color: .blue,
            defaultAmount: 5000,
            defaultTimeframe: 365, // 1 year
            recommendedAssets: [
                AssetRecommendation(currency: "BTC", allocation: 0.4, reasoning: "Store of value"),
                AssetRecommendation(currency: "ETH", allocation: 0.3, reasoning: "Established ecosystem"),
                AssetRecommendation(currency: "USDC", allocation: 0.3, reasoning: "Stable value")
            ],
            difficulty: .beginner,
            tags: ["stable", "conservative", "beginner-friendly"]
        ),
        
        GoalTemplate(
            type: .investment,
            name: "DeFi Portfolio", 
            description: "Diversified investment across major DeFi protocols and tokens",
            icon: "chart.line.uptrend.xyaxis",
            color: .green,
            defaultAmount: 10000,
            defaultTimeframe: 730, // 2 years
            recommendedAssets: [
                AssetRecommendation(currency: "ETH", allocation: 0.4, reasoning: "DeFi backbone"),
                AssetRecommendation(currency: "BTC", allocation: 0.2, reasoning: "Portfolio anchor"),
                AssetRecommendation(currency: "MATIC", allocation: 0.2, reasoning: "Low-cost DeFi"),
                AssetRecommendation(currency: "AVAX", allocation: 0.2, reasoning: "Fast ecosystem")
            ],
            difficulty: .intermediate,
            tags: ["defi", "growth", "diversified"]
        ),
        
        GoalTemplate(
            type: .retirement,
            name: "Crypto Retirement",
            description: "Long-term wealth building with established cryptocurrencies",
            icon: "house.fill",
            color: .orange,
            defaultAmount: 50000,
            defaultTimeframe: 3650, // 10 years
            recommendedAssets: [
                AssetRecommendation(currency: "BTC", allocation: 0.5, reasoning: "Digital gold"),
                AssetRecommendation(currency: "ETH", allocation: 0.3, reasoning: "Smart contracts"),
                AssetRecommendation(currency: "SOL", allocation: 0.1, reasoning: "High performance"),
                AssetRecommendation(currency: "ADA", allocation: 0.1, reasoning: "Sustainable blockchain")
            ],
            difficulty: .intermediate,
            tags: ["long-term", "retirement", "wealth-building"]
        ),
        
        // Specific use cases
        GoalTemplate(
            type: .travel,
            name: "World Travel Fund",
            description: "Save for your dream vacation with globally accepted cryptocurrencies",
            icon: "airplane",
            color: .purple,
            defaultAmount: 8000,
            defaultTimeframe: 545, // 18 months
            recommendedAssets: [
                AssetRecommendation(currency: "BTC", allocation: 0.5, reasoning: "Global acceptance"),
                AssetRecommendation(currency: "USDC", allocation: 0.3, reasoning: "Stable spending"),
                AssetRecommendation(currency: "ETH", allocation: 0.2, reasoning: "Wide adoption")
            ],
            difficulty: .beginner,
            tags: ["travel", "practical", "spending"]
        ),
        
        GoalTemplate(
            type: .purchase,
            name: "Down Payment",
            description: "Save for a major purchase like a house or car with steady growth",
            icon: "house.circle.fill",
            color: .red,
            defaultAmount: 25000,
            defaultTimeframe: 1095, // 3 years
            recommendedAssets: [
                AssetRecommendation(currency: "BTC", allocation: 0.4, reasoning: "Long-term appreciation"),
                AssetRecommendation(currency: "ETH", allocation: 0.3, reasoning: "Steady growth"),
                AssetRecommendation(currency: "USDC", allocation: 0.3, reasoning: "Capital preservation")
            ],
            difficulty: .beginner,
            tags: ["purchase", "real-estate", "stable-growth"]
        ),
        
        // Advanced templates
        GoalTemplate(
            type: .investment,
            name: "Alt-Coin Speculation",
            description: "High-risk, high-reward portfolio focusing on emerging protocols",
            icon: "bolt.fill",
            color: .yellow,
            defaultAmount: 5000,
            defaultTimeframe: 365, // 1 year
            recommendedAssets: [
                AssetRecommendation(currency: "ETH", allocation: 0.3, reasoning: "Foundation layer"),
                AssetRecommendation(currency: "SOL", allocation: 0.25, reasoning: "Fast ecosystem"),
                AssetRecommendation(currency: "AVAX", allocation: 0.2, reasoning: "Scalable platform"),
                AssetRecommendation(currency: "MATIC", allocation: 0.25, reasoning: "Layer 2 solution")
            ],
            difficulty: .advanced,
            tags: ["speculative", "alt-coins", "high-risk"]
        )
    ]
    
    // MARK: - Template Filtering
    static func templatesForExperience(_ level: ExperienceLevel) -> [GoalTemplate] {
        switch level {
        case .beginner:
            return allTemplates.filter { $0.difficulty == .beginner }
        case .intermediate:
            return allTemplates.filter { $0.difficulty != .advanced }
        case .advanced:
            return allTemplates
        }
    }
    
    static func templatesForGoalType(_ goalType: GoalType) -> [GoalTemplate] {
        return allTemplates.filter { $0.type == goalType }
    }
    
    static func recommendedTemplates(for profile: UserProfile) -> [GoalTemplate] {
        var templates = templatesForExperience(profile.experienceLevel)
        
        // Filter by primary goal preference
        let primaryTemplates = templates.filter { $0.type == profile.primaryGoal }
        let otherTemplates = templates.filter { $0.type != profile.primaryGoal }
        
        // Return primary goal templates first, then others
        return primaryTemplates + otherTemplates.prefix(2)
    }
    
    // MARK: - Goal Creation
    func createGoal() -> (name: String, targetAmount: Double, deadline: Date, currency: String) {
        let deadline = Calendar.current.date(byAdding: .day, value: defaultTimeframe, to: Date()) ?? Date().addingTimeInterval(86400 * 365)
        
        return (
            name: name,
            targetAmount: defaultAmount,
            deadline: deadline,
            currency: currency
        )
    }
    
    func generateAssets() -> [AssetRecommendation] {
        return recommendedAssets
    }
}

// MARK: - Supporting Types
struct AssetRecommendation: Identifiable, Hashable {
    let id = UUID()
    let currency: String
    let allocation: Double // Percentage as decimal (0.0-1.0)
    let reasoning: String
    
    var allocationPercentage: Int {
        Int(allocation * 100)
    }
    
    var displayName: String {
        return currency.uppercased()
    }
}

enum TemplateDifficulty: String, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
    
    var description: String {
        switch self {
        case .beginner: return "Simple, stable approach with established cryptocurrencies"
        case .intermediate: return "Balanced portfolio with moderate risk and diversification"
        case .advanced: return "Complex strategies with higher risk and reward potential"
        }
    }
}

// MARK: - Template Extensions
extension GoalTemplate {
    var estimatedMonthlyContribution: Double {
        let months = max(1, defaultTimeframe / 30)
        return defaultAmount / Double(months)
    }
    
    var riskLevel: String {
        switch difficulty {
        case .beginner: return "Low Risk"
        case .intermediate: return "Medium Risk"
        case .advanced: return "High Risk"
        }
    }
    
    var timeframeDescription: String {
        let months = defaultTimeframe / 30
        let years = months / 12
        
        if years >= 1 {
            return "\(years) year\(years == 1 ? "" : "s")"
        } else {
            return "\(months) month\(months == 1 ? "" : "s")"
        }
    }
}