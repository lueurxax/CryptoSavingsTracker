import Foundation

@MainActor
protocol OnboardingFlowStateControlling: AnyObject {
    var hasCompletedOnboarding: Bool { get }
    var currentStep: OnboardingStep { get }

    func markFirstGoalCompleted()
    func completeOnboarding()
}

struct OnboardingGoalCreationState {
    var isCreatingGoal = false
    var error: UserFacingError?

    mutating func begin() {
        isCreatingGoal = true
        error = nil
    }

    mutating func handleSuccess(using onboardingFlow: OnboardingFlowStateControlling) {
        onboardingFlow.markFirstGoalCompleted()
        onboardingFlow.completeOnboarding()
        isCreatingGoal = false
        error = nil
    }

    mutating func handleFailure(_ error: Error) {
        isCreatingGoal = false
        self.error = Self.makeUserFacingError(from: error)
    }

    mutating func handleMissingTemplateSelection() {
        isCreatingGoal = false
        error = UserFacingError(
            title: "Choose a Goal Template",
            message: "Select a goal template before finishing onboarding.",
            recoverySuggestion: "Pick a template to keep your progress and create your first goal.",
            isRetryable: false,
            category: .unknown
        )
    }

    mutating func clearError() {
        error = nil
    }

    private static func makeUserFacingError(from error: Error) -> UserFacingError {
        if let persistenceError = error as? PersistenceMutationError {
            switch persistenceError {
            case .saveFailed:
                return UserFacingError(
                    title: "Goal Setup Failed",
                    message: "We couldn't create your first goal yet.",
                    recoverySuggestion: "Retry to keep your setup progress and try again.",
                    isRetryable: true,
                    category: .dataCorruption
                )
            case .validationFailed(let message):
                return UserFacingError(
                    title: "Goal Setup Failed",
                    message: message,
                    recoverySuggestion: "Review your setup and try again.",
                    isRetryable: false,
                    category: .unknown
                )
            case .objectNotFound(let message):
                return UserFacingError(
                    title: "Goal Setup Failed",
                    message: message,
                    recoverySuggestion: "Retry to keep your setup progress and try again.",
                    isRetryable: true,
                    category: .unknown
                )
            }
        }

        return UserFacingError(
            title: "Goal Setup Failed",
            message: "We couldn't create your first goal yet.",
            recoverySuggestion: "Retry to keep your setup progress and try again.",
            isRetryable: true,
            category: .unknown
        )
    }
}
