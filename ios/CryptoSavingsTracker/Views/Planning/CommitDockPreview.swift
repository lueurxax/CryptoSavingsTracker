// Extracted preview-only declarations for NAV003 policy compliance.
// Source: CommitDock.swift

import SwiftUI
#if os(iOS)
import UIKit
#endif

#Preview("CommitDock — Expanded") {
    VStack {
        Spacer()
        CommitDock(
            phase: .expanded,
            showConfirmation: .constant(false),
            planningMonthLabel: "2026-03"
        )
    }
}

#Preview("CommitDock — Collapsed") {
    VStack {
        Spacer()
        CommitDock(
            phase: .collapsed,
            showConfirmation: .constant(false),
            planningMonthLabel: "2026-03"
        )
    }
}
