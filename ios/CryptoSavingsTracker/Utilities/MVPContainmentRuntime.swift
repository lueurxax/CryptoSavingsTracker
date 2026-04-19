//
//  MVPContainmentRuntime.swift
//  CryptoSavingsTracker
//

import Foundation

enum HiddenRuntimeMode: String, Sendable {
    case publicMVP = "release_mvp"
    case debugInternal = "debug_internal"

    nonisolated static var current: HiddenRuntimeMode {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        if let explicit = HiddenRuntimeMode(rawValue: processInfo.environment["CST_RUNTIME_MODE"] ?? "") {
            return explicit
        }

        let environment = processInfo.environment
        let arguments = processInfo.arguments
        let isTestHarness = environment["XCTestConfigurationFilePath"] != nil
            || arguments.contains(where: { $0.hasPrefix("UITEST") })
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["VISUAL_CAPTURE_MODE"] != nil
            || environment["VISUAL_CAPTURE_COMPONENT"] != nil

        return isTestHarness ? .debugInternal : .publicMVP
        #else
        return .publicMVP
        #endif
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
