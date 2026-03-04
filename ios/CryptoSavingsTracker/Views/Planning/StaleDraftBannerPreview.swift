// Extracted preview-only declarations for NAV003 policy compliance.
// Source: StaleDraftBanner.swift

//
//  StaleDraftBanner.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Unified Monthly Planning Architecture
//  Handles stale draft plans with pagination and clear action consequences
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#Preview("Stale Draft Banner") {
    let plans: [MonthlyPlan] = (0..<12).map { index in
        let plan = MonthlyPlan(
            goalId: UUID(),
            monthLabel: "2025-\(String(format: "%02d", index + 1))",
            requiredMonthly: Double.random(in: 500...2000),
            remainingAmount: Double.random(in: 5000...20000),
            monthsRemaining: Int.random(in: 1...12),
            currency: "USD",
            status: .onTrack,
            state: .draft
        )
        return plan
    }

    return VStack {
        StaleDraftBanner(
            stalePlans: plans,
            onMarkCompleted: { plan in
                print("Mark completed: \(plan.monthLabel)")
            },
            onMarkSkipped: { plan in
                print("Mark skipped: \(plan.monthLabel)")
            },
            onDelete: { plan in
                print("Delete: \(plan.monthLabel)")
            }
        )
        .padding()

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    #if os(macOS)
    .background(Color(NSColor.controlBackgroundColor))
    #else
    .background(Color(.systemBackground))
    #endif
}

#Preview("Single Stale Plan Row") {
    let plan = MonthlyPlan(
        goalId: UUID(),
        monthLabel: "2025-10",
        requiredMonthly: 1500,
        remainingAmount: 15000,
        monthsRemaining: 10,
        currency: "EUR",
        status: .onTrack,
        state: .draft
    )

    return StalePlanRow(
        plan: plan,
        onMarkCompleted: { print("Completed") },
        onMarkSkipped: { print("Skipped") },
        onDelete: { print("Deleted") }
    )
    .padding()
    .frame(width: 500)
    #if os(macOS)
    .background(Color(NSColor.controlBackgroundColor))
    #else
    .background(Color(.systemBackground))
    #endif
}
