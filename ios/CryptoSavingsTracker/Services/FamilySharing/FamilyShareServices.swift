//
//  FamilyShareServices.swift
//  CryptoSavingsTracker
//

import Combine
import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CloudKit)
import CloudKit
#endif

protocol FamilyShareStateProviding {
    func seededState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareSeededNamespaceState?
    func inviteeState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareInviteeViewState?
    func ownerState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareOwnerViewState?
}

protocol FamilyShareInviteeStateProviding {
    func inviteeStates() async throws -> [FamilyShareInviteeViewState]
    func sharedInviteeProjection() async throws -> FamilyShareInviteeProjection
}

protocol FamilyShareProjectionPublishing {
    func publish(_ payload: FamilyShareProjectionPayload) async throws -> FamilySharePublicationResult
}

protocol FamilyShareOwnerSharingServicing {
    func scopePreview(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareScopePreviewSummary
    func ownerState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareOwnerViewState?
    func revoke(namespaceID: FamilyShareNamespaceID) async throws
}

protocol FamilyShareCacheMigrating {
    func ensureCompatible(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareCacheMigrationResult
}

protocol FamilyShareNamespaceManaging {
    func bootstrap(with state: FamilyShareSeededNamespaceState) async
    func refresh(with state: FamilyShareSeededNamespaceState) async
    func markAccepted() async
    func markFailed(reason: String?) async
    func markRevoked() async
    func stateSnapshot() async -> FamilyShareNamespaceActorSnapshot
}

protocol FamilyShareSceneAccepting: AnyObject {
    func acceptInvitation(_ metadata: CKShare.Metadata)

#if canImport(UIKit)
    func acceptPendingInvitation(from connectionOptions: UIScene.ConnectionOptions)
#endif
}

struct FamilySharePublicationResult: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let projectionVersion: Int
    let activeProjectionVersion: Int
    let goalCount: Int
    let ownerSectionCount: Int
    let publishedAt: Date

    /// Server-assigned timestamp from CKRecord.modificationDate.
    /// Used to populate `projectionServerTimestamp` for freshness ordering.
    let projectionServerTimestamp: Date?
}

struct FamilyShareProjectionOutboxItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let namespaceID: FamilyShareNamespaceID
    let projectionVersion: Int
    let enqueuedAt: Date
}

struct FamilyShareCacheMigrationResult: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let previousSchemaVersion: Int?
    let currentSchemaVersion: Int
    let didMigrate: Bool
    let requiresRebuild: Bool
    let quarantined: Bool
}

struct FamilyShareNamespaceActorSnapshot: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let acceptanceOutcome: FamilyShareAcceptanceOutcome
    let lifecycleState: FamilyShareLifecycleState
    let ownerState: FamilyShareOwnerViewState
    let inviteeState: FamilyShareInviteeViewState?
    let projectionPayload: FamilyShareProjectionPayload?
}

enum FamilyShareCacheMigrationError: Error, LocalizedError, Sendable {
    case unsupportedFutureSchemaVersion(current: Int, required: Int)
    case unsupportedHistoricalSchemaVersion(current: Int, required: Int)
    case namespaceUnavailable

    var errorDescription: String? {
        switch self {
        case let .unsupportedFutureSchemaVersion(current, required):
            return "Namespace uses future schema version \(required); current supported version is \(current)."
        case let .unsupportedHistoricalSchemaVersion(current, required):
            return "Namespace schema version \(required) is below supported range beginning at \(current)."
        case .namespaceUnavailable:
            return "Family sharing namespace is unavailable."
        }
    }
}

actor FamilyShareNamespaceActor {
    let namespaceID: FamilyShareNamespaceID
    private var acceptanceOutcome: FamilyShareAcceptanceOutcome = .pending
    private var lifecycleState: FamilyShareLifecycleState = .invitePendingAcceptance
    private var ownerState: FamilyShareOwnerViewState
    private var inviteeState: FamilyShareInviteeViewState?
    private var projectionPayload: FamilyShareProjectionPayload?

    init(
        namespaceID: FamilyShareNamespaceID,
        ownerState: FamilyShareOwnerViewState,
        inviteeState: FamilyShareInviteeViewState? = nil,
        projectionPayload: FamilyShareProjectionPayload? = nil
    ) {
        self.namespaceID = namespaceID
        self.ownerState = ownerState
        self.inviteeState = inviteeState
        self.projectionPayload = projectionPayload
        if let inviteeState {
            lifecycleState = inviteeState.lifecycleState
            acceptanceOutcome = inviteeState.lifecycleState == .active ? .accepted : .pending
        }
    }

    func bootstrap(with state: FamilyShareSeededNamespaceState) async {
        ownerState = state.ownerState
        inviteeState = state.inviteeState
        projectionPayload = state.projectionPayload
        lifecycleState = state.inviteeState?.lifecycleState ?? .invitePendingAcceptance
        acceptanceOutcome = lifecycleState == .active ? .accepted : .pending
    }

    func refresh(with state: FamilyShareSeededNamespaceState) async {
        await bootstrap(with: state)
    }

    func markAccepted() async {
        acceptanceOutcome = .accepted
        lifecycleState = .active
    }

    func markFailed(reason: String? = nil) async {
        acceptanceOutcome = .failed
        lifecycleState = .temporarilyUnavailable
    }

    func markRevoked() async {
        acceptanceOutcome = .rejected
        lifecycleState = .revoked
    }

    func stateSnapshot() async -> FamilyShareNamespaceActorSnapshot {
        FamilyShareNamespaceActorSnapshot(
            namespaceID: namespaceID,
            acceptanceOutcome: acceptanceOutcome,
            lifecycleState: lifecycleState,
            ownerState: ownerState,
            inviteeState: inviteeState,
            projectionPayload: projectionPayload
        )
    }
}

actor FamilyShareNamespaceExecutionHub {
    private var actors: [String: FamilyShareNamespaceActor] = [:]

    func bootstrap(with state: FamilyShareSeededNamespaceState) async {
        let actor = actor(for: state)
        await actor.bootstrap(with: state)
    }

    func refresh(with state: FamilyShareSeededNamespaceState) async {
        let actor = actor(for: state)
        await actor.refresh(with: state)
    }

    func markAccepted(with state: FamilyShareSeededNamespaceState) async {
        let actor = actor(for: state)
        await actor.bootstrap(with: state)
        await actor.markAccepted()
    }

    func markFailed(with state: FamilyShareSeededNamespaceState, reason: String?) async {
        let actor = actor(for: state)
        await actor.bootstrap(with: state)
        await actor.markFailed(reason: reason)
    }

    func markRevoked(with state: FamilyShareSeededNamespaceState) async {
        let actor = actor(for: state)
        await actor.bootstrap(with: state)
        await actor.markRevoked()
    }

    func reset() {
        actors.removeAll()
    }

    func stateSnapshot(for namespaceID: FamilyShareNamespaceID) async -> FamilyShareNamespaceActorSnapshot? {
        guard let actor = actors[namespaceID.namespaceKey] else { return nil }
        return await actor.stateSnapshot()
    }

    private func actor(for state: FamilyShareSeededNamespaceState) -> FamilyShareNamespaceActor {
        let namespaceID = state.ownerState.namespaceID
        if let existing = actors[namespaceID.namespaceKey] {
            return existing
        }
        let created = FamilyShareNamespaceActor(
            namespaceID: namespaceID,
            ownerState: state.ownerState,
            inviteeState: state.inviteeState,
            projectionPayload: state.projectionPayload
        )
        actors[namespaceID.namespaceKey] = created
        return created
    }
}

@MainActor
final class DefaultFamilyShareStateProvider: FamilyShareStateProviding, FamilyShareInviteeStateProviding {
    private let registry: FamilyShareNamespaceRegistry

    init(registry: FamilyShareNamespaceRegistry? = nil) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
    }

    func seededState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareSeededNamespaceState? {
        try registry.seededState(for: namespaceID)
    }

    func inviteeState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareInviteeViewState? {
        try registry.snapshot(for: namespaceID)
    }

    func ownerState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareOwnerViewState? {
        try registry.seededState(for: namespaceID)?.ownerState
    }

    func inviteeStates() async throws -> [FamilyShareInviteeViewState] {
        try registry
            .seededStates()
            .compactMap(\.inviteeState)
            .sorted { lhs, rhs in
                let ownerSort = lhs.ownerDisplayName.localizedCaseInsensitiveCompare(rhs.ownerDisplayName)
                if ownerSort != .orderedSame {
                    return ownerSort == .orderedAscending
                }
                if lhs.namespaceID.ownerID != rhs.namespaceID.ownerID {
                    return lhs.namespaceID.ownerID < rhs.namespaceID.ownerID
                }
                return lhs.namespaceID.shareID < rhs.namespaceID.shareID
            }
    }

    func sharedInviteeProjection() async throws -> FamilyShareInviteeProjection {
        let sections = try registry
            .seededStates()
            .map(\.canonicalInviteeProjection)
            .flatMap(\.sections)
            .sorted { lhs, rhs in
                let ownerSort = lhs.ownerIdentity.displayName.localizedCaseInsensitiveCompare(rhs.ownerIdentity.displayName)
                if ownerSort != .orderedSame {
                    return ownerSort == .orderedAscending
                }
                if lhs.namespaceID.ownerID != rhs.namespaceID.ownerID {
                    return lhs.namespaceID.ownerID < rhs.namespaceID.ownerID
                }
                return lhs.namespaceID.shareID < rhs.namespaceID.shareID
            }
        let disambiguatedSections = FamilyShareOwnerIdentityResolver.disambiguatedSectionOwnerIdentities(for: sections)

        return FamilyShareInviteeProjection(
            entryTitle: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
            entrySummary: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: .active
            ),
            sections: disambiguatedSections
        )
    }
}

@MainActor
final class FamilyShareAccessGuard: FamilyShareAccessChecking {
    private let registry: FamilyShareNamespaceRegistry

    init(registry: FamilyShareNamespaceRegistry) {
        self.registry = registry
    }

    func isSharedGoalID(_ goalID: UUID) -> Bool {
        let goalIDString = goalID.uuidString
        for namespaceID in registry.allNamespaceIDs() {
            if let seededState = try? registry.seededState(for: namespaceID),
               seededState.projectionPayload?.goals.contains(where: { $0.goalID == goalIDString }) == true {
                return true
            }
        }
        return false
    }

    func assertOwnerWritable(goalID: UUID) throws {
        guard isSharedGoalID(goalID) == false else {
            throw FamilyShareReadOnlyAccessError.sharedGoalReadOnly
        }
    }

    func assertOwnerWritable(goal: Goal) throws {
        try assertOwnerWritable(goalID: goal.id)
    }

    func assertOwnerWritable(asset: Asset) throws {
        let goalIDs = (asset.allocations ?? []).compactMap(\.goal?.id)
        if let sharedGoalID = goalIDs.first(where: { isSharedGoalID($0) }) {
            try assertOwnerWritable(goalID: sharedGoalID)
        }
    }

    func assertOwnerWritable(transaction: Transaction) throws {
        if let asset = transaction.asset {
            try assertOwnerWritable(asset: asset)
        }
    }

    func assertOwnerWritable(plan: MonthlyPlan) throws {
        try assertOwnerWritable(goalID: plan.goalId)
    }

    func assertOwnerWritable(plans: [MonthlyPlan]) throws {
        if let sharedPlan = plans.first(where: { isSharedGoalID($0.goalId) }) {
            try assertOwnerWritable(plan: sharedPlan)
        }
    }

    func assertOwnerWritable(goals: [Goal]) throws {
        if let sharedGoal = goals.first(where: { isSharedGoalID($0.id) }) {
            try assertOwnerWritable(goal: sharedGoal)
        }
    }
}

@MainActor
final class DefaultFamilyShareProjectionPublisher: FamilyShareProjectionPublishing {
    private let registry: FamilyShareNamespaceRegistry
    private let cloudSync: FamilyShareCloudSyncing?
    private let telemetry: FamilyShareTelemetryTracking

    init(
        registry: FamilyShareNamespaceRegistry? = nil,
        cloudSync: FamilyShareCloudSyncing? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker()
    ) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
        self.cloudSync = cloudSync
        self.telemetry = telemetry
    }

    func publish(_ payload: FamilyShareProjectionPayload) async throws -> FamilySharePublicationResult {
        let activeParticipantCount = max(0, payload.participantCount - payload.pendingParticipantCount - payload.revokedParticipantCount)
        let ownerLifecycleState: FamilyShareOwnerLifecycleState = payload.pendingParticipantCount > 0 && activeParticipantCount == 0
            ? .invitePending
            : .sharedActive
        let ownerState = FamilyShareOwnerViewState(
            namespaceID: payload.namespaceID,
            lifecycleState: ownerLifecycleState,
            participantCount: payload.participantCount,
            pendingParticipantCount: payload.pendingParticipantCount,
            activeParticipantCount: activeParticipantCount,
            revokedParticipantCount: payload.revokedParticipantCount,
            failedParticipantCount: 0,
            summaryCopy: payload.summaryCopy,
            primaryActionCopy: "Manage Participants"
        )

        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: payload.namespaceID,
            ownerDisplayName: payload.ownerDisplayName,
            lifecycleState: FamilyShareLifecycleState(rawValue: payload.freshnessStateRawValue) ?? .active,
            goalCount: payload.goals.count,
            lastUpdatedAt: payload.publishedAt,
            asOfCopy: payload.publishedAt.map { "As of \($0.formatted(date: .abbreviated, time: .shortened))" },
            titleCopy: payload.summaryTitle,
            messageCopy: payload.summaryCopy,
            primaryActionCopy: "Retry Refresh",
            isReadOnly: true
        )

        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: payload.ownerDisplayName,
                ownerState: ownerState,
                inviteeState: inviteeState,
                projectionPayload: payload
            )
        )

        do {
            try await cloudSync?.publishProjection(payload)
        } catch {
            telemetry.track(
                .sharePublishFailed,
                payload: [
                    "namespace": payload.namespaceID.namespaceKey,
                    "reason": error.localizedDescription
                ]
            )
            throw error
        }

        // Capture server-assigned timestamp from CloudKit after publish
        let serverTimestamp = (cloudSync as? DefaultFamilyShareCloudKitStore)?.lastPublishServerTimestamp

        return FamilySharePublicationResult(
            namespaceID: payload.namespaceID,
            projectionVersion: payload.projectionVersion,
            activeProjectionVersion: payload.activeProjectionVersion,
            goalCount: payload.goals.count,
            ownerSectionCount: payload.ownerSections.count,
            publishedAt: payload.publishedAt ?? Date(),
            projectionServerTimestamp: serverTimestamp
        )
    }
}

@MainActor
final class DefaultFamilyShareOwnerSharingService: FamilyShareOwnerSharingServicing {
    private let registry: FamilyShareNamespaceRegistry
    private let stateProvider: FamilyShareStateProviding
    private let publisher: FamilyShareProjectionPublishing
    private let cloudSync: FamilyShareCloudSyncing?
    private let telemetry: FamilyShareTelemetryTracking
    private let namespaceExecutionHub: FamilyShareNamespaceExecutionHub

    init(
        registry: FamilyShareNamespaceRegistry? = nil,
        stateProvider: FamilyShareStateProviding? = nil,
        publisher: FamilyShareProjectionPublishing? = nil,
        cloudSync: FamilyShareCloudSyncing? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker()
    ) {
        let resolvedRegistry = registry ?? FamilyShareNamespaceRegistry()
        self.registry = resolvedRegistry
        self.stateProvider = stateProvider ?? DefaultFamilyShareStateProvider(registry: resolvedRegistry)
        self.publisher = publisher ?? DefaultFamilyShareProjectionPublisher(registry: resolvedRegistry)
        self.cloudSync = cloudSync
        self.telemetry = telemetry
        self.namespaceExecutionHub = FamilyShareNamespaceExecutionHub()
    }

    func scopePreview(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareScopePreviewSummary {
        let seededState = try await stateProvider.seededState(for: namespaceID)
        let hasGoals = seededState?.projectionPayload?.goals.isEmpty == false

        return FamilyShareScopePreviewSummary(
            title: "Share all current goals",
            summaryPoints: [
                "All current goals are shared",
                "Future goals auto-share",
                "Invitees are read-only"
            ],
            visibleDataSections: [
                "Goal name, emoji, target amount, deadline",
                "Progress, current month summary, freshness"
            ],
            excludedDataSections: [
                "Wallet addresses",
                "Raw transaction identifiers",
                "Operator-only repair tools"
            ],
            revokeBehavior: [
                "Access can be revoked at any time",
                "Revocation removes the invitee's read-only surface"
            ],
            primaryActionCopy: hasGoals ? "Continue" : "Share with Family"
        )
    }

    func ownerState(for namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareOwnerViewState? {
        try await stateProvider.ownerState(for: namespaceID)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
        guard let currentState = try await stateProvider.seededState(for: namespaceID) else { return }
        try await cloudSync?.revoke(namespaceID: namespaceID)
        telemetry.track(.revoked, payload: ["namespace": namespaceID.namespaceKey])

        let revokedOwnerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .revoked,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 1,
            failedParticipantCount: 0,
            summaryCopy: "Access revoked.",
            primaryActionCopy: "Share with Family"
        )

        let revokedInviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: currentState.ownerDisplayName,
            lifecycleState: .revoked,
            goalCount: currentState.inviteeState?.goalCount ?? currentState.projectionPayload?.goals.count ?? 0,
            lastUpdatedAt: Date(),
            asOfCopy: nil,
            titleCopy: "Access revoked by owner",
            messageCopy: "The shared read-only surface is no longer available.",
            primaryActionCopy: "Ask owner to re-share",
            isReadOnly: true
        )

        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: currentState.ownerDisplayName,
                ownerState: revokedOwnerState,
                inviteeState: revokedInviteeState,
                projectionPayload: currentState.projectionPayload?.updatingLifecycleState(FamilyShareOwnerLifecycleState.revoked.rawValue)
            )
        )
        await namespaceExecutionHub.markRevoked(
            with: FamilyShareSeededNamespaceState(
                ownerDisplayName: currentState.ownerDisplayName,
                ownerState: revokedOwnerState,
                inviteeState: revokedInviteeState,
                projectionPayload: currentState.projectionPayload?.updatingLifecycleState(FamilyShareOwnerLifecycleState.revoked.rawValue)
            )
        )
    }
}

@MainActor
final class FamilyShareCacheMigrationCoordinator: FamilyShareCacheMigrating {
    private let registry: FamilyShareNamespaceRegistry

    init(registry: FamilyShareNamespaceRegistry? = nil) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
    }

    func ensureCompatible(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareCacheMigrationResult {
        let current: FamilyShareSeededNamespaceState?
        do {
            current = try registry.seededState(for: namespaceID)
        } catch {
            registry.purge(namespaceID: namespaceID)
            try seedQuarantinedState(
                namespaceID: namespaceID,
                ownerDisplayName: namespaceID.ownerID,
                reason: error.localizedDescription
            )
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: nil,
                currentSchemaVersion: FamilyShareCacheSchema.currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: true
            )
        }

        guard let current else {
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: nil,
                currentSchemaVersion: FamilyShareCacheSchema.currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: false
            )
        }

        guard let projectionPayload = current.projectionPayload else {
            try seedQuarantinedState(
                namespaceID: namespaceID,
                ownerDisplayName: current.ownerDisplayName,
                reason: "The shared cache needs to be rebuilt before it can be trusted."
            )
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: nil,
                currentSchemaVersion: FamilyShareCacheSchema.currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: true
            )
        }

        let previousVersion = projectionPayload.schemaVersion
        let currentVersion = FamilyShareCacheSchema.currentVersion

        if previousVersion > currentVersion {
            registry.purge(namespaceID: namespaceID)
            try seedQuarantinedState(
                namespaceID: namespaceID,
                ownerDisplayName: current.ownerDisplayName,
                reason: FamilyShareCacheMigrationError.unsupportedFutureSchemaVersion(
                    current: currentVersion,
                    required: previousVersion
                ).localizedDescription
            )
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: previousVersion,
                currentSchemaVersion: currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: true
            )
        }

        if previousVersion < FamilyShareCacheSchema.supportedVersions.lowerBound {
            registry.purge(namespaceID: namespaceID)
            try seedQuarantinedState(
                namespaceID: namespaceID,
                ownerDisplayName: current.ownerDisplayName,
                reason: FamilyShareCacheMigrationError.unsupportedHistoricalSchemaVersion(
                    current: FamilyShareCacheSchema.supportedVersions.lowerBound,
                    required: previousVersion
                ).localizedDescription
            )
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: previousVersion,
                currentSchemaVersion: currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: true
            )
        }

        if previousVersion < currentVersion {
            let migratedPayload = projectionPayload.migratedForCurrentFreshnessSchema(
                currentVersion: currentVersion
            )
            let migratedSeed = FamilyShareSeededNamespaceState(
                ownerDisplayName: current.ownerDisplayName,
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: current.ownerState.namespaceID,
                    lifecycleState: current.ownerState.lifecycleState,
                    participantCount: current.ownerState.participantCount,
                    pendingParticipantCount: current.ownerState.pendingParticipantCount,
                    activeParticipantCount: current.ownerState.activeParticipantCount,
                    revokedParticipantCount: current.ownerState.revokedParticipantCount,
                    failedParticipantCount: current.ownerState.failedParticipantCount,
                    summaryCopy: current.ownerState.summaryCopy,
                    primaryActionCopy: current.ownerState.primaryActionCopy
                ),
                inviteeState: current.inviteeState.map { inviteeState in
                    FamilyShareInviteeViewState(
                        namespaceID: inviteeState.namespaceID,
                        ownerDisplayName: inviteeState.ownerDisplayName,
                        lifecycleState: inviteeState.lifecycleState,
                        goalCount: inviteeState.goalCount,
                        lastUpdatedAt: migratedPayload.lastReconciledAt ?? migratedPayload.publishedAt,
                        asOfCopy: migratedPayload.publishedAt.map { "As of \($0.formatted(date: .abbreviated, time: .shortened))" },
                        titleCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                            lifecycleState: inviteeState.lifecycleState,
                            fallback: inviteeState.titleCopy
                        ),
                        messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                            lifecycleState: inviteeState.lifecycleState,
                            fallback: inviteeState.messageCopy
                        ),
                        primaryActionCopy: inviteeState.primaryActionCopy,
                        isReadOnly: inviteeState.isReadOnly
                    )
                },
                projectionPayload: migratedPayload
            )
            try registry.seed(
                migratedSeed
            )

            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: previousVersion,
                currentSchemaVersion: currentVersion,
                didMigrate: true,
                requiresRebuild: false,
                quarantined: false
            )
        }

        return FamilyShareCacheMigrationResult(
            namespaceID: namespaceID,
            previousSchemaVersion: previousVersion,
            currentSchemaVersion: currentVersion,
            didMigrate: false,
            requiresRebuild: false,
            quarantined: false
        )
    }

    private func seedQuarantinedState(
        namespaceID: FamilyShareNamespaceID,
        ownerDisplayName: String,
        reason: String
    ) throws {
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: ownerDisplayName,
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: namespaceID,
                    lifecycleState: .shareFailed,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 1,
                    summaryCopy: "The shared cache needs to be rebuilt before it can be trusted.",
                    primaryActionCopy: "Manage Participants"
                ),
                inviteeState: FamilyShareInviteeViewState(
                    namespaceID: namespaceID,
                    ownerDisplayName: ownerDisplayName,
                    lifecycleState: .temporarilyUnavailable,
                    goalCount: 0,
                    lastUpdatedAt: nil,
                    asOfCopy: nil,
                    titleCopy: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                    messageCopy: reason,
                    primaryActionCopy: "Retry",
                    isReadOnly: true
                ),
                projectionPayload: nil
            )
        )
    }
}

@MainActor
struct FamilyShareCloudSharingPreparationRequest {
    let namespaceID: FamilyShareNamespaceID
    let ownerDisplayName: String
    let shareTitle: String
}

@MainActor
struct FamilyShareCloudSharingRequest: Identifiable {
    let namespaceID: FamilyShareNamespaceID
    let ownerDisplayName: String
    let shareTitle: String
    #if canImport(CloudKit)
    let share: CKShare
    let container: CKContainer
    #endif

    var id: String { namespaceID.namespaceKey }
}

@MainActor
final class FamilyShareProjectionPublishCoordinator {
    private let publisher: FamilyShareProjectionPublishing
    private(set) var pendingItems: [FamilyShareProjectionOutboxItem] = []

    init(publisher: FamilyShareProjectionPublishing) {
        self.publisher = publisher
    }

    func publish(_ payload: FamilyShareProjectionPayload) async throws -> FamilySharePublicationResult {
        let outboxItem = FamilyShareProjectionOutboxItem(
            id: UUID(),
            namespaceID: payload.namespaceID,
            projectionVersion: payload.projectionVersion,
            enqueuedAt: Date()
        )
        pendingItems.append(outboxItem)
        defer {
            pendingItems.removeAll { $0.id == outboxItem.id }
        }
        return try await publisher.publish(payload)
    }
}

@MainActor
final class FamilyShareSceneBridgeHub {
    static let shared = FamilyShareSceneBridgeHub()
    weak var acceptanceSink: (any FamilyShareSceneAccepting)?
}

@MainActor
final class FamilyShareOwnerIdentityStore {
    private enum Keys {
        static let ownerID = "familyShare.ownerID"
        static let shareID = "familyShare.shareID"
        static let ownerName = "familyShare.ownerName"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func ownerID() -> String {
        if let existing = userDefaults.string(forKey: Keys.ownerID), existing.isEmpty == false {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        userDefaults.set(generated, forKey: Keys.ownerID)
        return generated
    }

    func shareID() -> String {
        if let existing = userDefaults.string(forKey: Keys.shareID), existing.isEmpty == false {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        userDefaults.set(generated, forKey: Keys.shareID)
        return generated
    }

    func ownerDisplayName() -> String {
        if let existing = userDefaults.string(forKey: Keys.ownerName), existing.isEmpty == false {
            return existing
        }
        let generated: String
#if canImport(UIKit)
        generated = UIDevice.current.name.isEmpty ? "My Goals" : UIDevice.current.name
#else
        generated = ProcessInfo.processInfo.hostName.isEmpty ? "My Goals" : ProcessInfo.processInfo.hostName
#endif
        userDefaults.set(generated, forKey: Keys.ownerName)
        return generated
    }

    func ownerNamespaceID() -> FamilyShareNamespaceID {
        FamilyShareNamespaceID(ownerID: ownerID(), shareID: shareID())
    }

    func namespaceID(for snapshot: FamilyShareInvitationMetadataSnapshot) -> FamilyShareNamespaceID {
        if let parsed = snapshot.rootRecordLookupCandidates.compactMap(FamilyShareNamespaceID.init(recordLocator:)).first {
            return parsed
        }
        let ownerID = sanitize(snapshot.rootRecordName ?? snapshot.ownerDisplayName)
        let shareID = sanitize(snapshot.hierarchicalRootRecordName ?? snapshot.shareURLString ?? snapshot.ownerDisplayName)
        return FamilyShareNamespaceID(ownerID: ownerID, shareID: shareID)
    }

    private func sanitize(_ rawValue: String) -> String {
        let lowered = rawValue.lowercased()
        let filtered = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let normalized = String(filtered)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? UUID().uuidString.lowercased() : normalized
    }
}

@MainActor
final class FamilyShareAcceptanceCoordinator: ObservableObject, FamilyShareSceneAccepting {
    @Published private(set) var latestAcceptanceSnapshot: FamilyShareInvitationMetadataSnapshot?
    @Published private(set) var latestConnectionOptionsSnapshot: FamilyShareInvitationMetadataSnapshot?
    @Published private(set) var lastSeededScenario: FamilyShareTestScenario?
    @Published private(set) var ownerState: FamilyShareOwnerViewState
    @Published private(set) var ownerParticipants: [FamilyShareParticipantSnapshot] = []
    @Published private(set) var inviteeProjection: FamilyShareInviteeProjection = .empty
    @Published private(set) var inviteeStates: [FamilyShareInviteeViewState] = []
    @Published var pendingCloudSharingRequest: FamilyShareCloudSharingRequest?
    @Published var latestErrorMessage: String?

    let ownerNamespaceID: FamilyShareNamespaceID

    private let registry: FamilyShareNamespaceRegistry
    private let stateProvider: FamilyShareStateProviding
    private let inviteeStateProvider: FamilyShareInviteeStateProviding
    private let ownerSharingService: FamilyShareOwnerSharingServicing
    private let cacheMigrationCoordinator: FamilyShareCacheMigrating
    private let publishCoordinator: FamilyShareProjectionPublishCoordinator
    private let seeder: FamilyShareTestSeeder
    private let identityStore: FamilyShareOwnerIdentityStore
    private let cloudSync: FamilyShareCloudSyncing?
    private let rollout: FamilyShareRollout
    private let telemetry: FamilyShareTelemetryTracking
    private let namespaceExecutionHub: FamilyShareNamespaceExecutionHub
    private let activeGoalsProvider: () throws -> [Goal]
    private var trackedInviteeTelemetryKeys: Set<String> = []
    private var refreshGeneration: Int = 0

    // MARK: - Freshness Pipeline Components

    private let autoRepublishCoordinator: FamilyShareProjectionAutoRepublishCoordinator
    private let mutationObserver: FamilyShareProjectionMutationObserver
    private let inviteeRefreshScheduler: FamilyShareInviteeRefreshScheduler
    private let rateRefreshDriver: FamilyShareForegroundRateRefreshDriver?
    private let rateDriftEvaluator: FamilyShareRateDriftEvaluator
    private var freshnessPipelineActive = false

    var sharedSections: [FamilyShareInviteeSectionProjection] {
        inviteeProjection.sections
    }

    init(
        registry: FamilyShareNamespaceRegistry? = nil,
        stateProvider: (any FamilyShareStateProviding)? = nil,
        inviteeStateProvider: (any FamilyShareInviteeStateProviding)? = nil,
        ownerSharingService: (any FamilyShareOwnerSharingServicing)? = nil,
        cacheMigrationCoordinator: (any FamilyShareCacheMigrating)? = nil,
        publishCoordinator: FamilyShareProjectionPublishCoordinator? = nil,
        seeder: FamilyShareTestSeeder? = nil,
        identityStore: FamilyShareOwnerIdentityStore? = nil,
        cloudSync: FamilyShareCloudSyncing? = nil,
        rollout: FamilyShareRollout = .shared,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker(),
        activeGoalsProvider: (() throws -> [Goal])? = nil
    ) {
        let resolvedRegistry = registry ?? FamilyShareNamespaceRegistry()
        let resolvedStateProvider = stateProvider ?? DefaultFamilyShareStateProvider(registry: resolvedRegistry)
        let resolvedInviteeProvider = inviteeStateProvider ?? DefaultFamilyShareStateProvider(registry: resolvedRegistry)
        let resolvedPublisher = DefaultFamilyShareProjectionPublisher(
            registry: resolvedRegistry,
            cloudSync: cloudSync,
            telemetry: telemetry
        )
        let resolvedIdentityStore = identityStore ?? FamilyShareOwnerIdentityStore()
        self.registry = resolvedRegistry
        self.stateProvider = resolvedStateProvider
        self.inviteeStateProvider = resolvedInviteeProvider
        self.ownerSharingService = ownerSharingService ?? DefaultFamilyShareOwnerSharingService(
            registry: resolvedRegistry,
            stateProvider: resolvedStateProvider,
            publisher: resolvedPublisher,
            cloudSync: cloudSync,
            telemetry: telemetry
        )
        self.cacheMigrationCoordinator = cacheMigrationCoordinator ?? FamilyShareCacheMigrationCoordinator(registry: resolvedRegistry)
        self.publishCoordinator = publishCoordinator ?? FamilyShareProjectionPublishCoordinator(publisher: resolvedPublisher)
        self.seeder = seeder ?? FamilyShareTestSeeder(registry: resolvedRegistry)
        self.identityStore = resolvedIdentityStore
        self.cloudSync = cloudSync
        self.rollout = rollout
        self.telemetry = telemetry
        self.namespaceExecutionHub = FamilyShareNamespaceExecutionHub()
        self.activeGoalsProvider = activeGoalsProvider ?? {
            try PersistenceController.shared.activeMainContext.fetch(SwiftDataQueries.activeGoals())
        }
        self.ownerNamespaceID = resolvedIdentityStore.ownerNamespaceID()
        self.ownerState = FamilyShareOwnerViewState(
            namespaceID: resolvedIdentityStore.ownerNamespaceID(),
            lifecycleState: .notShared,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Share all of your goals with family in read-only mode.",
            primaryActionCopy: "Share with Family"
        )

        // Initialize freshness pipeline components
        let nsKey = resolvedIdentityStore.ownerNamespaceID().namespaceKey
        self.autoRepublishCoordinator = FamilyShareProjectionAutoRepublishCoordinator(
            namespaceKey: nsKey,
            rollout: rollout
        )
        self.mutationObserver = FamilyShareProjectionMutationObserver(rollout: rollout)
        self.inviteeRefreshScheduler = FamilyShareInviteeRefreshScheduler(rollout: rollout)
        self.rateDriftEvaluator = FamilyShareRateDriftEvaluator(rollout: rollout)

        // Rate refresh driver needs ExchangeRateService — use DIContainer if available
        if rollout.isFreshnessPipelineEnabled() {
            self.rateRefreshDriver = FamilyShareForegroundRateRefreshDriver(
                exchangeRateService: ExchangeRateService.shared,
                rollout: rollout
            )
        } else {
            self.rateRefreshDriver = nil
        }

        FamilyShareSceneBridgeHub.shared.acceptanceSink = self

        Task { [weak self] in
            await self?.refreshAllState()
        }
    }

    /// Wire the freshness pipeline into production lifecycle.
    private func startFreshnessPipeline() async {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        freshnessPipelineActive = true

        await configureAutoRepublishCoordinator()

        inviteeRefreshScheduler.setRefreshAction { [weak self] namespaceKey in
            guard let self else { return .failure(FamilyShareCloudKitError.sharedProjectionMissing) }
            guard let namespaceID = self.resolveNamespaceID(for: namespaceKey) else {
                return .failure(FamilyShareCloudKitError.sharedProjectionMissing)
            }
            let result = await self.refreshNamespace(namespaceID)
            await self.refreshAllState()
            return result
        }

        // Start mutation observer — routes dirty events to coordinator
        mutationObserver.start { [weak self] reason in
            guard let self else { return }
            Task {
                await self.autoRepublishCoordinator.markDirty(reason: reason)
            }
        }

        // Rehydrate any persisted dirty state from previous launch
        await autoRepublishCoordinator.rehydrateIfNeeded()

        // Start rate-drift evaluator — listens for rate refresh events and emits dirty events
        let initialGoals = (try? fetchActiveGoals()) ?? []
        let initialPublishedAmounts = (try? registry.seededState(for: ownerNamespaceID)?.projectionPayload?.goals.reduce(into: [UUID: Decimal]()) { partialResult, goal in
            guard let goalID = UUID(uuidString: goal.goalID) else { return }
            partialResult[goalID] = goal.currentAmount
        }) ?? [:]
        await rateDriftEvaluator.start(
            goalInputs: makeGoalProgressInputs(from: initialGoals),
            lastPublished: initialPublishedAmounts,
            handler: { [weak self] reason in
                guard let self else { return }
                Task {
                    await self.autoRepublishCoordinator.markDirty(reason: reason)
                }
            }
        )

        if shouldRunOwnerRateRefreshDriver(for: ownerState) {
            rateRefreshDriver?.start()
        } else {
            rateRefreshDriver?.suspend()
        }
    }

    private func configureAutoRepublishCoordinator() async {
        let payloadBuilder = { [weak self] () async throws -> FamilySharePublishReceipt? in
            guard let self else { return nil }
            let goals = try self.fetchActiveGoals()
            return try await self.publishProjectionImmediately(for: goals)
        }
        await autoRepublishCoordinator.setPublishAction(payloadBuilder)
        await autoRepublishCoordinator.setRemoteChangeDateProvider { [weak self] in
            guard let self else { return nil }
            return self.lastKnownOwnerProjectionServerTimestamp()
        }
    }

    /// Last known goals passed to shareAllGoals — cached for auto-republish rebuilds.
    /// Updated by shareAllGoals and by updateSharedGoalsCache when mutations occur.
    private var lastSharedGoals: [Goal] = []

    /// Fetch active goals for projection rebuild.
    /// Prefers authoritative SwiftData state; falls back to the in-memory cache only
    /// if fetching fails unexpectedly.
    private func fetchActiveGoals() throws -> [Goal] {
        do {
            let goals = try activeGoalsProvider()
            lastSharedGoals = goals
            return goals
        } catch {
            if lastSharedGoals.isEmpty == false {
                AppLog.warning("Falling back to cached shared goals for projection rebuild: \(error)", category: .ui)
                return lastSharedGoals
            }
            throw error
        }
    }

    /// Update the shared goals cache with fresh goal references.
    /// Called from shareAllGoals and when goals change via mutation observer.
    func updateSharedGoalsCache(_ goals: [Goal]) {
        lastSharedGoals = goals
    }

    func refreshAllState() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        guard rollout.isEnabled() else {
            await teardownFreshnessPipelineIfNeeded()
            return
        }
        if rollout.isFreshnessPipelineEnabled(), freshnessPipelineActive == false {
            await startFreshnessPipeline()
        }
        do {
            let namespaceIDs = registry.allNamespaceIDs()
            for namespaceID in namespaceIDs {
                do {
                    let migrationResult = try await cacheMigrationCoordinator.ensureCompatible(namespaceID: namespaceID)
                    if migrationResult.quarantined {
                        telemetry.track(
                            .migrationFailed,
                            payload: [
                                "namespace": namespaceID.namespaceKey,
                                "reason": "quarantined",
                                "requires_rebuild": migrationResult.requiresRebuild ? "true" : "false"
                            ]
                        )
                        try await quarantineNamespace(namespaceID: namespaceID)
                    } else if migrationResult.requiresRebuild {
                        telemetry.track(
                            .rebuildStarted,
                            payload: ["namespace": namespaceID.namespaceKey]
                        )
                        telemetry.track(
                            .rebuildSucceeded,
                            payload: ["namespace": namespaceID.namespaceKey]
                        )
                    }
                } catch {
                    telemetry.track(
                        .migrationFailed,
                        payload: ["namespace": namespaceID.namespaceKey, "reason": error.localizedDescription]
                    )
                    throw error
                }
            }

            let storedOwnerState = try await stateProvider.ownerState(for: ownerNamespaceID) ?? defaultOwnerState(for: ownerNamespaceID)
            var resolvedOwnerState = storedOwnerState
            var resolvedOwnerParticipants = fallbackParticipants(for: storedOwnerState)
            var ownerShareErrorMessage: String?

            if let cloudSync {
                do {
                    let ownerShareSnapshot = try await cloudSync.ownerShareSnapshot(namespaceID: ownerNamespaceID)
                    resolvedOwnerState = ownerShareSnapshot.ownerState
                    resolvedOwnerParticipants = ownerShareSnapshot.participants
                } catch {
                    telemetry.track(
                        .refreshFailed,
                        payload: [
                            "namespace": ownerNamespaceID.namespaceKey,
                            "reason": error.localizedDescription,
                            "surface": "owner"
                        ]
                    )
                    ownerShareErrorMessage = error.localizedDescription
                }
            }

            guard generation == refreshGeneration else { return }
            ownerState = resolvedOwnerState
            ownerParticipants = resolvedOwnerParticipants
            if rollout.isFreshnessPipelineEnabled() {
                if shouldRunOwnerRateRefreshDriver(for: resolvedOwnerState) {
                    rateRefreshDriver?.start()
                } else {
                    rateRefreshDriver?.suspend()
                }
            }
            inviteeStates = try await inviteeStateProvider.inviteeStates()
                .filter { $0.namespaceID != ownerNamespaceID }
            let projection = try await inviteeStateProvider.sharedInviteeProjection()
            inviteeProjection = FamilyShareInviteeProjection(
                entryTitle: projection.entryTitle,
                entrySummary: projection.entrySummary,
                sections: projection.sections.filter {
                    $0.namespaceID.ownerID != ownerNamespaceID.ownerID || $0.namespaceID.shareID != ownerNamespaceID.shareID
                }
            )
            trackInviteeViewTelemetry()
            latestErrorMessage = ownerShareErrorMessage
        } catch {
            guard generation == refreshGeneration else { return }
            latestErrorMessage = error.localizedDescription
            inviteeStates = []
            inviteeProjection = .empty
            ownerState = defaultOwnerState(for: ownerNamespaceID)
            ownerParticipants = []
        }
    }

    func makeFamilyAccessModel(currentGoals: [Goal]) -> FamilyAccessModel {
        let currentOwnerState = ownerState
        let ownerName = normalizedOwnerDisplayName()
        let ownerSection = FamilyShareOwnerSection(
            ownerID: ownerNamespaceID.ownerID,
            shareID: ownerNamespaceID.shareID,
            ownerName: ownerName,
            goals: currentGoals
                .sorted {
                    if $0.deadline != $1.deadline {
                        return $0.deadline < $1.deadline
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                .map { goal in
                    FamilySharedGoalSummary(goal: goal, ownerName: ownerName, state: mapSurfaceState(ownerLifecycleState: currentOwnerState.lifecycleState))
                },
            isCurrentOwner: true,
            state: mapSurfaceState(ownerLifecycleState: currentOwnerState.lifecycleState),
            summaryCopy: currentOwnerState.summaryCopy,
            primaryActionTitle: currentOwnerState.primaryActionCopy
        )

        return FamilyAccessModel(
            ownerName: ownerName,
            subtitle: currentOwnerState.summaryCopy,
            participants: ownerParticipants.map { snapshot in
                FamilyShareParticipant(
                    displayName: snapshot.displayName,
                    emailOrAlias: snapshot.emailOrAlias,
                    state: mapParticipantState(snapshot.state),
                    lastUpdatedAt: snapshot.lastUpdatedAt,
                    isCurrentUser: snapshot.isCurrentUser
                )
            },
            ownerSections: currentGoals.isEmpty ? [] : [ownerSection],
            state: mapSurfaceState(ownerLifecycleState: currentOwnerState.lifecycleState),
            scopePreview: makeScopePreview(ownerName: ownerName)
        )
    }

    func settingsRowSummary(currentGoalCount: Int) -> String {
        switch ownerState.lifecycleState {
        case .notShared:
            return currentGoalCount == 0 ? "Share when goals are ready" : "Not shared"
        case .invitePending:
            return ownerState.pendingParticipantCount == 1
                ? "1 invite pending"
                : "\(ownerState.pendingParticipantCount) invites pending"
        case .sharedActive:
            if ownerState.activeParticipantCount > 0 {
                return ownerState.activeParticipantCount == 1
                    ? "1 participant"
                    : "\(ownerState.activeParticipantCount) participants"
            }
            return "Ready to invite"
        case .revoked:
            return "Access revoked"
        case .shareFailed:
            return "Needs attention"
        }
    }

    func shareAllGoals(_ goals: [Goal]) async {
        guard rollout.isEnabled() else {
            latestErrorMessage = FamilyShareCloudKitError.rolloutDisabled.localizedDescription
            return
        }
        guard goals.isEmpty == false else {
            latestErrorMessage = "Add at least one goal before sharing with family."
            return
        }

        // Cache goals for auto-republish rebuilds
        lastSharedGoals = goals

        do {
            telemetry.track(.createStarted, payload: ["namespace": ownerNamespaceID.namespaceKey])
            telemetry.track(.shareRequested, payload: ["goal_count": "\(goals.count)"])
            guard let cloudSync else {
                telemetry.track(
                    .createFailed,
                    payload: [
                        "namespace": ownerNamespaceID.namespaceKey,
                        "reason": "family sharing cloud sync unavailable"
                    ]
                )
                latestErrorMessage = "Family sync is currently unavailable."
                return
            }

            await configureAutoRepublishCoordinator()
            _ = try await autoRepublishCoordinator.publishNow(reason: .participantChange)

            let prepared = try await cloudSync.prepareShare(
                for: FamilyShareCloudSharingPreparationRequest(
                    namespaceID: ownerNamespaceID,
                    ownerDisplayName: normalizedOwnerDisplayName(),
                    shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals"
                )
            )
            pendingCloudSharingRequest = FamilyShareCloudSharingRequest(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: normalizedOwnerDisplayName(),
                shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals",
                share: prepared.share,
                container: prepared.container
            )
            telemetry.track(.createSucceeded, payload: ["namespace": ownerNamespaceID.namespaceKey])
            if let seededState = try? registry.seededState(for: ownerNamespaceID) {
                await namespaceExecutionHub.bootstrap(with: seededState)
            }
            await refreshAllState()
        } catch {
            telemetry.track(
                .createFailed,
                payload: [
                    "namespace": ownerNamespaceID.namespaceKey,
                    "reason": (error as NSError).localizedDescription
                ]
            )
            latestErrorMessage = error.localizedDescription
        }
    }

    func manageParticipants() async {
        guard rollout.isEnabled() else {
            latestErrorMessage = FamilyShareCloudKitError.rolloutDisabled.localizedDescription
            return
        }
        guard ownerState.lifecycleState != .notShared else {
            latestErrorMessage = "Share your goals first before managing participants."
            return
        }
        guard let cloudSync else {
            latestErrorMessage = "Family sync is currently unavailable."
            return
        }

        do {
            let prepared = try await cloudSync.prepareShare(
                for: FamilyShareCloudSharingPreparationRequest(
                    namespaceID: ownerNamespaceID,
                    ownerDisplayName: normalizedOwnerDisplayName(),
                    shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals"
                )
            )
            pendingCloudSharingRequest = FamilyShareCloudSharingRequest(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: normalizedOwnerDisplayName(),
                shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals",
                share: prepared.share,
                container: prepared.container
            )
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func refreshFamilyAccessOwnerData(currentGoals: [Goal]) async {
        guard rollout.isEnabled() else {
            latestErrorMessage = FamilyShareCloudKitError.rolloutDisabled.localizedDescription
            return
        }

        updateSharedGoalsCache(currentGoals)

        if rollout.isFreshnessPipelineEnabled(),
           currentGoals.isEmpty == false,
           shouldRunOwnerRateRefreshDriver(for: ownerState) {
            do {
                await configureAutoRepublishCoordinator()
                _ = try await autoRepublishCoordinator.publishNow(reason: .manualRefresh)
            } catch {
                latestErrorMessage = error.localizedDescription
            }
        }

        await refreshAllState()
    }

    func noteOwnerParticipantsDidChange() async {
        guard rollout.isFreshnessPipelineEnabled() else {
            await refreshAllState()
            return
        }

        do {
            await configureAutoRepublishCoordinator()
            _ = try await autoRepublishCoordinator.publishNow(reason: .participantChange)
        } catch {
            latestErrorMessage = error.localizedDescription
        }

        await refreshAllState()
    }

    func revokeOwnerShare() async {
        do {
            try await ownerSharingService.revoke(namespaceID: ownerNamespaceID)
            await refreshAllState()
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func handlePrimaryAction(for section: FamilyShareInviteeSectionProjection) async {
        let namespaceID = section.namespaceID
        switch section.state {
        case .active, .stale, .temporarilyUnavailable, .emptySharedDataset:
            inviteeRefreshScheduler.onManualRefresh(namespaceKey: namespaceID.namespaceKey)
        case .invitePendingAcceptance:
            latestErrorMessage = "Accept the Family invitation from Mail or Messages to finish setup."
        case .revoked:
            latestErrorMessage = "The owner needs to share this goal set again."
        case .removedOrNoLongerShared:
            registry.purge(namespaceID: namespaceID)
            await refreshAllState()
        }
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        guard rollout.isFreshnessPipelineEnabled() else { return }

        switch scenePhase {
        case .active:
            if shouldRunOwnerRateRefreshDriver(for: ownerState) {
                rateRefreshDriver?.start()
            }
            #if DEBUG
            let isSeededUITestScenario = UITestFlags.familyShareScenario != nil
            if isSeededUITestScenario {
                return
            }
            #endif
            let inviteeNamespaceKeys = registry
                .allNamespaceIDs()
                .filter { $0 != ownerNamespaceID }
                .map(\.namespaceKey)
            if inviteeNamespaceKeys.isEmpty {
                Task { [weak self] in
                    await self?.refreshAllState()
                }
            } else {
                inviteeRefreshScheduler.onForegroundEntry(namespaceKeys: inviteeNamespaceKeys)
            }
        case .background:
            rateRefreshDriver?.suspend()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func noteSharedSectionBecameVisible(_ namespaceID: FamilyShareNamespaceID) {
        #if DEBUG
        guard UITestFlags.familyShareScenario == nil else { return }
        #endif
        inviteeRefreshScheduler.onFirstVisibility(namespaceKey: namespaceID.namespaceKey)
    }

    func freshnessSubstate(for namespaceID: FamilyShareNamespaceID) -> FamilyShareFreshnessSubstate {
        inviteeRefreshScheduler.substateByNamespace[namespaceID.namespaceKey] ?? .idle
    }

    func freshnessLastChecked(for namespaceID: FamilyShareNamespaceID) -> Date? {
        inviteeRefreshScheduler.lastCheckedByNamespace[namespaceID.namespaceKey]
    }

    func dismissPendingCloudSharingRequest() {
        pendingCloudSharingRequest = nil
    }

    func seedScenario(_ scenario: FamilyShareTestScenario, namespaceID: FamilyShareNamespaceID) throws {
        try seeder.seed(scenario, namespaceID: namespaceID)
        lastSeededScenario = scenario
        Task { [weak self] in
            await self?.refreshAllState()
        }
    }

    #if DEBUG
    func seedUITestScenario(_ scenario: UITestFlags.FamilyShareScenario) async {
        guard let mappedScenario = FamilyShareTestScenario(rawValue: scenario.rawValue) else { return }
        let namespaceID: FamilyShareNamespaceID
        switch mappedScenario {
        case .ownerNotShared, .ownerSharedActive:
            namespaceID = ownerNamespaceID
        case .inviteePending, .inviteeActive, .inviteeBlockedOwner, .inviteeMultiOwner, .inviteeMultiOwnerUnresolved, .inviteeEmpty, .inviteeStale, .inviteeRevoked, .inviteeRemoved, .inviteeUnavailable:
            namespaceID = FamilyShareNamespaceID(ownerID: "shared-owner", shareID: "shared-household")
        }

        do {
            try seeder.seed(mappedScenario, namespaceID: namespaceID)
            lastSeededScenario = mappedScenario
            await refreshAllState()
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }
    #endif

    func resetAllNamespaces() async {
        registry.purgeAllNamespaces()
        await namespaceExecutionHub.reset()
        trackedInviteeTelemetryKeys.removeAll()
        inviteeStates = []
        inviteeProjection = .empty
        pendingCloudSharingRequest = nil
        latestErrorMessage = nil
        lastSeededScenario = nil
        ownerState = defaultOwnerState(for: ownerNamespaceID)
        ownerParticipants = []
    }

    func acceptInvitation(_ metadata: CKShare.Metadata) {
        guard rollout.isEnabled() else { return }
        let snapshot = FamilyShareInvitationMetadataSnapshot(metadata: metadata)
        latestAcceptanceSnapshot = snapshot
        Task { [weak self] in
            await self?.bootstrapAcceptedInvitation(snapshot, metadata: metadata)
        }
    }

#if canImport(UIKit)
    func acceptPendingInvitation(from connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        let snapshot = FamilyShareInvitationMetadataSnapshot(metadata: metadata)
        latestConnectionOptionsSnapshot = snapshot
        acceptInvitation(metadata)
    }
#endif

    private func bootstrapAcceptedInvitation(
        _ snapshot: FamilyShareInvitationMetadataSnapshot,
        metadata: CKShare.Metadata? = nil
    ) async {
        do {
            if let cloudSync {
                let acceptedSnapshot: FamilyShareInvitationMetadataSnapshot
                if let metadata {
                    acceptedSnapshot = try await cloudSync.acceptInvitation(metadata: metadata)
                    await MainActor.run {
                        latestAcceptanceSnapshot = acceptedSnapshot
                    }
                } else {
                    acceptedSnapshot = snapshot
                }

                let seededState = try await cloudSync.fetchAcceptedProjection(from: acceptedSnapshot)
                try registry.seed(seededState)
                await namespaceExecutionHub.markAccepted(with: seededState)
                telemetry.track(.acceptSucceeded, payload: ["namespace": seededState.ownerState.namespaceID.namespaceKey])
                telemetry.track(.accepted, payload: ["namespace": seededState.ownerState.namespaceID.namespaceKey])
            } else {
                let namespaceID = identityStore.namespaceID(for: snapshot)
                if try registry.seededState(for: namespaceID) == nil {
                    let seededState = FamilyShareSeededNamespaceState(
                        ownerDisplayName: snapshot.ownerDisplayName,
                        ownerState: FamilyShareOwnerViewState(
                            namespaceID: namespaceID,
                            lifecycleState: .sharedActive,
                            participantCount: 1,
                            pendingParticipantCount: 0,
                            activeParticipantCount: 1,
                            revokedParticipantCount: 0,
                            failedParticipantCount: 0,
                            summaryCopy: "Shared goal set available for read-only access.",
                            primaryActionCopy: "Manage Participants"
                        ),
                        inviteeState: FamilyShareInviteeViewState(
                            namespaceID: namespaceID,
                            ownerDisplayName: snapshot.ownerDisplayName,
                            lifecycleState: .emptySharedDataset,
                            goalCount: 0,
                            lastUpdatedAt: Date(),
                            asOfCopy: Date().formatted(date: .abbreviated, time: .shortened),
                            titleCopy: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                            messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                                lifecycleState: .emptySharedDataset,
                                fallback: "The invitation was accepted. Pull the latest shared goals to populate this section."
                            ),
                            primaryActionCopy: "Retry",
                            isReadOnly: true
                        ),
                        projectionPayload: nil
                    )
                    try registry.seed(seededState)
                    await namespaceExecutionHub.markAccepted(with: seededState)
                    telemetry.track(.acceptSucceeded, payload: ["namespace": namespaceID.namespaceKey])
                    telemetry.track(.accepted, payload: ["namespace": namespaceID.namespaceKey])
                }
            }
            await refreshAllState()
        } catch {
            let namespaceID = identityStore.namespaceID(for: (metadata.map { FamilyShareInvitationMetadataSnapshot(metadata: $0) }) ?? snapshot)
            if (try? registry.seededState(for: namespaceID)) == nil {
                let failedState = FamilyShareSeededNamespaceState(
                    ownerDisplayName: snapshot.ownerDisplayName,
                    ownerState: FamilyShareOwnerViewState(
                        namespaceID: namespaceID,
                        lifecycleState: .shareFailed,
                        participantCount: 0,
                        pendingParticipantCount: 0,
                        activeParticipantCount: 0,
                        revokedParticipantCount: 0,
                        failedParticipantCount: 1,
                        summaryCopy: "The invitation was accepted, but shared goals could not be loaded yet.",
                        primaryActionCopy: "Manage Participants"
                    ),
                        inviteeState: FamilyShareInviteeViewState(
                            namespaceID: namespaceID,
                            ownerDisplayName: snapshot.ownerDisplayName,
                            lifecycleState: .temporarilyUnavailable,
                            goalCount: 0,
                            lastUpdatedAt: nil,
                            asOfCopy: nil,
                            titleCopy: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                            messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                                lifecycleState: .temporarilyUnavailable,
                                fallback: "The invitation was accepted, but the shared goal set is not available yet. Try again in a moment."
                            ),
                            primaryActionCopy: "Retry",
                            isReadOnly: true
                        ),
                    projectionPayload: nil
                )
                try? registry.seed(failedState)
                await namespaceExecutionHub.markFailed(
                    with: failedState,
                    reason: error.localizedDescription
                )
            }
            telemetry.track(.acceptFailed, payload: ["reason": error.localizedDescription])
            latestErrorMessage = error.localizedDescription
            await refreshAllState()
        }
    }

    private func publishProjectionImmediately(for goals: [Goal]) async throws -> FamilySharePublishReceipt? {
        let payload = try await makeProjectionPayload(for: goals)
        if let cachedPayload = try registry.seededState(for: ownerNamespaceID)?.projectionPayload,
           let incomingHash = payload.contentHash,
           let cachedHash = cachedPayload.contentHash,
           incomingHash == cachedHash {
            telemetry.track(.contentHashDedup, payload: ["namespace": ownerNamespaceID.namespaceKey])
            await recordPublishedProjection(
                goals: goals,
                payload: payload,
                result: FamilySharePublicationResult(
                    namespaceID: cachedPayload.namespaceID,
                    projectionVersion: cachedPayload.projectionVersion,
                    activeProjectionVersion: cachedPayload.activeProjectionVersion,
                    goalCount: cachedPayload.goals.count,
                    ownerSectionCount: cachedPayload.ownerSections.count,
                    publishedAt: cachedPayload.publishedAt ?? Date(),
                    projectionServerTimestamp: cachedPayload.projectionServerTimestamp
                )
            )
            return nil
        }
        let result = try await publishCoordinator.publish(payload)
        await recordPublishedProjection(goals: goals, payload: payload, result: result)
        return FamilySharePublishReceipt(
            serverTimestamp: result.projectionServerTimestamp ?? result.publishedAt,
            recordCount: result.goalCount + result.ownerSectionCount + 1
        )
    }

    private func recordPublishedProjection(
        goals: [Goal],
        payload: FamilyShareProjectionPayload,
        result: FamilySharePublicationResult
    ) async {
        var updatedPayload = payload
        updatedPayload.projectionServerTimestamp = result.projectionServerTimestamp

        if result.projectionServerTimestamp != nil {
            try? registry.seed(
                FamilyShareSeededNamespaceState(
                    ownerDisplayName: payload.ownerDisplayName,
                    ownerState: ownerState,
                    inviteeState: nil,
                    projectionPayload: updatedPayload
                )
            )
        }

        lastSharedGoals = goals
        let publishedAmounts: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: updatedPayload.goals.compactMap { projectedGoal in
            guard let goalID = UUID(uuidString: projectedGoal.goalID) else { return nil }
            return (goalID, projectedGoal.currentAmount)
        })
        await rateDriftEvaluator.updateTrackedGoals(
            makeGoalProgressInputs(from: goals),
            lastPublished: publishedAmounts
        )
    }

    private func makeGoalProgressInputs(from goals: [Goal]) -> [GoalProgressInput] {
        goals.map { goal in
            GoalProgressInput(
                goalID: goal.id,
                currency: goal.currency,
                targetAmount: Decimal(goal.targetAmount),
                allocations: (goal.allocations ?? []).compactMap { alloc in
                    guard let asset = alloc.asset else { return nil }
                    return AllocationInput(
                        assetCurrency: asset.currency,
                        allocatedAmount: Decimal(alloc.amountValue)
                    )
                }
            )
        }
    }

    private func resolveNamespaceID(for namespaceKey: String) -> FamilyShareNamespaceID? {
        registry.allNamespaceIDs().first { $0.namespaceKey == namespaceKey }
    }

    private func shouldRunOwnerRateRefreshDriver(for ownerState: FamilyShareOwnerViewState) -> Bool {
        switch ownerState.lifecycleState {
        case .sharedActive, .invitePending:
            return true
        case .notShared, .revoked, .shareFailed:
            return false
        }
    }

    private func lastKnownOwnerProjectionServerTimestamp() -> Date? {
        guard let payload = try? registry.seededState(for: ownerNamespaceID)?.projectionPayload else {
            return nil
        }
        return payload.projectionServerTimestamp ?? payload.publishedAt
    }

    private func teardownFreshnessPipelineIfNeeded() async {
        guard freshnessPipelineActive else { return }
        mutationObserver.teardown()
        inviteeRefreshScheduler.teardown()
        await rateDriftEvaluator.teardown()
        rateRefreshDriver?.teardown()
        await autoRepublishCoordinator.teardown()
        freshnessPipelineActive = false
    }

    private func refreshNamespace(_ namespaceID: FamilyShareNamespaceID) async -> FamilyShareRefreshResult {
        telemetry.track(.refreshRequested, payload: ["namespace": namespaceID.namespaceKey])
        if let cloudSync {
            do {
                let seededState = try await cloudSync.refreshProjection(namespaceID: namespaceID)

                // Three-phase invitee ordering check (proposal Section 6.8.2)
                if let incoming = seededState.projectionPayload,
                   let cached = try? await stateProvider.seededState(for: namespaceID)?.projectionPayload {
                    // Phase 1: Atomic version check
                    if incoming.projectionVersion < cached.activeProjectionVersion {
                        telemetry.track(.refreshSucceeded, payload: ["namespace": namespaceID.namespaceKey, "ordering": "rejected_version"])
                        return .noNewData // Discard — incomplete publish from old topology
                    }
                    // Phase 2: Content dedup — matching hash = no-op
                    if let incomingHash = incoming.contentHash,
                       let cachedHash = cached.contentHash,
                       incomingHash == cachedHash {
                        telemetry.track(.contentHashDedup, payload: ["namespace": namespaceID.namespaceKey])
                        return .noNewData // No semantic change
                    }
                    // Phase 3: contentHash differs → accept unconditionally (semantic change)
                    // If contentHash is nil (pre-migration), fall back to projectionServerTimestamp
                    if incoming.contentHash == nil || cached.contentHash == nil {
                        if let incomingTs = incoming.projectionServerTimestamp,
                           let cachedTs = cached.projectionServerTimestamp,
                           incomingTs <= cachedTs {
                            telemetry.track(.refreshSucceeded, payload: ["namespace": namespaceID.namespaceKey, "ordering": "rejected_timestamp"])
                            return .noNewData // Incoming is not newer
                        }
                    }
                    // Accept: contentHash differs or pre-migration fallback passed
                }

                try registry.seed(seededState)
                await namespaceExecutionHub.refresh(with: seededState)
                telemetry.track(.refreshSucceeded, payload: ["namespace": namespaceID.namespaceKey])
                trackViewEvent(for: seededState.inviteeState)
                return .success(updatedProjection: true)
            } catch {
                telemetry.track(.refreshFailed, payload: ["namespace": namespaceID.namespaceKey, "reason": error.localizedDescription])
                if let current = try? await stateProvider.seededState(for: namespaceID) {
                    let mappedLifecycleState = sharedLifecycleState(forRefreshError: error)
                    let inviteeState = FamilyShareInviteeViewState(
                        namespaceID: namespaceID,
                        ownerDisplayName: current.ownerDisplayName,
                        lifecycleState: mappedLifecycleState,
                        goalCount: mappedLifecycleState == .removedOrNoLongerShared ? 0 : (current.projectionPayload?.goals.count ?? current.inviteeState?.goalCount ?? 0),
                        lastUpdatedAt: current.inviteeState?.lastUpdatedAt,
                        asOfCopy: current.inviteeState?.asOfCopy,
                        titleCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                            lifecycleState: mappedLifecycleState,
                            fallback: current.inviteeState?.titleCopy
                        ),
                        messageCopy: sharedMessageCopy(for: mappedLifecycleState, fallback: current.inviteeState?.messageCopy),
                        primaryActionCopy: FamilyShareSurfaceState(rawValue: mappedLifecycleState.rawValue)?.primaryActionTitle ?? "Retry",
                        isReadOnly: true
                    )
                    let updatedPayload = mappedLifecycleState == .removedOrNoLongerShared ? nil : current.projectionPayload.map { payload in
                        FamilyShareProjectionPayload(
                            namespaceID: payload.namespaceID,
                            ownerDisplayName: payload.ownerDisplayName,
                            schemaVersion: payload.schemaVersion,
                            projectionVersion: payload.projectionVersion,
                            activeProjectionVersion: payload.activeProjectionVersion,
                            freshnessStateRawValue: mappedLifecycleState.rawValue,
                            lifecycleStateRawValue: payload.lifecycleStateRawValue,
                            publishedAt: payload.publishedAt,
                            lastReconciledAt: payload.lastReconciledAt,
                            lastRefreshAttemptAt: Date(),
                            lastRefreshErrorCode: (error as NSError).domain,
                            lastRefreshErrorMessage: error.localizedDescription,
                            summaryTitle: payload.summaryTitle,
                            summaryCopy: sharedMessageCopy(for: mappedLifecycleState, fallback: payload.summaryCopy),
                            participantCount: payload.participantCount,
                            pendingParticipantCount: payload.pendingParticipantCount,
                            revokedParticipantCount: payload.revokedParticipantCount,
                            goals: payload.goals,
                            ownerSections: payload.ownerSections,
                            rateSnapshotTimestamp: payload.rateSnapshotTimestamp,
                            projectionServerTimestamp: payload.projectionServerTimestamp,
                            contentHash: payload.contentHash
                        )
                    }
                    try? registry.seed(
                        FamilyShareSeededNamespaceState(
                            ownerDisplayName: current.ownerDisplayName,
                            ownerState: current.ownerState,
                            inviteeState: inviteeState,
                            projectionPayload: updatedPayload
                        )
                    )
                    await namespaceExecutionHub.markFailed(
                        with: FamilyShareSeededNamespaceState(
                            ownerDisplayName: current.ownerDisplayName,
                            ownerState: current.ownerState,
                            inviteeState: inviteeState,
                            projectionPayload: updatedPayload
                        ),
                        reason: error.localizedDescription
                    )
                    trackViewEvent(for: inviteeState)
                    return .failure(error)
                }
                return .failure(error)
            }
        }
        guard let current = try? await stateProvider.seededState(for: namespaceID) else {
            return .failure(FamilyShareCloudKitError.sharedProjectionMissing)
        }
        let currentState = current.inviteeState?.lifecycleState ?? .emptySharedDataset
        let refreshedState: FamilyShareLifecycleState
        switch currentState {
        case .temporarilyUnavailable, .stale:
            refreshedState = current.projectionPayload?.goals.isEmpty == false ? .active : .emptySharedDataset
        case .emptySharedDataset:
            refreshedState = current.projectionPayload?.goals.isEmpty == false ? .active : .emptySharedDataset
        case .active, .invitePendingAcceptance, .revoked, .removedOrNoLongerShared:
            refreshedState = currentState
        }

        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: current.ownerDisplayName,
            lifecycleState: refreshedState,
            goalCount: current.projectionPayload?.goals.count ?? current.inviteeState?.goalCount ?? 0,
            lastUpdatedAt: Date(),
            asOfCopy: Date().formatted(date: .abbreviated, time: .shortened),
            titleCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                lifecycleState: refreshedState,
                fallback: current.inviteeState?.titleCopy
            ),
            messageCopy: refreshedState == .active
                ? FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                    lifecycleState: .active,
                    fallback: current.inviteeState?.messageCopy
                )
                : (current.inviteeState?.messageCopy ?? "Shared goals are not ready yet."),
            primaryActionCopy: FamilyShareSurfaceState(rawValue: refreshedState.rawValue)?.primaryActionTitle ?? "Retry",
            isReadOnly: true
        )

        let updatedPayload = current.projectionPayload.map { payload in
            FamilyShareProjectionPayload(
                namespaceID: payload.namespaceID,
                ownerDisplayName: payload.ownerDisplayName,
                schemaVersion: payload.schemaVersion,
                projectionVersion: payload.projectionVersion,
                activeProjectionVersion: payload.activeProjectionVersion,
                freshnessStateRawValue: refreshedState.rawValue,
                lifecycleStateRawValue: payload.lifecycleStateRawValue,
                publishedAt: payload.publishedAt,
                lastReconciledAt: Date(),
                lastRefreshAttemptAt: Date(),
                lastRefreshErrorCode: nil,
                lastRefreshErrorMessage: nil,
                summaryTitle: payload.summaryTitle,
                summaryCopy: inviteeState.messageCopy,
                participantCount: payload.participantCount,
                pendingParticipantCount: payload.pendingParticipantCount,
                revokedParticipantCount: payload.revokedParticipantCount,
                goals: payload.goals,
                ownerSections: payload.ownerSections,
                rateSnapshotTimestamp: payload.rateSnapshotTimestamp,
                projectionServerTimestamp: payload.projectionServerTimestamp,
                contentHash: payload.contentHash
            )
        }

        try? registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: current.ownerDisplayName,
                ownerState: current.ownerState,
                inviteeState: inviteeState,
                projectionPayload: updatedPayload
            )
        )
        await namespaceExecutionHub.bootstrap(
            with: FamilyShareSeededNamespaceState(
                ownerDisplayName: current.ownerDisplayName,
                ownerState: current.ownerState,
                inviteeState: inviteeState,
                projectionPayload: updatedPayload
            )
        )
        trackViewEvent(for: inviteeState)
        return .success(updatedProjection: true)
    }

    private func sharedLifecycleState(forRefreshError error: Error) -> FamilyShareLifecycleState {
        if let familyError = error as? FamilyShareCloudKitError, familyError == .rootRecordMissing {
            return .removedOrNoLongerShared
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .unknownItem:
                return .removedOrNoLongerShared
            case .permissionFailure, .notAuthenticated:
                return .revoked
            default:
                break
            }
        }

        return .temporarilyUnavailable
    }

    private func sharedMessageCopy(for lifecycleState: FamilyShareLifecycleState, fallback: String?) -> String {
        switch lifecycleState {
        case .removedOrNoLongerShared:
            return "This shared goal set is no longer available."
        case .revoked:
            return "Access to this shared goal set was revoked. Ask the owner to share it again."
        case .temporarilyUnavailable:
            return "Shared goals are temporarily unavailable. Try again in a moment."
        case .stale:
            return "Shared goals may be out of date. Retry to refresh this goal set."
        case .emptySharedDataset:
            return "This shared goal set is available, but no goals are visible yet."
        case .invitePendingAcceptance:
            return "Finish accepting the invitation to view the shared goal set."
        case .active:
            return fallback ?? "Goals are grouped by owner and stay read-only."
        }
    }

    private func trackViewEvent(for inviteeState: FamilyShareInviteeViewState?) {
        guard let inviteeState else { return }
        let telemetryKey = "\(inviteeState.namespaceID.namespaceKey)|\(inviteeState.lifecycleState.rawValue)"
        guard trackedInviteeTelemetryKeys.insert(telemetryKey).inserted else { return }
        switch inviteeState.lifecycleState {
        case .invitePendingAcceptance:
            telemetry.track(.invitePendingViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .active:
            telemetry.track(.activeViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .emptySharedDataset:
            telemetry.track(.emptyViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .stale:
            telemetry.track(.refreshStale, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .temporarilyUnavailable:
            telemetry.track(.temporarilyUnavailableViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .revoked:
            telemetry.track(.revokedViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        case .removedOrNoLongerShared:
            telemetry.track(.removedViewed, payload: ["namespace": inviteeState.namespaceID.namespaceKey])
        }
    }

    private func trackInviteeViewTelemetry() {
        let sectionStates = inviteeProjection.sections.map { section -> FamilyShareInviteeViewState? in
            let namespaceID = section.namespaceID
            let lifecycleState = FamilyShareLifecycleState(rawValue: section.state.rawValue) ?? .active
            return FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: section.ownerIdentity.displayName,
                lifecycleState: lifecycleState,
                goalCount: section.goals.count,
                lastUpdatedAt: section.goals.first?.lastUpdatedAt,
                asOfCopy: nil,
                titleCopy: inviteeProjection.entryTitle,
                messageCopy: section.summaryCopy ?? section.state.supportingCopy,
                primaryActionCopy: section.primaryActionTitle ?? "Retry",
                isReadOnly: true
            )
        }
        (inviteeStates + sectionStates.compactMap { $0 }).forEach(trackViewEvent(for:))
    }

    private func quarantineNamespace(namespaceID: FamilyShareNamespaceID) async throws {
        guard let current = try await stateProvider.seededState(for: namespaceID) else {
            let quarantinedState = FamilyShareSeededNamespaceState(
                ownerDisplayName: namespaceID.ownerID,
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: namespaceID,
                    lifecycleState: .shareFailed,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 1,
                    summaryCopy: "Shared goals are temporarily unavailable while the cache is rebuilt.",
                    primaryActionCopy: "Share with Family"
                ),
                    inviteeState: FamilyShareInviteeViewState(
                        namespaceID: namespaceID,
                        ownerDisplayName: namespaceID.ownerID,
                        lifecycleState: .temporarilyUnavailable,
                        goalCount: 0,
                        lastUpdatedAt: nil,
                        asOfCopy: nil,
                        titleCopy: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
                        messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                            lifecycleState: .temporarilyUnavailable,
                            fallback: "Shared goals are temporarily unavailable while this namespace is rebuilt."
                        ),
                        primaryActionCopy: "Retry",
                        isReadOnly: true
                    ),
                projectionPayload: nil
            )
            try registry.seed(quarantinedState)
            await namespaceExecutionHub.markFailed(with: quarantinedState, reason: "quarantined")
            return
        }

        let quarantinedState = FamilyShareSeededNamespaceState(
            ownerDisplayName: current.ownerDisplayName,
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .shareFailed,
                participantCount: current.ownerState.participantCount,
                pendingParticipantCount: current.ownerState.pendingParticipantCount,
                activeParticipantCount: current.ownerState.activeParticipantCount,
                revokedParticipantCount: current.ownerState.revokedParticipantCount,
                failedParticipantCount: current.ownerState.failedParticipantCount + 1,
                summaryCopy: "Shared goals are temporarily unavailable while the cache is rebuilt.",
                primaryActionCopy: "Manage Participants"
            ),
            inviteeState: FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: current.ownerDisplayName,
                lifecycleState: .temporarilyUnavailable,
                goalCount: 0,
                lastUpdatedAt: current.inviteeState?.lastUpdatedAt,
                asOfCopy: current.inviteeState?.asOfCopy,
                titleCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                    lifecycleState: .temporarilyUnavailable,
                    fallback: current.inviteeState?.titleCopy
                ),
                messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                    lifecycleState: .temporarilyUnavailable,
                    fallback: "Shared goals are temporarily unavailable while this namespace is rebuilt."
                ),
                primaryActionCopy: "Retry",
                isReadOnly: true
            ),
            projectionPayload: nil
        )
        try registry.seed(quarantinedState)
        await namespaceExecutionHub.markFailed(with: quarantinedState, reason: "quarantined")
    }

    private func makeProjectionPayload(for goals: [Goal]) async throws -> FamilyShareProjectionPayload {
        let ownerName = normalizedOwnerDisplayName()
        let sortedGoals = goals.sorted {
            if $0.deadline != $1.deadline {
                return $0.deadline < $1.deadline
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let existingVersion = try registry.seededState(for: ownerNamespaceID)?.projectionPayload?.projectionVersion ?? 0
        let projectionVersion = max(existingVersion + 1, 1)
        let participantCount = ownerState.participantCount
        let pendingCount = ownerState.pendingParticipantCount
        let publishedAt = Date()
        let exchangeRateService = ExchangeRateService.shared

        // Build GoalProgressInput value types for the pure calculator
        let calculator = GoalProgressCalculator()
        let inputs = sortedGoals.map { goal in
            GoalProgressInput(
                goalID: goal.id,
                currency: goal.currency,
                targetAmount: Decimal(goal.targetAmount),
                allocations: (goal.allocations ?? []).compactMap { allocation in
                    guard let asset = allocation.asset else { return nil }
                    return AllocationInput(
                        assetCurrency: asset.currency,
                        allocatedAmount: Decimal(allocation.amountValue)
                    )
                }
            )
        }

        // Build rate snapshot from currently cached exchange rates
        var rateMap: [String: Decimal] = [:]
        var ratePairs: Set<String> = []
        for input in inputs {
            for alloc in input.allocations {
                let from = alloc.assetCurrency.uppercased()
                let to = input.currency.uppercased()
                if from != to {
                    let pairKey = CurrencyPair.canonicalKey(from: from, to: to)
                    ratePairs.insert(pairKey)
                    if rateMap[pairKey] == nil {
                        if let rate = try? await exchangeRateService.fetchRate(from: from, to: to) {
                            rateMap[pairKey] = Decimal(rate)
                        }
                    }
                }
            }
        }
        let rateTimestamp = exchangeRateService.rateSnapshotTimestamp(for: ratePairs) ?? publishedAt
        let rateSnapshot = RateSnapshot(rates: rateMap, timestamp: rateTimestamp)
        let progressResults = calculator.calculateProgress(for: inputs, rates: rateSnapshot)

        let goalPayloads = sortedGoals.enumerated().map { index, goal in
            let result = progressResults[goal.id]
            // Use calculator result; only fall back to manualTotal when rate conversion fails
            let currentAmount: Decimal
            let progressRatio: Double
            if let calcResult = result, calcResult.currentAmount > 0 || (goal.allocations ?? []).isEmpty {
                currentAmount = calcResult.currentAmount
                progressRatio = calcResult.progressRatio
            } else {
                // Fallback for goals where all rate conversions failed
                currentAmount = Decimal(goal.manualTotal)
                progressRatio = goal.targetAmount > 0 ? min(max(goal.manualTotal / goal.targetAmount, 0), 1) : 0
            }

            return FamilyShareProjectedGoalPayload(
                id: "\(ownerNamespaceID.namespaceKey)|\(goal.id.uuidString)",
                namespaceID: ownerNamespaceID,
                ownerID: ownerNamespaceID.ownerID,
                ownerDisplayName: ownerName,
                goalID: goal.id.uuidString,
                goalName: goal.name,
                goalEmoji: goal.emoji,
                currency: goal.currency,
                targetAmount: Decimal(goal.targetAmount),
                currentAmount: currentAmount,
                progressRatio: progressRatio,
                deadline: goal.deadline,
                goalStatusRawValue: goal.status,
                forecastStateRawValue: nil,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lastUpdatedAt: goal.lastModifiedDate,
                summaryCopy: FamilyShareOwnerIdentityResolver.canonicalGoalContributionSummary(
                    currency: goal.currency,
                    currentAmount: NSDecimalNumber(decimal: currentAmount).doubleValue,
                    targetAmount: goal.targetAmount
                ),
                sortIndex: index
            )
        }

        // Compute contentHash over all invitee-visible state
        let hasher = FamilyShareContentHasher()
        let goalData = goalPayloads.map { g in
            (goalID: UUID(uuidString: g.goalID) ?? UUID(), currentAmount: g.currentAmount, targetAmount: g.targetAmount)
        }
        let contentHash = hasher.hash(
            goalData: goalData,
            rateSnapshotTimestamp: rateTimestamp,
            ownerDisplayName: ownerName,
            participantIDs: ownerParticipants.map { $0.id }
        )

        let ownerSections = [
            FamilyShareOwnerSectionPayload(
                id: "\(ownerNamespaceID.namespaceKey)|\(ownerName.lowercased())|0",
                namespaceID: ownerNamespaceID,
                ownerID: ownerNamespaceID.ownerID,
                ownerDisplayName: ownerName,
                goalCount: goalPayloads.count,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                sortIndex: 0,
                inlineChipCopy: ownerName
            )
        ]

        return FamilyShareProjectionPayload(
            namespaceID: ownerNamespaceID,
            ownerDisplayName: ownerName,
            schemaVersion: FamilyShareCacheSchema.currentVersion,
            projectionVersion: projectionVersion,
            activeProjectionVersion: projectionVersion,
            freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
            lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
            publishedAt: publishedAt,
            lastReconciledAt: publishedAt,
            lastRefreshAttemptAt: publishedAt,
            lastRefreshErrorCode: nil,
            lastRefreshErrorMessage: nil,
            summaryTitle: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
            summaryCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: .active,
                fallback: "All current goals are shared in read-only mode."
            ),
            participantCount: participantCount,
            pendingParticipantCount: pendingCount,
            revokedParticipantCount: ownerState.revokedParticipantCount,
            goals: goalPayloads,
            ownerSections: ownerSections,
            rateSnapshotTimestamp: rateTimestamp,
            projectionServerTimestamp: nil, // Set from CKRecord.modificationDate after publish
            contentHash: contentHash
        )
    }

    private func normalizedOwnerDisplayName() -> String {
        FamilyShareOwnerIdentityResolver.resolve(displayName: identityStore.ownerDisplayName()).displayName
    }

    private func defaultOwnerState(for namespaceID: FamilyShareNamespaceID) -> FamilyShareOwnerViewState {
        FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .notShared,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Share all of your goals with family in read-only mode.",
            primaryActionCopy: "Share with Family"
        )
    }

    private func makeScopePreview(ownerName: String) -> FamilyShareScopePreviewModel {
        FamilyShareScopePreviewModel(
            ownerName: ownerName,
            summaryPoints: [
                "All current goals are shared.",
                "Future goals auto-share while access remains active.",
                "Invitees receive read-only visibility only."
            ],
            sections: [
                FamilyShareScopeDisclosureSection(
                    kind: .visibleData,
                    title: "Visible Data",
                    rows: [
                        "Goal name, emoji, target amount, deadline, and progress.",
                        "Current-month status and safe contribution summaries."
                    ]
                ),
                FamilyShareScopeDisclosureSection(
                    kind: .excludedData,
                    title: "Excluded Data",
                    rows: [
                        "Wallet addresses.",
                        "Raw transaction identifiers.",
                        "Planning drafts and operator tools."
                    ]
                ),
                FamilyShareScopeDisclosureSection(
                    kind: .revokeBehavior,
                    title: "Revoke Behavior",
                    rows: [
                        "Revocation removes invitee access without affecting owner data.",
                        "Removed participants must be invited again to regain access."
                    ]
                )
            ]
        )
    }

    private func fallbackParticipants(for state: FamilyShareOwnerViewState) -> [FamilyShareParticipantSnapshot] {
        guard cloudSync == nil || lastSeededScenario != nil else {
            return []
        }
        return synthesizeParticipants(from: state)
    }

    private func synthesizeParticipants(from state: FamilyShareOwnerViewState) -> [FamilyShareParticipantSnapshot] {
        var participants: [FamilyShareParticipantSnapshot] = []

        for index in 0..<state.activeParticipantCount {
            participants.append(
                FamilyShareParticipantSnapshot(
                    id: "active-\(index + 1)",
                    displayName: "Family Member \(index + 1)",
                    emailOrAlias: "Accepted",
                    state: .active,
                    lastUpdatedAt: Date(),
                    isCurrentUser: false
                )
            )
        }

        for index in 0..<state.pendingParticipantCount {
            participants.append(
                FamilyShareParticipantSnapshot(
                    id: "pending-\(index + 1)",
                    displayName: "Pending Invite \(index + 1)",
                    emailOrAlias: "Waiting for acceptance",
                    state: .pending,
                    lastUpdatedAt: Date(),
                    isCurrentUser: false
                )
            )
        }

        for index in 0..<state.revokedParticipantCount {
            participants.append(
                FamilyShareParticipantSnapshot(
                    id: "revoked-\(index + 1)",
                    displayName: "Removed Invite \(index + 1)",
                    emailOrAlias: "Access revoked",
                    state: .revoked,
                    lastUpdatedAt: Date(),
                    isCurrentUser: false
                )
            )
        }

        for index in 0..<state.failedParticipantCount {
            participants.append(
                FamilyShareParticipantSnapshot(
                    id: "failed-\(index + 1)",
                    displayName: "Delivery Issue \(index + 1)",
                    emailOrAlias: "Needs retry",
                    state: .failed,
                    lastUpdatedAt: Date(),
                    isCurrentUser: false
                )
            )
        }

        return participants
    }

    private func mapParticipantState(_ state: FamilyShareParticipantLifecycleState) -> FamilyShareParticipantState {
        switch state {
        case .pending:
            return .pending
        case .active:
            return .active
        case .revoked:
            return .revoked
        case .failed:
            return .failed
        }
    }

    private func mapSurfaceState(ownerLifecycleState: FamilyShareOwnerLifecycleState) -> FamilyShareSurfaceState {
        switch ownerLifecycleState {
        case .notShared:
            return .emptySharedDataset
        case .invitePending:
            return .invitePendingAcceptance
        case .sharedActive:
            return .active
        case .revoked:
            return .revoked
        case .shareFailed:
            return .temporarilyUnavailable
        }
    }
}

#if canImport(UIKit)
import CloudKit

@MainActor
final class FamilyShareSceneDelegateBridge: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard connectionOptions.cloudKitShareMetadata != nil else { return }
        FamilyShareSceneBridgeHub.shared.acceptanceSink?.acceptPendingInvitation(from: connectionOptions)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        FamilyShareSceneBridgeHub.shared.acceptanceSink?.acceptInvitation(cloudKitShareMetadata)
    }
}

extension FamilyShareInvitationMetadataSnapshot {
    init(metadata: CKShare.Metadata) {
        let rootRecordID = metadata.rootRecord?.recordID
        self.init(
            ownerDisplayName: metadata.ownerIdentity.nameComponents?.formatted() ?? "Shared Family",
            shareURLString: metadata.share.url?.absoluteString,
            participantStatusRawValue: String(describing: metadata.participantStatus),
            participantRoleRawValue: String(describing: metadata.participantRole),
            participantPermissionRawValue: String(describing: metadata.participantPermission),
            rootRecordName: rootRecordID?.recordName,
            rootZoneName: rootRecordID?.zoneID.zoneName,
            rootZoneOwnerName: rootRecordID?.zoneID.ownerName,
            hierarchicalRootRecordName: metadata.hierarchicalRootRecordID?.recordName,
            hierarchicalRootZoneName: metadata.hierarchicalRootRecordID?.zoneID.zoneName,
            hierarchicalRootZoneOwnerName: metadata.hierarchicalRootRecordID?.zoneID.ownerName
        )
    }
}
#endif

private extension FamilyShareProjectionPayload {
    func migratedForCurrentFreshnessSchema(currentVersion: Int) -> FamilyShareProjectionPayload {
        return FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            schemaVersion: currentVersion,
            projectionVersion: projectionVersion,
            activeProjectionVersion: activeProjectionVersion,
            freshnessStateRawValue: freshnessStateRawValue,
            lifecycleStateRawValue: lifecycleStateRawValue,
            publishedAt: publishedAt,
            lastReconciledAt: lastReconciledAt,
            lastRefreshAttemptAt: lastRefreshAttemptAt,
            lastRefreshErrorCode: lastRefreshErrorCode,
            lastRefreshErrorMessage: lastRefreshErrorMessage,
            summaryTitle: summaryTitle,
            summaryCopy: summaryCopy,
            participantCount: participantCount,
            pendingParticipantCount: pendingParticipantCount,
            revokedParticipantCount: revokedParticipantCount,
            goals: goals,
            ownerSections: ownerSections,
            rateSnapshotTimestamp: rateSnapshotTimestamp ?? publishedAt,
            projectionServerTimestamp: projectionServerTimestamp,
            contentHash: contentHash
        )
    }

    func updatingSchemaVersion(_ schemaVersion: Int) -> FamilyShareProjectionPayload {
        FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            schemaVersion: schemaVersion,
            projectionVersion: projectionVersion,
            activeProjectionVersion: activeProjectionVersion,
            freshnessStateRawValue: freshnessStateRawValue,
            lifecycleStateRawValue: lifecycleStateRawValue,
            publishedAt: publishedAt,
            lastReconciledAt: lastReconciledAt,
            lastRefreshAttemptAt: lastRefreshAttemptAt,
            lastRefreshErrorCode: lastRefreshErrorCode,
            lastRefreshErrorMessage: lastRefreshErrorMessage,
            summaryTitle: summaryTitle,
            summaryCopy: summaryCopy,
            participantCount: participantCount,
            pendingParticipantCount: pendingParticipantCount,
            revokedParticipantCount: revokedParticipantCount,
            goals: goals,
            ownerSections: ownerSections,
            rateSnapshotTimestamp: rateSnapshotTimestamp,
            projectionServerTimestamp: projectionServerTimestamp,
            contentHash: contentHash
        )
    }

    func updatingLifecycleState(_ lifecycleStateRawValue: String) -> FamilyShareProjectionPayload {
        FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: ownerDisplayName,
            schemaVersion: schemaVersion,
            projectionVersion: projectionVersion,
            activeProjectionVersion: activeProjectionVersion,
            freshnessStateRawValue: freshnessStateRawValue,
            lifecycleStateRawValue: lifecycleStateRawValue,
            publishedAt: publishedAt,
            lastReconciledAt: lastReconciledAt,
            lastRefreshAttemptAt: lastRefreshAttemptAt,
            lastRefreshErrorCode: lastRefreshErrorCode,
            lastRefreshErrorMessage: lastRefreshErrorMessage,
            summaryTitle: summaryTitle,
            summaryCopy: summaryCopy,
            participantCount: participantCount,
            pendingParticipantCount: pendingParticipantCount,
            revokedParticipantCount: revokedParticipantCount,
            goals: goals,
            ownerSections: ownerSections,
            rateSnapshotTimestamp: rateSnapshotTimestamp,
            projectionServerTimestamp: projectionServerTimestamp,
            contentHash: contentHash
        )
    }
}
