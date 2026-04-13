import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct OnboardingGoalCreationStateTests {
    private final class OnboardingFlowSpy: OnboardingFlowStateControlling {
        var hasCompletedOnboarding = false
        var currentStep: OnboardingStep = .setupComplete
        private(set) var markFirstGoalCompletedCallCount = 0
        private(set) var completeOnboardingCallCount = 0

        func markFirstGoalCompleted() {
            markFirstGoalCompletedCallCount += 1
        }

        func completeOnboarding() {
            hasCompletedOnboarding = true
            currentStep = .completed
            completeOnboardingCallCount += 1
        }
    }

    @Test("goal creation failure keeps onboarding active and exposes retryable error")
    func goalCreationFailureKeepsOnboardingActive() {
        let onboardingFlow = OnboardingFlowSpy()
        var state = OnboardingGoalCreationState()

        state.begin()
        state.handleFailure(
            PersistenceMutationError.saveFailed(
                "Unable to create onboarding goal",
                underlying: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
            )
        )

        #expect(state.isCreatingGoal == false)
        #expect(state.error != nil)
        #expect(state.error?.title == "Goal Setup Failed")
        #expect(state.error?.isRetryable == true)
        #expect(onboardingFlow.hasCompletedOnboarding == false)
        #expect(onboardingFlow.currentStep == .setupComplete)
        #expect(onboardingFlow.markFirstGoalCompletedCallCount == 0)
        #expect(onboardingFlow.completeOnboardingCallCount == 0)
    }

    @Test("failure in goal creation retains active onboarding step")
    func failureKeepsCurrentStepForRecoveryRetry() {
        let onboardingFlow = OnboardingFlowSpy()
        onboardingFlow.currentStep = .assetSelection
        var state = OnboardingGoalCreationState()

        state.begin()
        state.handleFailure(PersistenceMutationError.saveFailed("temporary error", underlying: NSError(
            domain: "test",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "network timeout"]
        )))

        #expect(state.isCreatingGoal == false)
        #expect(state.error != nil)
        #expect(onboardingFlow.currentStep == .assetSelection)
        #expect(onboardingFlow.completeOnboardingCallCount == 0)
        #expect(onboardingFlow.markFirstGoalCompletedCallCount == 0)
    }

    @Test("validation failure should be non-retryable and keep onboarding active")
    func validationFailureIsNonRetryable() {
        let onboardingFlow = OnboardingFlowSpy()
        var state = OnboardingGoalCreationState()
        onboardingFlow.currentStep = .goalTemplate

        state.begin()
        state.handleFailure(PersistenceMutationError.validationFailed("Template selected is missing required fields"))

        #expect(state.error != nil)
        #expect(state.error?.isRetryable == false)
        #expect(state.error?.title == "Goal Setup Failed")
        #expect(onboardingFlow.currentStep == .goalTemplate)
        #expect(onboardingFlow.hasCompletedOnboarding == false)
        #expect(onboardingFlow.completeOnboardingCallCount == 0)
    }

    @Test("missing template keeps onboarding active and asks the user to choose one")
    func missingTemplateKeepsOnboardingActive() {
        let onboardingFlow = OnboardingFlowSpy()
        var state = OnboardingGoalCreationState()

        state.handleMissingTemplateSelection()

        #expect(state.isCreatingGoal == false)
        #expect(state.error?.title == "Choose a Goal Template")
        #expect(state.error?.isRetryable == false)
        #expect(onboardingFlow.hasCompletedOnboarding == false)
        #expect(onboardingFlow.currentStep == .setupComplete)
        #expect(onboardingFlow.markFirstGoalCompletedCallCount == 0)
        #expect(onboardingFlow.completeOnboardingCallCount == 0)
    }

    @Test("goal creation success completes onboarding")
    func goalCreationSuccessCompletesOnboarding() {
        let onboardingFlow = OnboardingFlowSpy()
        var state = OnboardingGoalCreationState()

        state.begin()
        state.handleSuccess(using: onboardingFlow)

        #expect(state.isCreatingGoal == false)
        #expect(state.error == nil)
        #expect(onboardingFlow.hasCompletedOnboarding == true)
        #expect(onboardingFlow.currentStep == .completed)
        #expect(onboardingFlow.markFirstGoalCompletedCallCount == 1)
        #expect(onboardingFlow.completeOnboardingCallCount == 1)
    }
}
