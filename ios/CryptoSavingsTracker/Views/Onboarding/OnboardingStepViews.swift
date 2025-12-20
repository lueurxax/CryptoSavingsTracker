//
//  OnboardingStepViews.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// MARK: - Welcome Step
struct OnboardingWelcomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            // Hero image/icon
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accessiblePrimary.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accessiblePrimary)
                }
                .shadow(color: Color.accessiblePrimary.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            
            // Content
            VStack(spacing: 16) {
                Text("Welcome to CryptoSavings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Text("Track your cryptocurrency savings goals with precision, insights, and smart automation across 15+ blockchain networks.")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.accessibleSecondary)
                    .lineSpacing(2)
            }
            
            // Features highlight
            VStack(spacing: 16) {
                FeatureHighlight(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Smart Tracking",
                    description: "Real-time balance updates and detailed progress analytics"
                )
                
                FeatureHighlight(
                    icon: "link",
                    title: "Multi-Chain Support",
                    description: "Bitcoin, Ethereum, Solana, and 12+ other networks"
                )
                
                FeatureHighlight(
                    icon: "target",
                    title: "Goal-Based Saving",
                    description: "Organize savings by purpose with intelligent reminders"
                )
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Profile Step
struct OnboardingProfileView: View {
    @Binding var userProfile: UserProfile
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Text("Tell us about yourself")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text("We'll customize your experience based on your crypto knowledge and goals")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.accessibleSecondary)
            }
            
            VStack(spacing: 24) {
                // Experience Level
                ProfileSection(title: "Crypto Experience") {
                    VStack(spacing: 8) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { level in
                            ExperienceOption(
                                level: level,
                                isSelected: userProfile.experienceLevel == level
                            ) {
                                userProfile.experienceLevel = level
                            }
                        }
                    }
                }
                
                // Primary Goal
                ProfileSection(title: "What's your main savings goal?") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                        ForEach(GoalType.allCases, id: \.self) { goalType in
                            GoalTypeOption(
                                goalType: goalType,
                                isSelected: userProfile.primaryGoal == goalType
                            ) {
                                userProfile.primaryGoal = goalType
                            }
                        }
                    }
                }
                
                // Timeframe
                ProfileSection(title: "Investment Timeline") {
                    VStack(spacing: 8) {
                        ForEach(TimeframePreference.allCases, id: \.self) { timeframe in
                            TimeframeOption(
                                timeframe: timeframe,
                                isSelected: userProfile.targetTimeframe == timeframe
                            ) {
                                userProfile.targetTimeframe = timeframe
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Goal Template Step
struct OnboardingGoalTemplateView: View {
    let userProfile: UserProfile
    @Binding var selectedTemplate: GoalTemplate?
    
    private var recommendedTemplates: [GoalTemplate] {
        GoalTemplate.recommendedTemplates(for: userProfile)
    }
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Text("Choose your first goal")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text("We've selected templates based on your preferences. You can always create custom goals later.")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.accessibleSecondary)
            }
            
            // Template options
            VStack(spacing: 16) {
                ForEach(recommendedTemplates.prefix(3), id: \.id) { template in
                    GoalTemplateCard(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id
                    ) {
                        selectedTemplate = template
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Asset Selection Step
struct OnboardingAssetSelectionView: View {
    let template: GoalTemplate
    let userProfile: UserProfile
    @State private var selectedAssets: Set<String> = []
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Text("Select cryptocurrencies")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text("Based on your \"\(template.name)\" goal, here are our recommended cryptocurrencies:")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.accessibleSecondary)
            }
            
            // Asset recommendations
            VStack(spacing: 16) {
                ForEach(template.recommendedAssets, id: \.id) { asset in
                    AssetRecommendationCard(
                        asset: asset,
                        isSelected: selectedAssets.contains(asset.currency)
                    ) {
                        if selectedAssets.contains(asset.currency) {
                            selectedAssets.remove(asset.currency)
                        } else {
                            selectedAssets.insert(asset.currency)
                        }
                    }
                }
            }
            
            // Explanation
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accessiblePrimary)
                    
                    Text("Why these assets?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accessiblePrimary)
                    
                    Spacer()
                }
                
                Text("We've selected a balanced mix based on your \\(userProfile.experienceLevel.displayName.lowercased()) experience level and \\(template.riskLevel.lowercased()) approach.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accessibleSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accessiblePrimary.opacity(0.05))
            )
        }
        .padding(.vertical, 16)
        .onAppear {
            // Pre-select all recommended assets
            selectedAssets = Set(template.recommendedAssets.map { $0.currency })
        }
    }
}

// MARK: - Completion Step
struct OnboardingCompletionView: View {
    let template: GoalTemplate?
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            // Success animation area
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                }
                .shadow(color: Color.green.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            
            // Completion message
            VStack(spacing: 16) {
                Text("You're all set!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                if let template = template {
                    Text("Your \"\(template.name)\" goal is ready to track. Start adding transactions to see your progress grow.")
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.accessibleSecondary)
                        .lineSpacing(2)
                } else {
                    Text("Your savings journey begins now. Create goals and start tracking your cryptocurrency portfolio.")
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.accessibleSecondary)
                        .lineSpacing(2)
                }
            }
            
            // Quick stats preview
            if let template = template {
                VStack(spacing: 12) {
                    HStack {
                        StatPreview(
                            icon: "dollarsign.circle",
                            title: "Target",
                            value: "$\(Int(template.defaultAmount).formatted())"
                        )
                        
                        Spacer()
                        
                        StatPreview(
                            icon: "calendar.circle",
                            title: "Timeline",
                            value: template.timeframeDescription
                        )
                        
                        Spacer()
                        
                        StatPreview(
                            icon: "chart.bar.fill",
                            title: "Monthly",
                            value: "$\(Int(template.estimatedMonthlyContribution).formatted())"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accessibleHover)
                )
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Supporting Views
struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.accessiblePrimary)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accessibleSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            content
        }
    }
}

struct ExperienceOption: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(level.description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accessibleSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accessiblePrimary.opacity(0.1) : Color.accessibleHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accessiblePrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GoalTypeOption: View {
    let goalType: GoalType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: iconForGoalType(goalType))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
                
                Text(goalType.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accessiblePrimary.opacity(0.1) : Color.accessibleHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accessiblePrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForGoalType(_ type: GoalType) -> String {
        switch type {
        case .emergency: return "shield.fill"
        case .retirement: return "house.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .travel: return "airplane"
        case .purchase: return "cart.fill"
        case .education: return "graduationcap.fill"
        }
    }
}

struct TimeframeOption: View {
    let timeframe: TimeframePreference
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(timeframe.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accessiblePrimary.opacity(0.1) : Color.accessibleHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accessiblePrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GoalTemplateCard: View {
    let template: GoalTemplate
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                VStack {
                    Image(systemName: template.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(template.color)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(template.color.opacity(0.1))
                        )
                    
                    Spacer()
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(template.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(template.difficulty.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(template.difficulty.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(template.difficulty.color.opacity(0.1))
                            )
                    }
                    
                    Text(template.description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accessibleSecondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 16) {
                        Label("$\(Int(template.defaultAmount).formatted())", systemImage: "dollarsign.circle")
                        Label(template.timeframeDescription, systemImage: "calendar.circle")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accessibleSecondary)
                }
                
                // Selection indicator
                VStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accessiblePrimary.opacity(0.05) : Color.accessibleHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accessiblePrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AssetRecommendationCard: View {
    let asset: AssetRecommendation
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Asset icon (placeholder)
                Text(asset.currency.prefix(2).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(colorForCurrency(asset.currency))
                    )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(asset.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(asset.allocationPercentage)%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accessiblePrimary)
                    }
                    
                    Text(asset.reasoning)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accessibleSecondary)
                }
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accessiblePrimary : .accessibleSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accessiblePrimary.opacity(0.05) : Color.accessibleHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accessiblePrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func colorForCurrency(_ currency: String) -> Color {
        switch currency.uppercased() {
        case "BTC": return .orange
        case "ETH": return .blue
        case "SOL": return .purple
        case "USDC": return .green
        case "ADA": return .blue
        case "MATIC": return .purple
        case "AVAX": return .red
        default: return .gray
        }
    }
}

struct StatPreview: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.accessiblePrimary)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accessibleSecondary)
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OnboardingWelcomeView()
        .padding()
}