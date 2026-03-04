// Extracted preview-only declarations for NAV003 policy compliance.
// Source: HelpTooltip.swift

import SwiftUI

#Preview {
    VStack(spacing: 20) {
        Text("Current Total: $5,000")
            .helpTooltip(MetricTooltips.currentTotal)
        
        Text("Daily Target: $50")
            .helpTooltip(MetricTooltips.dailyTarget)
        
        Text("Days Remaining: 45")
            .helpTooltip(MetricTooltips.daysRemaining)
    }
    .padding()
}
