//
//  UITestFlags.swift
//  CryptoSavingsTracker
//
//  Helpers for UI test detection.
//

import Foundation

enum UITestFlags {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("UITEST_UI_FLOW")
            || args.contains("UITEST_RESET_DATA")
            || args.contains("UITEST_SEED_GOALS")
            || args.contains("UITEST_SEED_SHARED_ASSET")
    }
}
