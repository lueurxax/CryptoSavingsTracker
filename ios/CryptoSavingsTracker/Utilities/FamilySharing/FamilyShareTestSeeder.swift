//
//  FamilyShareTestSeeder.swift
//  CryptoSavingsTracker
//

import Foundation

enum FamilyShareTestScenario: String, CaseIterable, Sendable {
    case ownerNotShared = "owner_not_shared"
    case ownerSharedActive = "owner_shared_active"
    case inviteeActive = "invitee_active"
    case inviteeEmpty = "invitee_empty"
    case inviteeStale = "invitee_stale"
    case inviteeRevoked = "invitee_revoked"
    case inviteeRemoved = "invitee_removed"
    case inviteeUnavailable = "invitee_unavailable"
}

struct FamilyShareTestSeeder {
    let registry: FamilyShareNamespaceRegistry

    init(registry: FamilyShareNamespaceRegistry? = nil) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
    }

    @MainActor
    func seed(_ scenario: FamilyShareTestScenario, namespaceID: FamilyShareNamespaceID) throws {
        try registry.seed(Self.makeSeed(for: scenario, namespaceID: namespaceID))
    }

    @MainActor
    func reset(namespaceID: FamilyShareNamespaceID) {
        registry.purge(namespaceID: namespaceID)
    }

    @MainActor
    static func makeInMemoryRegistrySeeded(
        with scenario: FamilyShareTestScenario,
        namespaceID: FamilyShareNamespaceID
    ) throws -> FamilyShareNamespaceRegistry {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        try FamilyShareTestSeeder(registry: registry).seed(scenario, namespaceID: namespaceID)
        return registry
    }

    static func makeSeed(for scenario: FamilyShareTestScenario, namespaceID: FamilyShareNamespaceID) -> FamilyShareSeededNamespaceState {
        switch scenario {
        case .ownerNotShared:
            return FamilyShareSeededNamespaceState(
                ownerDisplayName: namespaceID.ownerID,
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: namespaceID,
                    lifecycleState: .notShared,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "No family share is active yet.",
                    primaryActionCopy: "Share with Family"
                ),
                inviteeState: nil,
                projectionPayload: nil
            )
        case .ownerSharedActive:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive)
        case .inviteeActive:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive)
        case .inviteeEmpty:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive, goalCount: 0, lifecycleState: .emptySharedDataset, primaryAction: "Retry")
        case .inviteeStale:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive, lifecycleState: .stale, title: "This shared view may be out of date", primaryAction: "Retry Refresh")
        case .inviteeRevoked:
            return activeSeed(namespaceID: namespaceID, ownerState: .revoked, lifecycleState: .revoked, title: "Access revoked by owner", primaryAction: "Ask owner to re-share")
        case .inviteeRemoved:
            return activeSeed(namespaceID: namespaceID, ownerState: .revoked, lifecycleState: .removedOrNoLongerShared, title: "Shared goals no longer available", primaryAction: "Dismiss")
        case .inviteeUnavailable:
            return activeSeed(namespaceID: namespaceID, ownerState: .shareFailed, lifecycleState: .temporarilyUnavailable, title: "Shared goals temporarily unavailable", primaryAction: "Retry")
        }
    }

    private static func activeSeed(
        namespaceID: FamilyShareNamespaceID,
        ownerState: FamilyShareOwnerLifecycleState,
        goalCount: Int = 2,
        lifecycleState: FamilyShareLifecycleState = .active,
        title: String = "Read-only shared by Family",
        primaryAction: String = "Retry"
    ) -> FamilyShareSeededNamespaceState {
        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: "Family",
            lifecycleState: lifecycleState,
            goalCount: goalCount,
            lastUpdatedAt: Date(),
            asOfCopy: "As of \(Date().formatted(date: .abbreviated, time: .shortened))",
            titleCopy: title,
            messageCopy: lifecycleState == .active ? "Shared goals are read-only." : "This shared dataset needs attention.",
            primaryActionCopy: primaryAction,
            isReadOnly: true
        )

        let ownerViewState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: ownerState,
            participantCount: ownerState == .sharedActive ? 1 : 0,
            pendingParticipantCount: ownerState == .invitePending ? 1 : 0,
            activeParticipantCount: ownerState == .sharedActive ? 1 : 0,
            revokedParticipantCount: ownerState == .revoked ? 1 : 0,
            failedParticipantCount: ownerState == .shareFailed ? 1 : 0,
            summaryCopy: "Family sharing state seeded for tests.",
            primaryActionCopy: ownerState == .notShared ? "Share with Family" : "Manage Participants"
        )

        let payload = goalCount > 0 ? FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: "Family",
            schemaVersion: FamilyShareCacheSchema.currentVersion,
            projectionVersion: 1,
            activeProjectionVersion: 1,
            freshnessStateRawValue: lifecycleState.rawValue,
            lifecycleStateRawValue: ownerState.rawValue,
            publishedAt: Date(),
            lastReconciledAt: Date(),
            lastRefreshAttemptAt: Date(),
            lastRefreshErrorCode: lifecycleState == .temporarilyUnavailable ? "shared_database_unavailable" : nil,
            lastRefreshErrorMessage: lifecycleState == .temporarilyUnavailable ? "Shared goals temporarily unavailable." : nil,
            summaryTitle: "Shared Goals",
            summaryCopy: "Read-only shared dataset seeded for tests.",
            participantCount: ownerViewState.participantCount,
            pendingParticipantCount: ownerViewState.pendingParticipantCount,
            revokedParticipantCount: ownerViewState.revokedParticipantCount,
            goals: (1...goalCount).map { index in
                FamilyShareProjectedGoalPayload(
                    id: "\(namespaceID.namespaceKey)-goal-\(index)",
                    namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: "Family",
                    goalID: "goal-\(index)",
                    goalName: "Shared Goal \(index)",
                    goalEmoji: index == 1 ? "🎯" : "💰",
                    currency: "USD",
                    targetAmount: Decimal(1000 * index),
                    currentAmount: Decimal(250 * index),
                    progressRatio: Double(index) / Double(goalCount + 1),
                    deadline: Calendar.current.date(byAdding: .month, value: index, to: Date()) ?? Date(),
                    goalStatusRawValue: "active",
                    forecastStateRawValue: "high",
                    freshnessStateRawValue: lifecycleState.rawValue,
                    lastUpdatedAt: Date(),
                    summaryCopy: "Goal \(index) remains read-only.",
                    sortIndex: index
                )
            },
            ownerSections: [
                FamilyShareOwnerSectionPayload(
                    id: "\(namespaceID.namespaceKey)-section-1",
                    namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: "Family",
                    goalCount: goalCount,
                    freshnessStateRawValue: lifecycleState.rawValue,
                    sortIndex: 1,
                    inlineChipCopy: "Shared by Family"
                )
            ]
        ) : nil

        return FamilyShareSeededNamespaceState(
            ownerDisplayName: "Family",
            ownerState: ownerViewState,
            inviteeState: inviteeState,
            projectionPayload: payload
        )
    }
}
