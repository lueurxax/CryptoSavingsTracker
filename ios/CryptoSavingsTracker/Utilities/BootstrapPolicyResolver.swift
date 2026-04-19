//
//  BootstrapPolicyResolver.swift
//  CryptoSavingsTracker
//
//  Centralizes startup policy ownership for app bootstrap containment.
//

import Foundation

struct BootstrapLaunchContext: Equatable, Sendable {
    let arguments: [String]
    let environment: [String: String]

    init(
        arguments: [String],
        environment: [String: String]
    ) {
        self.arguments = arguments
        self.environment = environment
    }

    static func current(processInfo: ProcessInfo = .processInfo) -> Self {
        Self(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        )
    }

    var isXCTestRun: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    var isUITestRun: Bool {
        #if DEBUG
        arguments.contains(where: { $0.hasPrefix("UITEST") })
        #else
        false
        #endif
    }

    var isPreviewRun: Bool {
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var skipsStartupThrottle: Bool {
        isXCTestRun || isUITestRun || isPreviewRun
    }

    var captureMode: String? {
        environment["VISUAL_CAPTURE_MODE"]?.lowercased()
    }

    var productionFlow: String? {
        environment["VISUAL_PRODUCTION_FLOW"]
    }

    var productionState: String? {
        environment["VISUAL_PRODUCTION_STATE"]
    }

    var captureComponent: String? {
        environment["VISUAL_CAPTURE_COMPONENT"]
    }

    var captureState: String? {
        environment["VISUAL_CAPTURE_STATE"]
    }
}

struct AppBootstrapPlan: Sendable {
    let launchContext: BootstrapLaunchContext
    let persistenceBootstrap: PersistenceBootstrap
    let monitoringPlan: MonitoringPlan
    let platformBridgePlan: PlatformBridgePlan
    let testHarnessPlan: TestHarnessPlan
    let visualCapturePlan: VisualCapturePlan
    let rootShellPlan: RootShellPlan

    struct PersistenceBootstrap: Sendable {
        let shouldPerformDeferredCloudCleanup: Bool
        let shouldPerformLegacyLocalCleanup: Bool

        func run() {
            guard shouldPerformDeferredCloudCleanup || shouldPerformLegacyLocalCleanup else {
                return
            }

            // Cleanup must run before any cloud-backed container opens.
            if shouldPerformDeferredCloudCleanup {
                PersistenceController.performDeferredCloudStoreCleanupIfNeeded()
            }

            if shouldPerformLegacyLocalCleanup {
                PersistenceController.performLegacyLocalStoreCleanupIfNeeded()
            }
        }
    }

    struct MonitoringPlan: Sendable {
        let shouldDelayUntilStartupSettles: Bool
        let shouldStartCloudMonitoring: Bool

        func startIfNeeded(
            throttler: StartupThrottler,
            startMonitoring: @escaping @MainActor @Sendable () -> Void
        ) async {
            guard shouldStartCloudMonitoring else { return }

            if shouldDelayUntilStartupSettles {
                await throttler.waitForStartup()
            }

            await MainActor.run {
                startMonitoring()
            }
        }
    }

    struct PlatformBridgePlan: Sendable {
        let shouldEnableAppDelegateBridge: Bool

        static let retainedPublicDefault = Self(shouldEnableAppDelegateBridge: false)
    }

    struct TestHarnessPlan: Sendable {
        let isUITestRun: Bool
        let shouldResetData: Bool
        let shouldSeedGoals: Bool
        let shouldSeedManyGoals: Bool

        var blocksRootContent: Bool {
            isUITestRun
        }

        var shouldRunBootstrapTasks: Bool {
            shouldResetData || shouldSeedGoals || shouldSeedManyGoals
        }

        func applyLaunchDefaults(userDefaults: UserDefaults = .standard) {
            guard isUITestRun else { return }

            userDefaults.set("ui-test-owner", forKey: "familyShare.ownerID")
            userDefaults.set("ui-test-household", forKey: "familyShare.shareID")
            userDefaults.set("UI Test Owner", forKey: "familyShare.ownerName")
        }
    }

    struct VisualCapturePlan: Sendable {
        enum Destination: Sendable {
            case none
            case production(flow: String, state: String)
            case component(component: String, state: String)
        }

        let destination: Destination
    }

    struct RootShellPlan: Sendable {
        enum Destination: Sendable {
            case headless
            case content
            case onboarding
        }

        let destination: Destination
    }
}

enum BootstrapPolicyResolver {
    static func resolve(
        launchContext: BootstrapLaunchContext = .current()
    ) -> AppBootstrapPlan {
        let visualCaptureDestination: AppBootstrapPlan.VisualCapturePlan.Destination
        if launchContext.captureMode == "production", let flow = launchContext.productionFlow {
            visualCaptureDestination = .production(
                flow: flow,
                state: launchContext.productionState ?? "default"
            )
        } else if let component = launchContext.captureComponent,
                  let state = launchContext.captureState {
            visualCaptureDestination = .component(component: component, state: state)
        } else {
            visualCaptureDestination = .none
        }

        let rootShellDestination: AppBootstrapPlan.RootShellPlan.Destination
        #if DEBUG
        if launchContext.isXCTestRun && !launchContext.isUITestRun {
            rootShellDestination = .headless
        } else if launchContext.arguments.contains("UITEST_SEED_MANY_GOALS")
                    || launchContext.arguments.contains("UITEST_SEED_GOALS")
                    || launchContext.arguments.contains("UITEST_UI_FLOW") {
            rootShellDestination = .content
        } else {
            rootShellDestination = .onboarding
        }
        #else
        if launchContext.isXCTestRun {
            rootShellDestination = .headless
        } else {
            rootShellDestination = .onboarding
        }
        #endif

        #if DEBUG
        let testHarnessPlan = AppBootstrapPlan.TestHarnessPlan(
            isUITestRun: launchContext.isUITestRun,
            shouldResetData: launchContext.arguments.contains("UITEST_RESET_DATA"),
            shouldSeedGoals: launchContext.arguments.contains("UITEST_SEED_GOALS"),
            shouldSeedManyGoals: launchContext.arguments.contains("UITEST_SEED_MANY_GOALS")
        )
        #else
        let testHarnessPlan = AppBootstrapPlan.TestHarnessPlan(
            isUITestRun: false,
            shouldResetData: false,
            shouldSeedGoals: false,
            shouldSeedManyGoals: false
        )
        #endif

        return AppBootstrapPlan(
            launchContext: launchContext,
            persistenceBootstrap: .init(
                shouldPerformDeferredCloudCleanup: true,
                shouldPerformLegacyLocalCleanup: true
            ),
            monitoringPlan: .init(
                shouldDelayUntilStartupSettles: !launchContext.skipsStartupThrottle,
                shouldStartCloudMonitoring: !launchContext.skipsStartupThrottle
            ),
            platformBridgePlan: .retainedPublicDefault,
            testHarnessPlan: testHarnessPlan,
            visualCapturePlan: .init(destination: visualCaptureDestination),
            rootShellPlan: .init(destination: rootShellDestination)
        )
    }
}
