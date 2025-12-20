//
//  OnboardingFlowView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var selectedTemplate: GoalTemplate?
    @State private var isCreatingGoal = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.accessiblePrimary.opacity(0.1),
                        Color.accessiblePrimaryBackground.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    OnboardingProgressView(currentStep: onboardingManager.currentStep)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    
                    // Main content
                    ScrollView {
                        VStack(spacing: 32) {
                            currentStepView
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)
                    }
                    
                    // Navigation buttons
                    OnboardingNavigationView(
                        currentStep: onboardingManager.currentStep,
                        canProceed: canProceedToNextStep,
                        onNext: handleNextTapped,
                        onPrevious: handlePreviousTapped,
                        onSkip: handleSkipTapped
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34) // Account for safe area
                }
            }
        }
#if os(iOS)
        .navigationViewStyle(StackNavigationViewStyle())
#endif
        .interactiveDismissDisabled(true)
    }
    
    @ViewBuilder
    private var currentStepView: some View {
        switch onboardingManager.currentStep {
        case .welcome:
            OnboardingWelcomeView()
            
        case .userProfile:
            OnboardingProfileView(userProfile: $onboardingManager.userProfile)
            
        case .goalTemplate:
            OnboardingGoalTemplateView(
                userProfile: onboardingManager.userProfile,
                selectedTemplate: $selectedTemplate
            )
            
        case .assetSelection:
            if let template = selectedTemplate {
                OnboardingAssetSelectionView(
                    template: template,
                    userProfile: onboardingManager.userProfile
                )
            }
            
        case .setupComplete:
            OnboardingCompletionView(
                template: selectedTemplate,
                onComplete: {
                    createGoalFromTemplate()
                }
            )
            
        case .completed:
            EmptyView()
        }
    }
    
    private var canProceedToNextStep: Bool {
        switch onboardingManager.currentStep {
        case .welcome:
            return true
        case .userProfile:
            return true // Profile has reasonable defaults
        case .goalTemplate:
            return selectedTemplate != nil
        case .assetSelection:
            return true // Assets are pre-selected from template
        case .setupComplete:
            return true
        case .completed:
            return false
        }
    }
    
    private func handleNextTapped() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if onboardingManager.currentStep.isLastStep {
                createGoalFromTemplate()
            } else {
                onboardingManager.moveToNextStep()
            }
        }
    }
    
    private func handlePreviousTapped() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardingManager.moveToPreviousStep()
        }
    }
    
    private func handleSkipTapped() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardingManager.completeOnboarding()
        }
    }
    
    private func createGoalFromTemplate() {
        guard let template = selectedTemplate else {
            onboardingManager.completeOnboarding()
            return
        }
        
        isCreatingGoal = true
        
        Task {
            do {
                // Create goal from template
                let goalData = template.createGoal()
                let goal = Goal(
                    name: goalData.name,
                    currency: goalData.currency,
                    targetAmount: goalData.targetAmount,
                    deadline: goalData.deadline,
                    startDate: Date()
                )
                
                // Set up notifications if user selected a preference
                if onboardingManager.userProfile.experienceLevel != .beginner {
                    goal.reminderFrequency = ReminderFrequency.weekly.rawValue
                    goal.reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
                }
                
                modelContext.insert(goal)
                
                // Create recommended assets with allocations
                let assetRecommendations = template.generateAssets()
                for recommendation in assetRecommendations.prefix(3) { // Limit to 3 assets for simplicity
                    let asset = Asset(
                        currency: recommendation.currency
                    )
                    modelContext.insert(asset)
                    
                    // Create 100% allocation to this goal
                    let allocation = AssetAllocation(asset: asset, goal: goal, amount: asset.currentAmount)
                    modelContext.insert(allocation)
                }
                
                try modelContext.save()
                
                // Mark achievements
                await MainActor.run {
                    onboardingManager.markFirstGoalCompleted()
                    onboardingManager.completeOnboarding()
                    isCreatingGoal = false
                }
                
            } catch {
                await MainActor.run {
                    // Handle error - for now just complete onboarding
                    print("Failed to create goal from template: \(error)")
                    onboardingManager.completeOnboarding()
                    isCreatingGoal = false
                }
            }
        }
    }
}

// MARK: - Progress Indicator
struct OnboardingProgressView: View {
    let currentStep: OnboardingStep
    
    private let steps: [OnboardingStep] = [.welcome, .userProfile, .goalTemplate, .assetSelection, .setupComplete]
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Rectangle()
                        .fill(currentStepIndex >= index ? Color.accessiblePrimary : Color.accessibleSecondary.opacity(0.3))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentStepIndex)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            
            // Step indicator
            HStack {
                Text(currentStep.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(currentStepIndex + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
            }
        }
    }
    
    private var currentStepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }
}

// MARK: - Navigation
struct OnboardingNavigationView: View {
    let currentStep: OnboardingStep
    let canProceed: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Main navigation buttons
            HStack(spacing: 16) {
                // Back button
                if !currentStep.isFirstStep {
                    Button(action: onPrevious) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.accessibleSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accessibleHover)
                        )
                    }
                    .accessibilityLabel("Go back to previous step")
                } else {
                    Spacer()
                        .frame(width: 80) // Maintain spacing
                }
                
                Spacer()
                
                // Next/Complete button
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text(nextButtonText)
                            .font(.system(size: 16, weight: .semibold))
                        
                        if !currentStep.isLastStep {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canProceed ? Color.accessiblePrimary : Color.accessibleSecondary)
                    )
                }
                .disabled(!canProceed)
                .accessibilityLabel(nextButtonText)
            }
            
            // Skip option
            if currentStep != .setupComplete {
                Button("Skip setup and explore") {
                    onSkip()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accessibleSecondary)
                .accessibilityLabel("Skip onboarding setup")
            }
        }
    }
    
    private var nextButtonText: String {
        switch currentStep {
        case .setupComplete:
            return "Start Saving"
        case .assetSelection:
            return "Create Goal"
        default:
            return "Continue"
        }
    }
}

#Preview {
    OnboardingFlowView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
