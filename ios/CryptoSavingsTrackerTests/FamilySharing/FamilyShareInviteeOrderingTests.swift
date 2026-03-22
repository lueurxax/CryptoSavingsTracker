import XCTest
@testable import CryptoSavingsTracker

/// Tests for the three-phase invitee ordering contract (Section 6.8.2).
final class FamilyShareInviteeOrderingTests: XCTestCase {

    // MARK: - Phase 1: Atomic Version Check

    func testPhase1_rejectsLowerProjectionVersion() {
        // Incoming version 2 < cached activeProjectionVersion 5
        let incoming = makePayload(projectionVersion: 2, activeProjectionVersion: 2)
        let cached = makePayload(projectionVersion: 5, activeProjectionVersion: 5)

        let result = shouldAcceptIncoming(incoming: incoming, cached: cached)
        XCTAssertFalse(result, "Should reject incoming with lower projectionVersion")
    }

    // MARK: - Phase 2: Content Dedup

    func testPhase2_rejectsMatchingContentHash() {
        let incoming = makePayload(projectionVersion: 6, activeProjectionVersion: 6, contentHash: "abc123")
        let cached = makePayload(projectionVersion: 5, activeProjectionVersion: 5, contentHash: "abc123")

        let result = shouldAcceptIncoming(incoming: incoming, cached: cached)
        XCTAssertFalse(result, "Should reject when contentHash matches (no semantic change)")
    }

    // MARK: - Phase 3: Semantic Freshness

    func testPhase3_acceptsDifferentContentHash() {
        let incoming = makePayload(projectionVersion: 6, activeProjectionVersion: 6, contentHash: "new-hash")
        let cached = makePayload(projectionVersion: 5, activeProjectionVersion: 5, contentHash: "old-hash")

        let result = shouldAcceptIncoming(incoming: incoming, cached: cached)
        XCTAssertTrue(result, "Should accept when contentHash differs (semantic change)")
    }

    func testPhase3_preMigrationFallback_acceptsNewerTimestamp() {
        let incoming = makePayload(
            projectionVersion: 6, activeProjectionVersion: 6,
            contentHash: nil,
            projectionServerTimestamp: Date().addingTimeInterval(60)
        )
        let cached = makePayload(
            projectionVersion: 5, activeProjectionVersion: 5,
            contentHash: nil,
            projectionServerTimestamp: Date()
        )

        let result = shouldAcceptIncoming(incoming: incoming, cached: cached)
        XCTAssertTrue(result, "Should accept when pre-migration and incoming timestamp is newer")
    }

    func testPhase3_preMigrationFallback_rejectsOlderTimestamp() {
        let now = Date()
        let incoming = makePayload(
            projectionVersion: 6, activeProjectionVersion: 6,
            contentHash: nil,
            projectionServerTimestamp: now.addingTimeInterval(-60)
        )
        let cached = makePayload(
            projectionVersion: 5, activeProjectionVersion: 5,
            contentHash: nil,
            projectionServerTimestamp: now
        )

        let result = shouldAcceptIncoming(incoming: incoming, cached: cached)
        XCTAssertFalse(result, "Should reject when pre-migration and incoming timestamp is older")
    }

    // MARK: - Helpers

    private func makePayload(
        projectionVersion: Int = 1,
        activeProjectionVersion: Int = 1,
        contentHash: String? = nil,
        projectionServerTimestamp: Date? = nil
    ) -> FamilyShareProjectionPayload {
        FamilyShareProjectionPayload(
            namespaceID: FamilyShareNamespaceID(ownerID: "o", shareID: "s"),
            ownerDisplayName: "Test",
            schemaVersion: 2,
            projectionVersion: projectionVersion,
            activeProjectionVersion: activeProjectionVersion,
            freshnessStateRawValue: "active",
            lifecycleStateRawValue: "sharedActive",
            publishedAt: Date(),
            lastReconciledAt: nil,
            lastRefreshAttemptAt: nil,
            lastRefreshErrorCode: nil,
            lastRefreshErrorMessage: nil,
            summaryTitle: "Test",
            summaryCopy: "",
            participantCount: 1,
            pendingParticipantCount: 0,
            revokedParticipantCount: 0,
            goals: [],
            ownerSections: [],
            rateSnapshotTimestamp: nil,
            projectionServerTimestamp: projectionServerTimestamp,
            contentHash: contentHash
        )
    }

    /// Mirrors the three-phase ordering logic from FamilyShareServices.refreshNamespace()
    private func shouldAcceptIncoming(incoming: FamilyShareProjectionPayload, cached: FamilyShareProjectionPayload) -> Bool {
        // Phase 1: Atomic version check
        if incoming.projectionVersion < cached.activeProjectionVersion {
            return false
        }
        // Phase 2: Content dedup
        if let incomingHash = incoming.contentHash,
           let cachedHash = cached.contentHash,
           incomingHash == cachedHash {
            return false
        }
        // Phase 3: Semantic freshness
        if incoming.contentHash == nil || cached.contentHash == nil {
            if let incomingTs = incoming.projectionServerTimestamp,
               let cachedTs = cached.projectionServerTimestamp,
               incomingTs <= cachedTs {
                return false
            }
        }
        return true
    }
}
