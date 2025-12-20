//
//  OnboardingManager.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftData
import Combine

/// Manages user onboarding state and progress through the app
@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var hasCompletedOnboarding: Bool = false
    @Published var currentStep: OnboardingStep = .welcome
    @Published var userProfile: UserProfile = UserProfile()
    
    private let userDefaults = UserDefaults.standard
    private let onboardingCompletedKey = "hasCompletedOnboarding"
    private let userProfileKey = "userProfile"
    
    private init() {
        loadOnboardingState()
    }
    
    // MARK: - Onboarding Flow
    func startOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        userProfile = UserProfile()
        saveOnboardingState()
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        currentStep = .completed
        saveOnboardingState()
    }
    
    func moveToNextStep() {
        currentStep = currentStep.nextStep
        saveOnboardingState()
    }
    
    func moveToPreviousStep() {
        currentStep = currentStep.previousStep
        saveOnboardingState()
    }
    
    func skipOnboarding() {
        hasCompletedOnboarding = true
        currentStep = .completed
        saveOnboardingState()
    }
    
    // MARK: - User Assessment
    func shouldShowAdvancedFeatures() -> Bool {
        return userProfile.experienceLevel == .advanced || 
               userProfile.hasExistingPortfolio ||
               hasCompletedFirstGoal()
    }
    
    func shouldShowDetailedCharts() -> Bool {
        return shouldShowAdvancedFeatures() && hasTransactionData()
    }
    
    func hasCompletedFirstGoal() -> Bool {
        // This would be checked against actual data in real implementation
        return userDefaults.bool(forKey: "hasCompletedFirstGoal")
    }
    
    func hasTransactionData() -> Bool {
        // This would be checked against actual SwiftData in real implementation
        return userDefaults.bool(forKey: "hasTransactionData")
    }
    
    func markFirstGoalCompleted() {
        userDefaults.set(true, forKey: "hasCompletedFirstGoal")
    }
    
    func markTransactionDataAdded() {
        userDefaults.set(true, forKey: "hasTransactionData")
    }
    
    // MARK: - Persistence
    private func saveOnboardingState() {
        userDefaults.set(hasCompletedOnboarding, forKey: onboardingCompletedKey)
        
        if let profileData = try? JSONEncoder().encode(userProfile) {
            userDefaults.set(profileData, forKey: userProfileKey)
        }
    }
    
    private func loadOnboardingState() {
        hasCompletedOnboarding = userDefaults.bool(forKey: onboardingCompletedKey)
        
        if let profileData = userDefaults.data(forKey: userProfileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            userProfile = profile
        }
    }
}

// MARK: - Onboarding Steps
enum OnboardingStep: String, CaseIterable, Codable {
    case welcome = "welcome"
    case userProfile = "userProfile"
    case goalTemplate = "goalTemplate"
    case assetSelection = "assetSelection"
    case setupComplete = "setupComplete"
    case completed = "completed"
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to CryptoSavings"
        case .userProfile:
            return "Tell us about yourself"
        case .goalTemplate:
            return "Choose your first goal"
        case .assetSelection:
            return "Select cryptocurrencies"
        case .setupComplete:
            return "You're all set!"
        case .completed:
            return "Complete"
        }
    }
    
    var subtitle: String {
        switch self {
        case .welcome:
            return "Track your cryptocurrency savings goals with precision and insight"
        case .userProfile:
            return "We'll customize the experience based on your needs"
        case .goalTemplate:
            return "Start with a pre-configured template or create your own"
        case .assetSelection:
            return "Pick the cryptocurrencies you want to save"
        case .setupComplete:
            return "Your first goal is ready to track"
        case .completed:
            return ""
        }
    }
    
    var nextStep: OnboardingStep {
        switch self {
        case .welcome: return .userProfile
        case .userProfile: return .goalTemplate
        case .goalTemplate: return .assetSelection
        case .assetSelection: return .setupComplete
        case .setupComplete: return .completed
        case .completed: return .completed
        }
    }
    
    var previousStep: OnboardingStep {
        switch self {
        case .welcome: return .welcome
        case .userProfile: return .welcome
        case .goalTemplate: return .userProfile
        case .assetSelection: return .goalTemplate
        case .setupComplete: return .assetSelection
        case .completed: return .setupComplete
        }
    }
    
    var isFirstStep: Bool {
        return self == .welcome
    }
    
    var isLastStep: Bool {
        return self == .setupComplete
    }
}

// MARK: - User Profile
struct UserProfile: Codable {
    var experienceLevel: ExperienceLevel = .beginner
    var primaryGoal: GoalType = .emergency
    var targetTimeframe: TimeframePreference = .medium
    var hasExistingPortfolio: Bool = false
    var preferredCurrencies: [String] = []
    var investmentStyle: InvestmentStyle = .conservative
}

enum ExperienceLevel: String, CaseIterable, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate" 
    case advanced = "advanced"
    
    var displayName: String {
        switch self {
        case .beginner: return "New to crypto"
        case .intermediate: return "Some experience"
        case .advanced: return "Experienced trader"
        }
    }
    
    var description: String {
        switch self {
        case .beginner: return "I'm just getting started with cryptocurrency"
        case .intermediate: return "I have some crypto experience and basic knowledge"
        case .advanced: return "I actively trade and manage crypto portfolios"
        }
    }
}

enum GoalType: String, CaseIterable, Codable {
    case emergency = "emergency"
    case retirement = "retirement"
    case investment = "investment"
    case travel = "travel"
    case purchase = "purchase"
    case education = "education"
    
    var displayName: String {
        switch self {
        case .emergency: return "Emergency Fund"
        case .retirement: return "Retirement Savings"
        case .investment: return "Investment Portfolio"
        case .travel: return "Travel Fund"
        case .purchase: return "Major Purchase"
        case .education: return "Education Fund"
        }
    }
}

enum TimeframePreference: String, CaseIterable, Codable {
    case short = "short"      // 1-6 months
    case medium = "medium"    // 6 months - 2 years  
    case long = "long"        // 2+ years
    
    var displayName: String {
        switch self {
        case .short: return "Short-term (1-6 months)"
        case .medium: return "Medium-term (6 months - 2 years)"
        case .long: return "Long-term (2+ years)"
        }
    }
}

enum InvestmentStyle: String, CaseIterable, Codable {
    case conservative = "conservative"
    case balanced = "balanced"
    case aggressive = "aggressive"
    
    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced" 
        case .aggressive: return "Aggressive"
        }
    }
    
    var description: String {
        switch self {
        case .conservative: return "Prefer stable, established cryptocurrencies"
        case .balanced: return "Mix of stable and growth-oriented cryptocurrencies"
        case .aggressive: return "Open to newer, high-potential cryptocurrencies"
        }
    }
}