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
    private let plan: AppBootstrapPlan.TestHarnessPlan

    @State private var isReady: Bool

    init(
        plan: AppBootstrapPlan.TestHarnessPlan,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.plan = plan
        self.content = content
        self._isReady = State(initialValue: !plan.blocksRootContent)
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
            guard plan.blocksRootContent, !isReady else { return }

            if plan.shouldResetData {
                await CryptoSavingsTrackerApp.runUITestResetIfNeeded(context: modelContext)
            }

            if plan.shouldSeedGoals || plan.shouldSeedManyGoals {
                await CryptoSavingsTrackerApp.runUITestSeedIfNeeded(context: modelContext)
            }

            isReady = true
        }
    }
}
