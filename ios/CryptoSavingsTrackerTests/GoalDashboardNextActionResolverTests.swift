//
//  GoalDashboardNextActionResolverTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalDashboardNextActionResolverTests {
    private let resolver = GoalDashboardNextActionResolver()

    @Test("Resolver returns goal_paused state")
    func resolverGoalPaused() {
        let result = resolver.resolve(
            lifecycle: .paused,
            freshness: .fresh,
            hasAssets: true,
            hasContributionsThisMonth: true,
            forecastStatus: .onTrack,
            forecastConfidence: .high,
            overAllocated: false,
            lastSuccessfulRefreshAt: nil,
            reasonCode: nil
        )
        #expect(result.resolverState == .goalPaused)
        #expect(result.primaryCta.id == "resume_goal")
    }

    @Test("Resolver hard_error has diagnostics payload")
    func resolverHardErrorDiagnostics() {
        let now = Date()
        let result = resolver.resolve(
            lifecycle: .active,
            freshness: .hardError,
            hasAssets: true,
            hasContributionsThisMonth: true,
            forecastStatus: .onTrack,
            forecastConfidence: .high,
            overAllocated: false,
            lastSuccessfulRefreshAt: now,
            reasonCode: "network_timeout"
        )
        #expect(result.resolverState == .hardError)
        #expect(result.diagnostics != nil)
        #expect(result.diagnostics?.reasonCode == "network_timeout")
        #expect(result.diagnostics?.lastSuccessfulRefreshAt == now)
    }

    @Test("Resolver behind schedule has planning CTA")
    func resolverBehindSchedule() {
        let result = resolver.resolve(
            lifecycle: .active,
            freshness: .fresh,
            hasAssets: true,
            hasContributionsThisMonth: true,
            forecastStatus: .offTrack,
            forecastConfidence: .medium,
            overAllocated: false,
            lastSuccessfulRefreshAt: nil,
            reasonCode: nil
        )
        #expect(result.resolverState == .behindSchedule)
        #expect(result.primaryCta.id == "plan_this_month")
    }

    @Test("Resolver covers all contract states deterministically")
    func resolverCoversAllStates() {
        let base = ResolverInput(
            lifecycle: .active,
            freshness: .fresh,
            hasAssets: true,
            hasContributionsThisMonth: true,
            forecastStatus: .onTrack,
            forecastConfidence: .high,
            overAllocated: false
        )

        assertResolvedState(base.with(freshness: .hardError), .hardError)
        assertResolvedState(base.with(lifecycle: .finished), .goalFinishedOrArchived)
        assertResolvedState(base.with(lifecycle: .paused), .goalPaused)
        assertResolvedState(base.with(overAllocated: true), .overAllocated)
        assertResolvedState(base.with(hasAssets: false), .noAssets)
        assertResolvedState(base.with(hasContributionsThisMonth: false), .noContributions)
        assertResolvedState(base.with(freshness: .stale), .staleData)
        assertResolvedState(base.with(forecastStatus: .offTrack), .behindSchedule)
        assertResolvedState(base.with(forecastStatus: .onTrack, forecastConfidence: .low), .staleData)
        assertResolvedState(base, .onTrack)
    }

    @Test("At risk forecast does not auto-map to behind schedule")
    func resolverAtRiskStaysOnTrackPath() {
        let result = resolver.resolve(
            lifecycle: .active,
            freshness: .fresh,
            hasAssets: true,
            hasContributionsThisMonth: true,
            forecastStatus: .atRisk,
            forecastConfidence: .medium,
            overAllocated: false,
            lastSuccessfulRefreshAt: nil,
            reasonCode: nil
        )
        #expect(result.resolverState == .onTrack)
    }

    private func assertResolvedState(_ input: ResolverInput, _ expected: GoalDashboardNextActionResolverState) {
        let result = resolver.resolve(
            lifecycle: input.lifecycle,
            freshness: input.freshness,
            hasAssets: input.hasAssets,
            hasContributionsThisMonth: input.hasContributionsThisMonth,
            forecastStatus: input.forecastStatus,
            forecastConfidence: input.forecastConfidence,
            overAllocated: input.overAllocated,
            lastSuccessfulRefreshAt: nil,
            reasonCode: nil
        )
        #expect(result.resolverState == expected)
    }
}

private struct ResolverInput {
    let lifecycle: GoalDashboardLifecycleState
    let freshness: DataFreshnessState
    let hasAssets: Bool
    let hasContributionsThisMonth: Bool
    let forecastStatus: GoalDashboardRiskStatus?
    let forecastConfidence: GoalDashboardForecastConfidence?
    let overAllocated: Bool

    func with(
        lifecycle: GoalDashboardLifecycleState? = nil,
        freshness: DataFreshnessState? = nil,
        hasAssets: Bool? = nil,
        hasContributionsThisMonth: Bool? = nil,
        forecastStatus: GoalDashboardRiskStatus? = nil,
        forecastConfidence: GoalDashboardForecastConfidence? = nil,
        overAllocated: Bool? = nil
    ) -> ResolverInput {
        ResolverInput(
            lifecycle: lifecycle ?? self.lifecycle,
            freshness: freshness ?? self.freshness,
            hasAssets: hasAssets ?? self.hasAssets,
            hasContributionsThisMonth: hasContributionsThisMonth ?? self.hasContributionsThisMonth,
            forecastStatus: forecastStatus ?? self.forecastStatus,
            forecastConfidence: forecastConfidence ?? self.forecastConfidence,
            overAllocated: overAllocated ?? self.overAllocated
        )
    }
}
