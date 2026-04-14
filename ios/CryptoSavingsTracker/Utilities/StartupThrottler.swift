//
//  StartupThrottler.swift
//  CryptoSavingsTracker
//
//  Prevents excessive API calls during startup
//

import Foundation

class StartupThrottler {
    static let shared = StartupThrottler()

    private var isStartupComplete = false
    private var startupCompletionTime: Date?
    private let startupDelay: TimeInterval = 3.0 // Wait 3 seconds after startup

    private init() {}

    private var launchContext: BootstrapLaunchContext {
        BootstrapLaunchContext.current()
    }

    private var shouldBypassStartupThrottle: Bool {
        launchContext.skipsStartupThrottle
    }

    func markStartupComplete() {
        isStartupComplete = true
        startupCompletionTime = Date()
    }

    func shouldThrottleAPICall() -> Bool {
        guard !shouldBypassStartupThrottle else {
            return false
        }

        // During startup, throttle all API calls
        if !isStartupComplete {
            return true
        }

        // For first few seconds after startup, throttle API calls
        if let completionTime = startupCompletionTime,
           Date().timeIntervalSince(completionTime) < startupDelay {
            return true
        }

        return false
    }

    func waitForStartup() async {
        guard !shouldBypassStartupThrottle else {
            if !isStartupComplete {
                markStartupComplete()
            }
            return
        }

        if !isStartupComplete {
            // Wait for startup to complete
            try? await Task.sleep(nanoseconds: UInt64(startupDelay * 1_000_000_000))
            markStartupComplete()
        }
    }
}
