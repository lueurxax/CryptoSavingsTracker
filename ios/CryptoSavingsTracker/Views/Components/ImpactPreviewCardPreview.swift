// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ImpactPreviewCard.swift

import SwiftUI

#Preview {
    VStack(spacing: 20) {
        // Positive change example
        ImpactPreviewCard(
            impact: GoalImpact(
                oldProgress: 0.45,
                newProgress: 0.60,
                oldDailyTarget: 75.0,
                newDailyTarget: 50.0,
                oldDaysRemaining: 120,
                newDaysRemaining: 150,
                oldTargetAmount: 5000,
                newTargetAmount: 5000,
                significantChange: true
            ),
            currency: "USD"
        )

        // Negative change example
        ImpactPreviewCard(
            impact: GoalImpact(
                oldProgress: 0.60,
                newProgress: 0.40,
                oldDailyTarget: 50.0,
                newDailyTarget: 100.0,
                oldDaysRemaining: 150,
                newDaysRemaining: 90,
                oldTargetAmount: 5000,
                newTargetAmount: 8000,
                significantChange: true
            ),
            currency: "USD"
        )
    }
    .padding()
}
