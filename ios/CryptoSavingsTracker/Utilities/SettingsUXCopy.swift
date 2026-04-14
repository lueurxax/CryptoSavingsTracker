//
//  SettingsUXCopy.swift
//  CryptoSavingsTracker
//

import Foundation

enum SettingsUXCopy {
    static let importDataTitle = "Import Data"
    static let importDataHint =
        "Double tap to open Local Bridge Sync and review import packages before applying them."
    static let dataSectionFooter =
        "Exports create CSV snapshots. Imports are reviewed through Local Bridge Sync before changes are applied."
    static let syncSectionFooter =
        "Sync keeps your latest savings data up to date, while local storage only supports cached helper data."

    static func navigationHint(destination: String) -> String {
        "Double tap to open \(destination)."
    }
}
