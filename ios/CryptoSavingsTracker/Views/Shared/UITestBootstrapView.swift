//
//  UITestBootstrapView.swift
//  CryptoSavingsTracker
//
//  Ensures UITEST_RESET_DATA / UITEST_* seeding completes before showing UI,
//  preventing cross-test contamination and race conditions during app launch.
//

import SwiftUI
import SwiftData

struct UITestBootstrapView<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    private let content: () -> Content
    private let isUITestRun: Bool

    @State private var isReady: Bool

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        let args = ProcessInfo.processInfo.arguments
        self.isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
        self._isReady = State(initialValue: !isUITestRun)
    }

    var body: some View {
        Group {
            if isReady {
                content()
            } else {
                ProgressView("Preparing test data…")
            }
        }
        .task {
            guard isUITestRun, !isReady else { return }
            await CryptoSavingsTrackerApp.runUITestResetIfNeeded(context: modelContext)
            await CryptoSavingsTrackerApp.runUITestSeedIfNeeded(context: modelContext)
            isReady = true
        }
    }
}

