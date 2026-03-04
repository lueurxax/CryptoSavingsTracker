// Extracted preview-only declarations for NAV003 policy compliance.
// Source: CSVExportShareView.swift

//
//  CSVExportShareView.swift
//  CryptoSavingsTracker
//

import SwiftUI

#Preview {
    CSVExportShareView(fileURLs: [
        URL(fileURLWithPath: "/tmp/goals.csv"),
        URL(fileURLWithPath: "/tmp/assets.csv"),
        URL(fileURLWithPath: "/tmp/value_changes.csv")
    ])
}
