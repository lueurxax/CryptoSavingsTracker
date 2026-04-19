import Foundation
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

    @Test("onboarding UI-test failure flag is wired into goal creation service")
    func onboardingInjectedFailureFlagIsConsumedByGoalCreationService() throws {
        let root = repositoryRoot()
        let flagsSource = try readSource(root, "ios/CryptoSavingsTracker/Utilities/UITestFlags.swift")
        let serviceSource = try readSource(root, "ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift")

        #expect(flagsSource.contains("consumeSimulatedGoalSaveFailureIfNeeded"))
        #expect(serviceSource.contains("UITestFlags.consumeSimulatedGoalSaveFailureIfNeeded()"))
        #expect(serviceSource.contains("Simulated onboarding goal save failure"))
    }

    @Test("onboarding template save failure rolls back inserted graph")
    func onboardingTemplateSaveFailureRollsBackInsertedAssetsAndAllocations() throws {
        let root = repositoryRoot()
        let serviceSource = try readSource(root, "ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift")

        #expect(serviceSource.contains("var insertedAssets: [Asset] = []"))
        #expect(serviceSource.contains("var insertedAllocations: [AssetAllocation] = []"))
        #expect(serviceSource.contains("insertedAssets.append(asset)"))
        #expect(serviceSource.contains("insertedAllocations.append(allocation)"))
        #expect(serviceSource.contains("for allocation in insertedAllocations"))
        #expect(serviceSource.contains("modelContext.delete(allocation)"))
        #expect(serviceSource.contains("for asset in insertedAssets"))
        #expect(serviceSource.contains("modelContext.delete(asset)"))
    }

    @Test("onboarding UI test launch stays on onboarding shell")
    func onboardingUITestLaunchDoesNotBypassOnboardingShell() throws {
        let root = repositoryRoot()
        let onboardingUITestSource = try readSource(root, "ios/CryptoSavingsTrackerUITests/OnboardingUITests.swift")

        #expect(onboardingUITestSource.contains("UITEST_FORCE_ONBOARDING"))
        #expect(onboardingUITestSource.contains("UITEST_START_ON_GOALS"))
        #expect(!onboardingUITestSource.contains("\"UITEST_UI_FLOW\""))
        #expect(onboardingUITestSource.contains("tapIfExists(app.buttons[\"Create Goal\"])"))
    }

    @Test("forced onboarding reset starts at welcome step")
    func forcedOnboardingResetStartsOnboardingInsteadOfCompletingIt() throws {
        let root = repositoryRoot()
        let appSource = try readSource(root, "ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift")

        #expect(appSource.contains("if UITestFlags.shouldForceOnboarding {\n                OnboardingManager.shared.startOnboarding()"))
        #expect(appSource.contains("} else {\n                OnboardingManager.shared.completeOnboarding()"))
    }

    @Test("onboarding content gate checks completion + empty state")
    func onboardingGateRequiresUncompletedOnboardingAndEmptyGoals() throws {
        let root = repositoryRoot()
        let contentSource = try readSource(root, "ios/CryptoSavingsTracker/Views/OnboardingContentView.swift")

        #expect(contentSource.contains("return !onboardingManager.hasCompletedOnboarding && goals.isEmpty"))
        #expect(contentSource.contains("let forceOnboardingForUITest = UITestFlags.shouldForceOnboarding"))
        #expect(contentSource.contains("let shouldShow = (!onboardingManager.hasCompletedOnboarding || forceOnboardingForUITest) && goals.isEmpty"))
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
