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
    @State private var goalCreationState = OnboardingGoalCreationState()

    var body: some View {
        NavigationStack {
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
                    
                    if let error = goalCreationState.error {
                        ErrorBannerView(
                            error: error,
                            onRetry: error.isRetryable ? { () async in
                                createGoalFromTemplate()
                            } : nil,
                            onDismiss: { goalCreationState.clearError() }
                        )
                        .padding(.top, 16)
                        .accessibilityIdentifier("onboardingGoalCreationError")
                    }
                    
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
                        isProcessing: goalCreationState.isCreatingGoal,
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
            VStack(spacing: 12) {
                Text("You’re all set")
                    .font(.title2.bold())
                Text("Onboarding is complete. Continue to your goals and begin tracking.")
                    .font(.body)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
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
            return !goalCreationState.isCreatingGoal
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
        goalCreationState.clearError()
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardingManager.moveToPreviousStep()
        }
    }
    
    private func handleSkipTapped() {
        withAnimation(.easeInOut(duration: 0.3)) {
            goalCreationState.clearError()
            onboardingManager.completeOnboarding()
        }
    }
    
    private func createGoalFromTemplate() {
        guard let template = selectedTemplate else {
            goalCreationState.handleMissingTemplateSelection()
            return
        }

        goalCreationState.begin()

        Task {
            do {
                try await DIContainer.shared.makeOnboardingMutationService(modelContext: modelContext)
                    .createGoalFromTemplate(template, userProfile: onboardingManager.userProfile)
                
                // Mark achievements
                await MainActor.run {
                    goalCreationState.handleSuccess(using: onboardingManager)
                }
                
            } catch {
                await MainActor.run {
                    goalCreationState.handleFailure(error)
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
    let isProcessing: Bool
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
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }

                        Text(nextButtonText)
                            .font(.system(size: 16, weight: .semibold))
                        
                        if !currentStep.isLastStep && !isProcessing {
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
                .disabled(!canProceed || isProcessing)
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
                .disabled(isProcessing)
            }
        }
    }
    
    private var nextButtonText: String {
        if isProcessing {
            return "Creating Goal..."
        }

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
