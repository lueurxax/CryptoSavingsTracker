import Foundation
import Testing
@testable import CryptoSavingsTracker

struct BalanceStateTests {
    @Test("Public crypto tracking vocabulary matches retained proposal states")
    func publicCryptoTrackingVocabulary() {
        #expect(BalanceState.CryptoTrackingStatus.allCases.map(\.title) == [
            "Connecting",
            "Syncing",
            "Connected",
            "Stale",
            "Needs Attention"
        ])
    }

    @Test("Balance state maps retained crypto tracking statuses deterministically")
    func retainedCryptoTrackingStatusMapping() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            BalanceState.loading.publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: false
            ) == .connecting
        )
        #expect(
            BalanceState.loading.publicCryptoTrackingStatus(
                isRefreshing: true,
                hasRetainedValue: true
            ) == .syncing
        )
        #expect(
            BalanceState.loaded(balance: 1.25, isCached: false, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .connected
        )
        #expect(
            BalanceState.loaded(balance: 1.25, isCached: true, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .stale
        )
        #expect(
            BalanceState.error(message: "offline", cachedBalance: 1.25, lastUpdated: now).publicCryptoTrackingStatus(
                isRefreshing: false,
                hasRetainedValue: true
            ) == .needsAttention
        )
    }

    @Test("Needs attention copy preserves last successful value guidance")
    func needsAttentionCopyKeepsLastSuccessfulValueVisible() {
        let detail = BalanceState.error(
            message: "offline",
            cachedBalance: 0.42,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        ).publicTrackingStatusDetail(
            isRefreshing: false,
            hasRetainedValue: true
        )

        #expect(detail.contains("last successful"))
        #expect(detail.contains("visible"))
    }
}
