import Testing
@testable import CryptoSavingsTracker

struct OnboardingFlowContractTests {
    @Test("onboarding failure path must not complete onboarding")
    func onboardingFailurePathKeepsOnboardingActive() throws {
        let root = repositoryRoot()
        let flowSource = try readSource(root, "ios/CryptoSavingsTracker/Views/Onboarding/OnboardingFlowView.swift")

        #expect(flowSource.contains("do {"))
        #expect(flowSource.contains("catch {"))
        #expect(flowSource.contains("goalCreationState.handleFailure(error)"))
        #expect(!flowSource.contains("catch {\n                onboardingManager.completeOnboarding()"))
    }

    @Test("onboarding retry action still invokes goal creation closure")
    func onboardingRetryCallsCreateGoalFromTemplate() throws {
        let root = repositoryRoot()
        let flowSource = try readSource(root, "ios/CryptoSavingsTracker/Views/Onboarding/OnboardingFlowView.swift")

        #expect(flowSource.contains("ErrorBannerView"))
        #expect(flowSource.contains("error.isRetryable ? { () async in\n                                createGoalFromTemplate()"))
    }

    @Test("onboarding content gate checks completion + empty state")
    func onboardingGateRequiresUncompletedOnboardingAndEmptyGoals() throws {
        let root = repositoryRoot()
        let contentSource = try readSource(root, "ios/CryptoSavingsTracker/Views/OnboardingContentView.swift")

        #expect(contentSource.contains("return !onboardingManager.hasCompletedOnboarding && goals.isEmpty"))
        #expect(contentSource.contains("let shouldShow = (!onboardingManager.hasCompletedOnboarding || UITestFlags.shouldForceOnboarding) && goals.isEmpty"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
