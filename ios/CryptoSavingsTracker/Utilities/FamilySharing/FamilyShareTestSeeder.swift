//
//  FamilyShareTestSeeder.swift
//  CryptoSavingsTracker
//

import Foundation

enum FamilyShareTestScenario: String, CaseIterable, Sendable {
    case ownerNotShared = "owner_not_shared"
    case ownerSharedActive = "owner_shared_active"
    case inviteePending = "invitee_pending"
    case inviteeActive = "invitee_active"
    case inviteeBlockedOwner = "invitee_blocked_owner"
    case inviteeMultiOwner = "invitee_multi_owner"
    case inviteeMultiOwnerUnresolved = "invitee_multi_owner_unresolved"
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
        if scenario == .inviteeMultiOwner {
            try registry.seed(Self.makeSeed(for: .inviteeActive, namespaceID: namespaceID))
            let secondaryNamespaceID = FamilyShareNamespaceID(
                ownerID: namespaceID.ownerID + "-coowner",
                shareID: namespaceID.shareID + "-secondary"
            )
            try registry.seed(Self.makeSecondaryOwnerSeed(namespaceID: secondaryNamespaceID))
            return
        }

        if scenario == .inviteeMultiOwnerUnresolved {
            try registry.seed(Self.makeBlockedOwnerSeed(namespaceID: namespaceID, rawOwnerDisplayName: "iPhone"))
            let secondaryNamespaceID = FamilyShareNamespaceID(
                ownerID: namespaceID.ownerID + "-blocked",
                shareID: namespaceID.shareID + "-secondary"
            )
            try registry.seed(Self.makeBlockedOwnerSeed(namespaceID: secondaryNamespaceID, rawOwnerDisplayName: "iPad"))
            return
        }

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
        case .inviteePending:
            return activeSeed(
                namespaceID: namespaceID,
                ownerState: .invitePending,
                lifecycleState: .invitePendingAcceptance,
                title: "Invitation pending",
                primaryAction: "Accept"
            )
        case .inviteeActive:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive)
        case .inviteeBlockedOwner:
            return makeRedesignedBlockedOwnerSeed(namespaceID: namespaceID)
        case .inviteeMultiOwner:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive)
        case .inviteeMultiOwnerUnresolved:
            return makeBlockedOwnerSeed(namespaceID: namespaceID, rawOwnerDisplayName: "iPhone")
        case .inviteeEmpty:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive, goalCount: 0, lifecycleState: .emptySharedDataset, title: "No shared items yet", primaryAction: "Retry")
        case .inviteeStale:
            return activeSeed(namespaceID: namespaceID, ownerState: .sharedActive, lifecycleState: .stale, title: "Shared with You", primaryAction: "Retry Refresh")
        case .inviteeRevoked:
            return activeSeed(namespaceID: namespaceID, ownerState: .revoked, lifecycleState: .revoked, title: "Access revoked", primaryAction: "Ask owner to re-share")
        case .inviteeRemoved:
            return activeSeed(namespaceID: namespaceID, ownerState: .revoked, lifecycleState: .removedOrNoLongerShared, title: "No longer shared", primaryAction: "Dismiss")
        case .inviteeUnavailable:
            return activeSeed(namespaceID: namespaceID, ownerState: .shareFailed, lifecycleState: .temporarilyUnavailable, title: "Shared with You", primaryAction: "Retry")
        }
    }

    private static func activeSeed(
        namespaceID: FamilyShareNamespaceID,
        ownerState: FamilyShareOwnerLifecycleState,
        goalCount: Int = 3,
        lifecycleState: FamilyShareLifecycleState = .active,
        title: String = "Shared with You",
        primaryAction: String = "Refresh",
        ownerDisplayName: String = "Alex"
    ) -> FamilyShareSeededNamespaceState {
        let resolvedOwnerDisplayName = normalizedOwnerDisplayName(from: ownerDisplayName)
        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: resolvedOwnerDisplayName,
            lifecycleState: lifecycleState,
            goalCount: goalCount,
            lastUpdatedAt: Date(),
            asOfCopy: "As of \(Date().formatted(date: .abbreviated, time: .shortened))",
            titleCopy: title,
            messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: lifecycleState,
                fallback: inviteeMessageCopy(for: lifecycleState)
            ),
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
            summaryCopy: ownerState == .sharedActive ? "1 participant has active read-only access." : "Family sharing state seeded for tests.",
            primaryActionCopy: ownerState == .notShared ? "Share with Family" : "Manage Participants"
        )

        let payload = goalCount > 0 ? FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: resolvedOwnerDisplayName,
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
            summaryTitle: "Shared with You",
            summaryCopy: "Read-only shared goals grouped by owner.",
            participantCount: ownerViewState.participantCount,
            pendingParticipantCount: ownerViewState.pendingParticipantCount,
            revokedParticipantCount: ownerViewState.revokedParticipantCount,
            goals: (1...goalCount).map { index in
                let status = redesignedGoalStatus(for: index)
                return FamilyShareProjectedGoalPayload(
                    id: "\(namespaceID.namespaceKey)-goal-\(index)",
                    namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: resolvedOwnerDisplayName,
                    goalID: "goal-\(index)",
                    goalName: "Shared Goal \(index)",
                    goalEmoji: index == 1 ? "🎯" : "💰",
                    currency: "USD",
                    targetAmount: Decimal(1000 * index),
                    currentAmount: Decimal(250 * index),
                    progressRatio: Double(index) / Double(goalCount + 1),
                    deadline: Calendar.current.date(byAdding: .month, value: index, to: Date()) ?? Date(),
                    goalStatusRawValue: status,
                    forecastStateRawValue: "high",
                    freshnessStateRawValue: lifecycleState.rawValue,
                    lastUpdatedAt: Date(),
                    summaryCopy: redesignedGoalSummaryCopy(for: status, index: index),
                    sortIndex: index
                )
            },
            ownerSections: [
                FamilyShareOwnerSectionPayload(
                    id: "\(namespaceID.namespaceKey)-section-1",
                    namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: resolvedOwnerDisplayName,
                    goalCount: goalCount,
                    freshnessStateRawValue: lifecycleState.rawValue,
                    sortIndex: 1,
                    inlineChipCopy: ""
                )
            ]
        ) : nil

        return FamilyShareSeededNamespaceState(
            ownerDisplayName: resolvedOwnerDisplayName,
            ownerState: ownerViewState,
            inviteeState: inviteeState,
            projectionPayload: payload
        )
    }

    private static func makeSecondaryOwnerSeed(namespaceID: FamilyShareNamespaceID) -> FamilyShareSeededNamespaceState {
        let ownerDisplayName = "Jordan"
        let goals = [
            FamilyShareProjectedGoalPayload(
                id: "\(namespaceID.namespaceKey)-goal-1",
                namespaceID: namespaceID,
                ownerID: namespaceID.ownerID,
                ownerDisplayName: ownerDisplayName,
                goalID: "goal-1",
                goalName: "Vacation Fund",
                goalEmoji: "🌴",
                currency: "USD",
                targetAmount: 3200,
                currentAmount: 1840,
                progressRatio: 0.575,
                deadline: Calendar.current.date(byAdding: .month, value: 4, to: .now) ?? .now,
                goalStatusRawValue: "active",
                forecastStateRawValue: "on_track",
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lastUpdatedAt: .now,
                    summaryCopy: redesignedGoalSummaryCopy(for: "active", index: 1),
                sortIndex: 0
            )
        ]

        return FamilyShareSeededNamespaceState(
            ownerDisplayName: ownerDisplayName,
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .sharedActive,
                participantCount: 1,
                pendingParticipantCount: 0,
                activeParticipantCount: 1,
                revokedParticipantCount: 0,
                failedParticipantCount: 0,
                summaryCopy: "Family sharing state seeded for tests.",
                primaryActionCopy: "Manage Participants"
            ),
            inviteeState: FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: ownerDisplayName,
                lifecycleState: .active,
                goalCount: goals.count,
                lastUpdatedAt: .now,
                asOfCopy: "As of \(Date().formatted(date: .abbreviated, time: .shortened))",
                titleCopy: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                    lifecycleState: .active,
                    fallback: "Goals are grouped by owner and stay read-only."
                ),
                primaryActionCopy: "Refresh",
                isReadOnly: true
            ),
            projectionPayload: FamilyShareProjectionPayload(
                namespaceID: namespaceID,
                ownerDisplayName: FamilyShareOwnerIdentityResolver.resolve(displayName: ownerDisplayName).displayName,
                schemaVersion: FamilyShareCacheSchema.currentVersion,
                projectionVersion: 1,
                activeProjectionVersion: 1,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
                publishedAt: .now,
                lastReconciledAt: .now,
                lastRefreshAttemptAt: .now,
                lastRefreshErrorCode: nil,
                lastRefreshErrorMessage: nil,
                summaryTitle: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                summaryCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                    lifecycleState: .active,
                    fallback: "Read-only shared goals grouped by owner."
                ),
                participantCount: 1,
                pendingParticipantCount: 0,
                revokedParticipantCount: 0,
                goals: goals,
                ownerSections: [
                    FamilyShareOwnerSectionPayload(
                        id: "\(namespaceID.namespaceKey)-section-1",
                        namespaceID: namespaceID,
                    ownerID: namespaceID.ownerID,
                    ownerDisplayName: FamilyShareOwnerIdentityResolver.resolve(displayName: ownerDisplayName).displayName,
                        goalCount: 1,
                        freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                        sortIndex: 1,
                        inlineChipCopy: ""
                    )
                ]
            )
        )
    }

    static func normalizedOwnerDisplayName(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = ["iphone", "ipad", "macbook", "unknown device", "unknown"]
        if blocked.contains(where: { trimmed.lowercased().contains($0) }) {
            return "Family member"
        }
        return trimmed.isEmpty ? "Family member" : trimmed
    }

    static func makeRedesignedBlockedOwnerSeed(namespaceID: FamilyShareNamespaceID) -> FamilyShareSeededNamespaceState {
        let ownerDisplayName = normalizedOwnerDisplayName(from: "iPhone")
        return redesignedSeed(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            ownerState: .sharedActive,
            lifecycleState: .active,
            title: "Shared with You",
            primaryAction: "Refresh"
        )
    }

    static func makeBlockedOwnerSeed(
        namespaceID: FamilyShareNamespaceID,
        rawOwnerDisplayName: String
    ) -> FamilyShareSeededNamespaceState {
        redesignedSeed(
            namespaceID: namespaceID,
            ownerDisplayName: normalizedOwnerDisplayName(from: rawOwnerDisplayName),
            ownerState: .sharedActive,
            lifecycleState: .active,
            title: "Shared with You",
            primaryAction: "Refresh"
        )
    }

    static func makeRedesignedMixedLifecycleSeed(namespaceID: FamilyShareNamespaceID, ownerDisplayName: String = "Alex") -> FamilyShareSeededNamespaceState {
        redesignedSeed(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            ownerState: .sharedActive,
            lifecycleState: .active,
            title: "Shared with You",
            primaryAction: "Refresh"
        )
    }

    private static func redesignedSeed(
        namespaceID: FamilyShareNamespaceID,
        ownerDisplayName: String,
        ownerState: FamilyShareOwnerLifecycleState,
        lifecycleState: FamilyShareLifecycleState,
        title: String,
        primaryAction: String
    ) -> FamilyShareSeededNamespaceState {
        activeSeed(
            namespaceID: namespaceID,
            ownerState: ownerState,
            goalCount: 3,
            lifecycleState: lifecycleState,
            title: title,
            primaryAction: primaryAction,
            ownerDisplayName: ownerDisplayName
        )
    }

    private static func redesignedGoalStatus(for index: Int) -> String {
        switch index {
        case 1: return "active"
        case 2: return "achieved"
        default: return "expired"
        }
    }

    private static func redesignedGoalSummaryCopy(for status: String, index: Int) -> String {
        switch status {
        case "active":
            return "Goal \(index) is still in progress."
        case "achieved":
            return "Goal \(index) was achieved earlier this month."
        case "expired":
            return "Goal \(index) expired before full funding."
        default:
            return "Goal \(index) remains read-only."
        }
    }

    private static func inviteeMessageCopy(for lifecycleState: FamilyShareLifecycleState) -> String {
        switch lifecycleState {
        case .active:
            return "Goals are grouped by owner and stay read-only."
        case .invitePendingAcceptance:
            return "The invitation is waiting for acceptance."
        case .emptySharedDataset:
            return "No shared items are visible yet."
        case .stale:
            return "The shared cache may be out of date."
        case .temporarilyUnavailable:
            return "This shared dataset is temporarily unavailable right now."
        case .revoked:
            return "Access was removed by the owner."
        case .removedOrNoLongerShared:
            return "This shared dataset is no longer available."
        }
    }
}
