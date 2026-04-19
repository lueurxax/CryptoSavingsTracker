//
//  MVPContainmentRuntime.swift
//  CryptoSavingsTracker
//

import Foundation

enum PreviewFeaturesRuntime {
    nonisolated static let userDefaultsKey = "mvp.previewFeatures.enabled"

    nonisolated static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: userDefaultsKey)
    }

    nonisolated static func setEnabled(_ isEnabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: userDefaultsKey)
    }
}

enum HiddenRuntimeMode: String, Sendable {
    case publicMVP = "release_mvp"
    case debugInternal = "debug_internal"

    nonisolated static var current: HiddenRuntimeMode {
        let processInfo = ProcessInfo.processInfo
        return resolved(
            environment: processInfo.environment,
            arguments: processInfo.arguments,
            userDefaults: .standard
        )
    }

    nonisolated static func resolved(
        environment: [String: String],
        arguments: [String],
        userDefaults: UserDefaults
    ) -> HiddenRuntimeMode {
        #if DEBUG
        if let explicit = HiddenRuntimeMode(rawValue: environment["CST_RUNTIME_MODE"] ?? "") {
            return explicit
        }

        let isTestHarness = environment["XCTestConfigurationFilePath"] != nil
            || arguments.contains(where: { $0.hasPrefix("UITEST") })
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["VISUAL_CAPTURE_MODE"] != nil
            || environment["VISUAL_CAPTURE_COMPONENT"] != nil

        if isTestHarness {
            return .debugInternal
        }
        #endif

        return PreviewFeaturesRuntime.isEnabled(userDefaults: userDefaults) ? .debugInternal : .publicMVP
    }

    nonisolated var hiddenRuntimeEnabledByDefault: Bool {
        allowsFamilySharing
    }

    nonisolated var allowsFamilySharing: Bool {
        self == .debugInternal
    }

    nonisolated var allowsNotificationPrompts: Bool {
        self == .debugInternal
    }

    nonisolated var allowsReminderScheduling: Bool {
        self == .debugInternal
    }

    nonisolated var allowsAutomationScheduler: Bool {
        self == .debugInternal
    }

    nonisolated var allowsShortcuts: Bool {
        self == .debugInternal
    }

    nonisolated var showsForecastModules: Bool {
        self == .debugInternal
    }
}
