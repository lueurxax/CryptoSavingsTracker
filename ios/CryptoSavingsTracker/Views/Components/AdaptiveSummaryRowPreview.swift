import SwiftUI

#Preview("Adaptive Summary Row") {
    List {
        Section("Regular") {
            AdaptiveSummaryRow(label: "Target", value: "12,500.00 USD")
            AdaptiveSummaryRow(label: "Suggested deposit", value: "125.00 USD")
        }

        Section("Compact fallback") {
            AdaptiveSummaryRow(
                label: "Deadline with a long localized label",
                value: "Apr 18, 2026 (42 days remaining)"
            )
        }
    }
}
