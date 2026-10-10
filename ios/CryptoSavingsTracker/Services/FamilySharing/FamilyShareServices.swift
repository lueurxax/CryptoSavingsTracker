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

enum FamilyShareProjectionBuildError: LocalizedError, Equatable {
    case incompleteExchangeRates([String])
    case missingGoalProgress(UUID)
    case orphanedAllocation(UUID)

    var errorDescription: String? {
        switch self {
        case .incompleteExchangeRates(let pairs):
            let pairList = pairs.joined(separator: ", ")
            return "Family progress was not published because exchange rates are unavailable for \(pairList)."
        case .missingGoalProgress:
            return "Family progress was not published because a goal calculation could not be completed."
        case .orphanedAllocation:
            return "Family progress was not published because one or more allocations no longer reference an asset."
        }
    }
}

private struct FamilyShareGoalProjectionSnapshot: Sendable {
    let id: UUID
    let name: String
    let emoji: String?
    let currency: String
    let targetAmount: Decimal
    let targetAmountValue: Double
    let deadline: Date
    let lastModifiedAt: Date
    let progressInput: GoalProgressInput
}

private struct FamilyShareExplicitIntentFingerprint: Equatable, Sendable {
    private struct GoalValue: Equatable, Sendable {
        struct AllocationValue: Equatable, Sendable {
            let assetCurrency: String
            let allocatedAmount: Decimal
        }

        let id: UUID
        let name: String
        let emoji: String?
        let currency: String
        let targetAmount: Decimal
        let targetAmountValue: Double
        let deadline: Date
        let lastModifiedAt: Date
        let allocations: [AllocationValue]

        init(snapshot: FamilyShareGoalProjectionSnapshot) {
            id = snapshot.id
            name = snapshot.name
            emoji = snapshot.emoji
            currency = snapshot.currency
            targetAmount = snapshot.targetAmount
            targetAmountValue = snapshot.targetAmountValue
            deadline = snapshot.deadline
            lastModifiedAt = snapshot.lastModifiedAt
            allocations = snapshot.progressInput.allocations.map {
                AllocationValue(
                    assetCurrency: $0.assetCurrency,
                    allocatedAmount: $0.allocatedAmount
                )
            }
        }
    }

    private let goals: [GoalValue]

    init(goalSnapshots: [FamilyShareGoalProjectionSnapshot]) {
        goals = goalSnapshots.map(GoalValue.init(snapshot:))
    }
}

private struct FamilyShareProjectionBuildResult: Sendable {
    let payload: FamilyShareProjectionPayload
    let rateSnapshot: RateSnapshot
    let goalInputs: [GoalProgressInput]
}

private struct FamilySharePublicationInvalidatedByRevocationError: LocalizedError {
    var errorDescription: String? {
        "Family access revocation is still pending."
    }
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
    private let revocationTombstoneStore: FamilyShareRevocationTombstoneStore

    init(
        registry: FamilyShareNamespaceRegistry? = nil,
        cloudSync: FamilyShareCloudSyncing? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker(),
        revocationTombstoneStore: FamilyShareRevocationTombstoneStore = FamilyShareRevocationTombstoneStore()
    ) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
        self.cloudSync = cloudSync
        self.telemetry = telemetry
        self.revocationTombstoneStore = revocationTombstoneStore
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

        guard let cloudSync else {
            let error = FamilyShareCloudKitError.accountUnavailable
            telemetry.track(
                .sharePublishFailed,
                payload: [
                    "namespace": payload.namespaceID.namespaceKey,
                    "reason": error.localizedDescription
                ]
            )
            throw error
        }

        do {
            try await cloudSync.publishProjection(payload)
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

        guard revocationTombstoneStore.isPending(namespaceKey: payload.namespaceID.namespaceKey) == false else {
            // The remote write may have committed after revoke. Keep the local
            // last-known-good revoked state and route through compensating delete.
            throw FamilySharePublicationInvalidatedByRevocationError()
        }

        // Capture server-assigned timestamp from CloudKit after publish
        let serverTimestamp = (cloudSync as? DefaultFamilyShareCloudKitStore)?.lastPublishServerTimestamp
        var acknowledgedPayload = payload
        acknowledgedPayload.projectionServerTimestamp = serverTimestamp ?? payload.projectionServerTimestamp

        // The registry is the authoritative last-known-good projection. Advance it
        // only after the remote transport has acknowledged the same payload.
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: payload.ownerDisplayName,
                ownerState: ownerState,
                inviteeState: inviteeState,
                projectionPayload: acknowledgedPayload
            )
        )

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
        let currentState = try await stateProvider.seededState(for: namespaceID)
        try await cloudSync?.revoke(namespaceID: namespaceID)
        telemetry.track(.revoked, payload: ["namespace": namespaceID.namespaceKey])
        guard let currentState else { return }

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
    let containerProvider: FamilyShareContainerProvider

    var container: CKContainer { containerProvider() }
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
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let revocationTombstoneStore: FamilyShareRevocationTombstoneStore
    private let revocationRetryScheduler: any FamilyShareScheduler
    private let revocationRetryPolicy: FamilyShareFreshnessPolicy
    private var trackedInviteeTelemetryKeys: Set<String> = []
    private struct RefreshWaiter {
        let requestID: Int
        let continuation: CheckedContinuation<Void, Never>
    }
    private var refreshRequestID = 0
    private var completedRefreshRequestID = 0
    private var refreshDrainRunning = false
    private var refreshWaiters: [RefreshWaiter] = []
    private var ownerLifecycleAuthorityGeneration = 0

    // MARK: - Freshness Pipeline Components

    private let autoRepublishCoordinator: FamilyShareProjectionAutoRepublishCoordinator
    private let mutationObserver: FamilyShareProjectionMutationObserver
    private let inviteeRefreshScheduler: FamilyShareInviteeRefreshScheduler
    private let rateRefreshDriver: FamilyShareForegroundRateRefreshDriver?
    private let rateDriftEvaluator: FamilyShareRateDriftEvaluator
    private var freshnessPipelineActive = false
    private var ownerFreshnessPipelineActive = false
    private var ownerAutoRepublishConfigured = false
    private var ownerPublicationEpoch = 0
    private var explicitShareInProgress = false
    private var explicitShareRevocationGeneration = 0
    private struct ExplicitShareIntent {
        let id: Int
        let goalSnapshots: [FamilyShareGoalProjectionSnapshot]
        let fingerprint: FamilyShareExplicitIntentFingerprint
        let revocationGeneration: Int
    }
    private struct PendingExplicitCatchUp {
        let explicitIntent: ExplicitShareIntent
        var explicitDidComplete: Bool
        var isDurablyMarked: Bool
    }
    private var nextExplicitShareIntentID = 0
    private var explicitShareIntentQueue: [ExplicitShareIntent] = []
    private var activeExplicitShareIntent: ExplicitShareIntent?
    private var pendingExplicitCatchUp: PendingExplicitCatchUp?
    private var explicitShareIntentWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var isDrainingExplicitShareIntents = false
    private var ownerPublicationsInFlight = 0
    private var ownerPublicationWaiters: [CheckedContinuation<Void, Never>] = []
    private enum OwnerRevocationOperationOutcome: Sendable {
        case completed
        case acknowledgedAwaitingPublicationSettlement
        case failed(message: String)
    }
    private var ownerRevocationOperationGeneration = 0
    private var ownerRevocationOperation: Task<OwnerRevocationOperationOutcome, Never>?
    private var revocationRetryHandle: (any FamilyShareCancellable)?
    private var revocationRetryFailureCount = 0
    private var initialRefreshTask: Task<Void, Never>?

    var sharedSections: [FamilyShareInviteeSectionProjection] {
        inviteeProjection.sections
    }

    var refreshRequestCountForTesting: Int {
        refreshRequestID
    }

    func waitForInitialRefreshForTesting() async {
        await initialRefreshTask?.value
    }

    func autoRepublishDebugSnapshotForTesting() async
        -> FamilyShareAutoRepublishDebugSnapshot {
        await autoRepublishCoordinator.debugSnapshotForTesting()
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
        activeGoalsProvider: (() throws -> [Goal])? = nil,
        exchangeRateService: ExchangeRateServiceProtocol? = nil,
        revocationTombstoneStore: FamilyShareRevocationTombstoneStore = FamilyShareRevocationTombstoneStore(),
        revocationRetryScheduler: any FamilyShareScheduler = GCDScheduler(),
        revocationRetryPolicy: FamilyShareFreshnessPolicy = FamilyShareFreshnessPolicy(),
        autoRepublishScheduler: any FamilyShareScheduler = GCDScheduler(),
        autoRepublishDirtyStateStore: FamilyShareDirtyStateStore = FamilyShareDirtyStateStore(),
        startsInitialRefreshTask: Bool = true
    ) {
        let resolvedRegistry = registry ?? FamilyShareNamespaceRegistry()
        let resolvedStateProvider = stateProvider ?? DefaultFamilyShareStateProvider(registry: resolvedRegistry)
        let resolvedInviteeProvider = inviteeStateProvider ?? DefaultFamilyShareStateProvider(registry: resolvedRegistry)
        let resolvedExchangeRateService = exchangeRateService ?? ExchangeRateService.shared
        let resolvedPublisher = DefaultFamilyShareProjectionPublisher(
            registry: resolvedRegistry,
            cloudSync: cloudSync,
            telemetry: telemetry,
            revocationTombstoneStore: revocationTombstoneStore
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
        self.exchangeRateService = resolvedExchangeRateService
        self.revocationTombstoneStore = revocationTombstoneStore
        self.revocationRetryScheduler = revocationRetryScheduler
        self.revocationRetryPolicy = revocationRetryPolicy
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
            scheduler: autoRepublishScheduler,
            dirtyStateStore: autoRepublishDirtyStateStore,
            rollout: rollout
        )
        self.mutationObserver = FamilyShareProjectionMutationObserver(rollout: rollout)
        self.inviteeRefreshScheduler = FamilyShareInviteeRefreshScheduler(rollout: rollout)
        self.rateDriftEvaluator = FamilyShareRateDriftEvaluator(rollout: rollout)

        // Rate refresh driver needs ExchangeRateService — use DIContainer if available
        if rollout.isFreshnessPipelineEnabled() {
            self.rateRefreshDriver = FamilyShareForegroundRateRefreshDriver(
                exchangeRateService: resolvedExchangeRateService,
                rollout: rollout
            )
        } else {
            self.rateRefreshDriver = nil
        }

        FamilyShareSceneBridgeHub.shared.acceptanceSink = self

        if startsInitialRefreshTask {
            initialRefreshTask = Task { [weak self] in
                guard let self else { return }
                _ = await self.retryPendingOwnerRevocationIfNeeded()
                await self.refreshAllState()
            }
        }
    }

    /// Wire the freshness pipeline into production lifecycle.
    private func startFreshnessPipeline() async {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        guard freshnessPipelineActive == false else { return }
        freshnessPipelineActive = true

        inviteeRefreshScheduler.setRefreshAction { [weak self] namespaceKey in
            guard let self else { return .failure(FamilyShareCloudKitError.sharedProjectionMissing) }
            guard let namespaceID = self.resolveNamespaceID(for: namespaceKey) else {
                return .failure(FamilyShareCloudKitError.sharedProjectionMissing)
            }
            let result = await self.refreshNamespace(namespaceID)
            await self.refreshAllState()
            return result
        }
    }

    private func reconcileOwnerFreshnessPipeline(
        for ownerState: FamilyShareOwnerViewState
    ) async {
        guard rollout.isFreshnessPipelineEnabled() else {
            await teardownOwnerFreshnessPipelineIfNeeded(
                preservingAutomaticDirtyState: false,
                forceCoordinatorTeardown: true,
                cause: "rolloutDisabled"
            )
            return
        }
        guard explicitShareInProgress == false else {
            return
        }

        if ownerState.lifecycleState == .revoked {
            // A confirmed remote revoke terminates every unpublished catch-up.
            // Force teardown because a prior inactive lifecycle may already have
            // stopped the in-memory pipeline while leaving durable dirty state.
            let preservesFreshReshare =
                hasCurrentActiveExplicitIntentCatchUp
            if preservesFreshReshare == false {
                pendingExplicitCatchUp = nil
            }
            await teardownOwnerFreshnessPipelineIfNeeded(
                preservingAutomaticDirtyState: preservesFreshReshare,
                forceCoordinatorTeardown: true,
                cause: "remoteRevoked"
            )
            return
        }

        if shouldRunOwnerRateRefreshDriver(for: ownerState) {
            await startOwnerFreshnessPipelineIfNeeded()
            await retryPendingExplicitCatchUpIfPossible(
                attemptImmediately: false
            )
        } else {
            // `.notShared` and `.shareFailed` can be transient/stale remote
            // observations. Preserve any durable publication obligation until
            // sharing becomes active again or a definitive revoke is observed.
            await teardownOwnerFreshnessPipelineIfNeeded(
                preservingAutomaticDirtyState: true,
                forceCoordinatorTeardown: true,
                cause: "remoteInactive"
            )
        }
    }

    private func startOwnerFreshnessPipelineIfNeeded() async {
        guard ownerFreshnessPipelineActive == false else {
            rateRefreshDriver?.start()
            return
        }
        let startEpoch = ownerPublicationEpoch
        ownerFreshnessPipelineActive = true

        await configureAutoRepublishCoordinator()
        guard ownerFreshnessPipelineActive,
              isOwnerPublicationAuthorized(
                epoch: startEpoch,
                allowsInactiveLifecycle: false
              )
        else {
            if explicitShareInProgress == false {
                await teardownOwnerFreshnessPipelineIfNeeded()
            }
            return
        }
        await autoRepublishCoordinator.activateAutomaticPublishing()

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
        let initialProjection = (try? registry.seededState(for: ownerNamespaceID))?.projectionPayload
        let initialPublishedAmounts = initialProjection?.goals.reduce(into: [UUID: Decimal]()) { partialResult, goal in
            guard let goalID = UUID(uuidString: goal.goalID) else { return }
            partialResult[goalID] = goal.currentAmount
        } ?? [:]
        let initialInputs = makeGoalProgressInputs(from: initialGoals)
        let initialRateSnapshot: RateSnapshot?
        if initialProjection != nil {
            initialRateSnapshot = await fetchRateSnapshot(for: initialInputs)
        } else {
            initialRateSnapshot = nil
        }
        guard ownerFreshnessPipelineActive,
              isOwnerPublicationAuthorized(
                epoch: startEpoch,
                allowsInactiveLifecycle: false
              )
        else {
            if explicitShareInProgress == false {
                await teardownOwnerFreshnessPipelineIfNeeded()
            }
            return
        }
        await rateDriftEvaluator.start(
            goalInputs: initialInputs,
            lastPublished: initialPublishedAmounts,
            initialRateSnapshot: initialRateSnapshot,
            handler: { [weak self] reason in
                guard let self else { return }
                Task {
                    await self.autoRepublishCoordinator.markDirty(reason: reason)
                }
            }
        )
        guard ownerFreshnessPipelineActive,
              isOwnerPublicationAuthorized(
                epoch: startEpoch,
                allowsInactiveLifecycle: false
              )
        else {
            if explicitShareInProgress == false {
                await teardownOwnerFreshnessPipelineIfNeeded()
            }
            return
        }

        if shouldRunOwnerRateRefreshDriver(for: ownerState) {
            rateRefreshDriver?.start()
        } else {
            rateRefreshDriver?.suspend()
        }
    }

    private func configureAutoRepublishCoordinator() async {
        let payloadBuilder = {
            [weak self] () async throws -> FamilyShareProjectionAutoPublishOutcome in
            guard let self else { return .suppressed }
            let publicationEpoch = self.ownerPublicationEpoch
            let allowsInactiveLifecycle = self.explicitShareInProgress
            guard self.isOwnerPublicationAuthorized(
                epoch: publicationEpoch,
                allowsInactiveLifecycle: allowsInactiveLifecycle
            ) else {
                return .suppressed
            }
            let goals = try self.fetchAuthoritativeGoalsForPublication()
            let outcome = try await self.publishProjectionImmediately(
                for: goals,
                publicationEpoch: publicationEpoch,
                allowsInactiveLifecycle: allowsInactiveLifecycle
            )
            if case .suppressed = outcome {
                return outcome
            }
            await self.completePendingExplicitCatchUpAfterAutomaticPublication(
                publicationEpoch: publicationEpoch,
                allowsInactiveLifecycle: allowsInactiveLifecycle
            )
            return outcome
        }
        await autoRepublishCoordinator.setPublishAction(payloadBuilder)
        await autoRepublishCoordinator.setRemoteChangeDateProvider { [weak self] in
            guard let self else { return nil }
            return self.lastKnownOwnerProjectionServerTimestamp()
        }
        ownerAutoRepublishConfigured = true
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

    /// Automatic publication must never substitute a stale explicit-intent cache
    /// when the authoritative SwiftData fetch fails.
    private func fetchAuthoritativeGoalsForPublication() throws -> [Goal] {
        let goals = try activeGoalsProvider()
        lastSharedGoals = goals
        return goals
    }

    /// Update the shared goals cache with fresh goal references.
    /// Called from shareAllGoals and when goals change via mutation observer.
    func updateSharedGoalsCache(_ goals: [Goal]) {
        lastSharedGoals = goals
    }

    func refreshAllState() async {
        refreshRequestID &+= 1
        let requestID = refreshRequestID
        await withCheckedContinuation { continuation in
            refreshWaiters.append(
                RefreshWaiter(
                    requestID: requestID,
                    continuation: continuation
                )
            )
            guard refreshDrainRunning == false else {
                return
            }
            refreshDrainRunning = true
            Task { @MainActor in
                await self.drainRefreshRequests()
            }
        }
    }

    private func drainRefreshRequests() async {
        while completedRefreshRequestID < refreshRequestID {
            let batchRequestID = refreshRequestID
            let lifecycleAuthorityGeneration =
                ownerLifecycleAuthorityGeneration
            await performRefreshPass(
                lifecycleAuthorityGeneration: lifecycleAuthorityGeneration
            )
            completedRefreshRequestID = batchRequestID
            resumeCompletedRefreshWaiters()
        }
        refreshDrainRunning = false
    }

    private func resumeCompletedRefreshWaiters() {
        let completedWaiters = refreshWaiters.filter {
            $0.requestID <= completedRefreshRequestID
        }
        refreshWaiters.removeAll {
            $0.requestID <= completedRefreshRequestID
        }
        completedWaiters.forEach {
            $0.continuation.resume()
        }
    }

    private func performRefreshPass(
        lifecycleAuthorityGeneration: Int
    ) async {
        guard rollout.isEnabled() else {
            await teardownFreshnessPipelineIfNeeded()
            return
        }
        guard revocationTombstoneStore.isPending(namespaceKey: ownerNamespaceID.namespaceKey) == false else {
            await holdOwnerLifecycleInactiveWhileRevocationIsPending()
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

            guard lifecycleAuthorityGeneration
                    == ownerLifecycleAuthorityGeneration,
                  revocationTombstoneStore.isPending(
                      namespaceKey: ownerNamespaceID.namespaceKey
                  ) == false
            else {
                if revocationTombstoneStore.isPending(
                    namespaceKey: ownerNamespaceID.namespaceKey
                ) {
                    await holdOwnerLifecycleInactiveWhileRevocationIsPending()
                }
                return
            }
            ownerState = resolvedOwnerState
            ownerParticipants = resolvedOwnerParticipants
            await reconcileOwnerFreshnessPipeline(for: resolvedOwnerState)
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
            guard lifecycleAuthorityGeneration
                    == ownerLifecycleAuthorityGeneration,
                  revocationTombstoneStore.isPending(
                      namespaceKey: ownerNamespaceID.namespaceKey
                  ) == false
            else {
                if revocationTombstoneStore.isPending(
                    namespaceKey: ownerNamespaceID.namespaceKey
                ) {
                    await holdOwnerLifecycleInactiveWhileRevocationIsPending()
                }
                return
            }
            latestErrorMessage = error.localizedDescription
            inviteeStates = []
            inviteeProjection = .empty
            ownerState = defaultOwnerState(for: ownerNamespaceID)
            ownerParticipants = []
            await reconcileOwnerFreshnessPipeline(for: ownerState)
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
        let goalSnapshots: [FamilyShareGoalProjectionSnapshot]
        do {
            goalSnapshots = try makeGoalProjectionSnapshots(from: goals)
        } catch {
            latestErrorMessage = error.localizedDescription
            return
        }

        // Keep only a best-effort live cache for automatic rebuilds. Explicit
        // publication below consumes the immutable call-time snapshots instead.
        lastSharedGoals = goals

        let fingerprint = FamilyShareExplicitIntentFingerprint(
            goalSnapshots: goalSnapshots
        )
        let revocationGeneration = explicitShareRevocationGeneration
        await withCheckedContinuation { continuation in
            let intentID: Int
            if let queuedIntent = explicitShareIntentQueue.last,
               queuedIntent.fingerprint == fingerprint,
               queuedIntent.revocationGeneration == revocationGeneration {
                intentID = queuedIntent.id
            } else if explicitShareIntentQueue.isEmpty,
                      let activeIntent = activeExplicitShareIntent,
                      activeIntent.fingerprint == fingerprint,
                      activeIntent.revocationGeneration == revocationGeneration {
                intentID = activeIntent.id
            } else {
                nextExplicitShareIntentID &+= 1
                intentID = nextExplicitShareIntentID
                explicitShareIntentQueue.append(
                    ExplicitShareIntent(
                        id: intentID,
                        goalSnapshots: goalSnapshots,
                        fingerprint: fingerprint,
                        revocationGeneration: revocationGeneration
                    )
                )
            }
            explicitShareIntentWaiters[intentID, default: []].append(continuation)
            guard isDrainingExplicitShareIntents == false else {
                return
            }
            isDrainingExplicitShareIntents = true
            Task { @MainActor in
                await self.drainExplicitShareIntents()
            }
        }
    }

    private func drainExplicitShareIntents() async {
        var completedWaiters: [CheckedContinuation<Void, Never>] = []

        while true {
            while explicitShareIntentQueue.isEmpty == false {
                let intent = explicitShareIntentQueue.removeFirst()
                activeExplicitShareIntent = intent
                let didComplete: Bool
                if intent.revocationGeneration == explicitShareRevocationGeneration {
                    let inheritedDurableMarker: Bool
                    if let superseded = pendingExplicitCatchUp,
                       superseded.isDurablyMarked,
                       superseded.explicitIntent.id != intent.id {
                        await autoRepublishCoordinator.supersedeExplicitCatchUp(
                            oldToken: superseded.explicitIntent.id,
                            newToken: intent.id,
                            reason: catchUpReason(
                                affectedGoalIDs: Set(intent.goalSnapshots.map(\.id))
                            )
                        )
                        inheritedDurableMarker = true
                    } else {
                        inheritedDurableMarker = false
                    }
                    pendingExplicitCatchUp = PendingExplicitCatchUp(
                        explicitIntent: intent,
                        explicitDidComplete: false,
                        isDurablyMarked: inheritedDurableMarker
                    )
                    didComplete = await performShareAllGoals(
                        intent.goalSnapshots,
                        revocationGeneration: intent.revocationGeneration
                    )
                } else {
                    didComplete = false
                }
                if var currentPending = pendingExplicitCatchUp,
                   currentPending.explicitIntent.id == intent.id,
                   currentPending.explicitIntent.revocationGeneration
                    == intent.revocationGeneration,
                   intent.revocationGeneration == explicitShareRevocationGeneration {
                    currentPending.explicitDidComplete = didComplete
                    pendingExplicitCatchUp = currentPending
                }
                activeExplicitShareIntent = nil
                completedWaiters.append(
                    contentsOf: explicitShareIntentWaiters.removeValue(forKey: intent.id) ?? []
                )
            }

            await retryPendingExplicitCatchUpIfPossible(
                attemptImmediately: true
            )
            if explicitShareIntentQueue.isEmpty {
                break
            }
        }

        isDrainingExplicitShareIntents = false
        completedWaiters.forEach { $0.resume() }
    }

    private func retryPendingExplicitCatchUpIfPossible(
        attemptImmediately: Bool
    ) async {
        guard let pending = pendingExplicitCatchUp else {
            return
        }
        let explicitIntent = pending.explicitIntent
        let revocationGeneration = explicitIntent.revocationGeneration
        guard revocationGeneration == explicitShareRevocationGeneration,
              revocationTombstoneStore.isPending(
                  namespaceKey: ownerNamespaceID.namespaceKey
              ) == false
        else {
            pendingExplicitCatchUp = nil
            return
        }

        let explicitGoalIDs = Set(explicitIntent.goalSnapshots.map(\.id))
        guard explicitShareInProgress == false,
              ownerFreshnessPipelineActive,
              ownerAutoRepublishConfigured
        else {
            await retainPendingExplicitCatchUp(
                pending,
                affectedGoalIDs: explicitGoalIDs
            )
            return
        }

        let publicationEpoch = ownerPublicationEpoch
        guard isOwnerPublicationAuthorized(
                  epoch: publicationEpoch,
                  allowsInactiveLifecycle: false
              )
        else {
            await retainPendingExplicitCatchUp(
                pending,
                affectedGoalIDs: explicitGoalIDs
            )
            return
        }

        let authoritativeGoals: [Goal]
        let authoritativeSnapshots: [FamilyShareGoalProjectionSnapshot]
        do {
            authoritativeGoals = try fetchAuthoritativeGoalsForPublication()
            authoritativeSnapshots = try makeGoalProjectionSnapshots(
                from: authoritativeGoals
            )
        } catch {
            latestErrorMessage = error.localizedDescription
            await retainPendingExplicitCatchUp(
                pending,
                affectedGoalIDs: explicitGoalIDs
            )
            guard attemptImmediately else {
                return
            }
            do {
                _ = try await autoRepublishCoordinator.publishNow(
                    reason: catchUpReason(affectedGoalIDs: explicitGoalIDs)
                )
            } catch {
                guard revocationGeneration == explicitShareRevocationGeneration else {
                    return
                }
                latestErrorMessage = error.localizedDescription
            }
            return
        }

        let affectedGoalIDs = explicitGoalIDs.union(authoritativeGoals.map(\.id))
        let fingerprintsMatch = FamilyShareExplicitIntentFingerprint(
            goalSnapshots: authoritativeSnapshots
        ) == explicitIntent.fingerprint
        if pending.explicitDidComplete,
           fingerprintsMatch {
            await autoRepublishCoordinator.acknowledgeExplicitCatchUp(
                token: explicitIntent.id
            )
            pendingExplicitCatchUp = nil
            return
        }

        await retainPendingExplicitCatchUp(
            pending,
            affectedGoalIDs: affectedGoalIDs
        )
        guard attemptImmediately,
              revocationGeneration == explicitShareRevocationGeneration,
              ownerPublicationEpoch == publicationEpoch,
              isOwnerPublicationAuthorized(
                  epoch: publicationEpoch,
                  allowsInactiveLifecycle: false
              )
        else {
            return
        }

        do {
            _ = try await autoRepublishCoordinator.publishNow(
                reason: catchUpReason(affectedGoalIDs: affectedGoalIDs)
            )
            guard revocationGeneration == explicitShareRevocationGeneration else {
                pendingExplicitCatchUp = nil
                return
            }
            guard ownerPublicationEpoch == publicationEpoch,
                  isOwnerPublicationAuthorized(
                      epoch: publicationEpoch,
                      allowsInactiveLifecycle: false
                  )
            else {
                if let currentPending = pendingExplicitCatchUp {
                    await retainPendingExplicitCatchUp(
                        currentPending,
                        affectedGoalIDs: affectedGoalIDs
                    )
                }
                return
            }
        } catch {
            guard revocationGeneration == explicitShareRevocationGeneration,
                  ownerPublicationEpoch == publicationEpoch
            else {
                return
            }
            latestErrorMessage = error.localizedDescription
        }
    }

    private func retainPendingExplicitCatchUp(
        _ pending: PendingExplicitCatchUp,
        affectedGoalIDs: Set<UUID>
    ) async {
        guard let currentPending = pendingExplicitCatchUp,
              currentPending.explicitIntent.id == pending.explicitIntent.id,
              currentPending.explicitIntent.revocationGeneration
                == pending.explicitIntent.revocationGeneration,
              pending.explicitIntent.revocationGeneration
                == explicitShareRevocationGeneration,
              revocationTombstoneStore.isPending(
                  namespaceKey: ownerNamespaceID.namespaceKey
              ) == false
        else {
            return
        }

        var durablyMarked = currentPending
        durablyMarked.isDurablyMarked = true
        pendingExplicitCatchUp = durablyMarked
        await autoRepublishCoordinator.retainDirtyForLater(
            reason: catchUpReason(affectedGoalIDs: affectedGoalIDs)
        )
    }

    private func durablyMarkPendingExplicitCatchUp(
        goalSnapshots: [FamilyShareGoalProjectionSnapshot],
        revocationGeneration: Int
    ) async -> Bool {
        guard let activeIntent = activeExplicitShareIntent,
              var pending = pendingExplicitCatchUp,
              pending.explicitIntent.id == activeIntent.id,
              pending.explicitIntent.revocationGeneration == revocationGeneration,
              revocationGeneration == explicitShareRevocationGeneration,
              revocationTombstoneStore.isPending(
                  namespaceKey: ownerNamespaceID.namespaceKey
              ) == false
        else {
            return false
        }

        await autoRepublishCoordinator.durablyMarkExplicitCatchUp(
            token: activeIntent.id,
            reason: catchUpReason(
                affectedGoalIDs: Set(goalSnapshots.map(\.id))
            )
        )

        guard let currentPending = pendingExplicitCatchUp,
              currentPending.explicitIntent.id == activeIntent.id,
              currentPending.explicitIntent.revocationGeneration
                == revocationGeneration,
              revocationGeneration == explicitShareRevocationGeneration,
              revocationTombstoneStore.isPending(
                  namespaceKey: ownerNamespaceID.namespaceKey
              ) == false
        else {
            return false
        }
        pending = currentPending
        pending.isDurablyMarked = true
        pendingExplicitCatchUp = pending
        return true
    }

    private func catchUpReason(
        affectedGoalIDs: Set<UUID>
    ) -> FamilyShareProjectionDirtyReason {
        affectedGoalIDs.isEmpty
            ? .manualRefresh
            : .goalMutation(goalIDs: affectedGoalIDs)
    }

    private var hasCurrentActiveExplicitIntentCatchUp: Bool {
        guard let activeIntent = activeExplicitShareIntent,
              let pending = pendingExplicitCatchUp else {
            return false
        }
        return pending.explicitIntent.id == activeIntent.id
            && pending.explicitIntent.revocationGeneration
                == explicitShareRevocationGeneration
            && activeIntent.revocationGeneration
                == explicitShareRevocationGeneration
    }

    private func completePendingExplicitCatchUpAfterAutomaticPublication(
        publicationEpoch: Int,
        allowsInactiveLifecycle: Bool
    ) async {
        guard let pending = pendingExplicitCatchUp,
              pending.explicitIntent.revocationGeneration
                == explicitShareRevocationGeneration,
              ownerPublicationEpoch == publicationEpoch,
              isOwnerPublicationAuthorized(
                  epoch: publicationEpoch,
                  allowsInactiveLifecycle: allowsInactiveLifecycle
              )
        else {
            return
        }
        await autoRepublishCoordinator.acknowledgeExplicitCatchUp(
            token: pending.explicitIntent.id
        )
        pendingExplicitCatchUp = nil
    }

    private func performShareAllGoals(
        _ goalSnapshots: [FamilyShareGoalProjectionSnapshot],
        revocationGeneration: Int
    ) async -> Bool {
        guard revocationGeneration == explicitShareRevocationGeneration else {
            return false
        }
        guard rollout.isEnabled() else {
            latestErrorMessage = FamilyShareCloudKitError.rolloutDisabled.localizedDescription
            return false
        }
        guard goalSnapshots.isEmpty == false else {
            latestErrorMessage = "Add at least one goal before sharing with family."
            return false
        }
        guard let cloudSync else {
            telemetry.track(.createStarted, payload: ["namespace": ownerNamespaceID.namespaceKey])
            telemetry.track(.shareRequested, payload: ["goal_count": "\(goalSnapshots.count)"])
            telemetry.track(
                .createFailed,
                payload: [
                    "namespace": ownerNamespaceID.namespaceKey,
                    "reason": "family sharing cloud sync unavailable"
                ]
            )
            latestErrorMessage = "Family sync is currently unavailable."
            return false
        }

        // Invalidate only after all synchronous, side-effect-free preflight
        // checks pass. Joined waiters share this one distinct FIFO intent.
        ownerLifecycleAuthorityGeneration &+= 1
        if revocationTombstoneStore.isPending(namespaceKey: ownerNamespaceID.namespaceKey) {
            await waitForOwnerPublicationsToSettle()
        }
        guard revocationGeneration == explicitShareRevocationGeneration else {
            return false
        }
        guard await retryPendingOwnerRevocationIfNeeded() else {
            latestErrorMessage = FamilySharePublicationInvalidatedByRevocationError().localizedDescription
            return false
        }
        guard revocationGeneration == explicitShareRevocationGeneration else {
            return false
        }

        do {
            telemetry.track(.createStarted, payload: ["namespace": ownerNamespaceID.namespaceKey])
            telemetry.track(.shareRequested, payload: ["goal_count": "\(goalSnapshots.count)"])

            explicitShareInProgress = true
            await teardownOwnerFreshnessPipelineIfNeeded(
                preservingAutomaticDirtyState: true
            )
            guard revocationGeneration == explicitShareRevocationGeneration,
                  explicitShareInProgress else {
                explicitShareInProgress = false
                return false
            }
            ownerPublicationEpoch &+= 1
            let explicitShareEpoch = ownerPublicationEpoch
            await configureAutoRepublishCoordinator()
            guard explicitShareInProgress,
                  revocationGeneration == explicitShareRevocationGeneration,
                  ownerPublicationEpoch == explicitShareEpoch else {
                explicitShareInProgress = false
                return false
            }
            guard await durablyMarkPendingExplicitCatchUp(
                goalSnapshots: goalSnapshots,
                revocationGeneration: revocationGeneration
            ) else {
                explicitShareInProgress = false
                return false
            }
            _ = try await autoRepublishCoordinator.publishExplicitIntent(
                reason: .participantChange
            ) { [weak self] in
                guard let self else {
                    throw CancellationError()
                }
                let outcome = try await self.publishProjectionImmediately(
                    for: goalSnapshots,
                    publicationEpoch: explicitShareEpoch,
                    allowsInactiveLifecycle: true
                )
                switch outcome {
                case .published(let receipt):
                    return receipt
                case .deduplicated:
                    return nil
                case .suppressed:
                    throw CancellationError()
                }
            }
            guard explicitShareInProgress,
                  revocationGeneration == explicitShareRevocationGeneration,
                  ownerPublicationEpoch == explicitShareEpoch else {
                explicitShareInProgress = false
                return false
            }

            let prepared = try await cloudSync.prepareShare(
                for: FamilyShareCloudSharingPreparationRequest(
                    namespaceID: ownerNamespaceID,
                    ownerDisplayName: normalizedOwnerDisplayName(),
                    shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals"
                )
            )
            guard explicitShareInProgress,
                  revocationGeneration == explicitShareRevocationGeneration,
                  ownerPublicationEpoch == explicitShareEpoch else {
                explicitShareInProgress = false
                _ = try? await compensateInvalidatedOwnerPublicationIfNeeded()
                return false
            }
            pendingCloudSharingRequest = FamilyShareCloudSharingRequest(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: normalizedOwnerDisplayName(),
                shareTitle: "\(normalizedOwnerDisplayName())'s Shared Goals",
                share: prepared.share,
                containerProvider: prepared.containerProvider
            )
            telemetry.track(.createSucceeded, payload: ["namespace": ownerNamespaceID.namespaceKey])
            if let seededState = try? registry.seededState(for: ownerNamespaceID) {
                await namespaceExecutionHub.bootstrap(with: seededState)
            }
            if var currentPending = pendingExplicitCatchUp,
               let activeIntent = activeExplicitShareIntent,
               currentPending.explicitIntent.id == activeIntent.id,
               activeIntent.revocationGeneration == revocationGeneration,
               revocationGeneration == explicitShareRevocationGeneration {
                // Mark completion before reactivating the observer. The
                // refresh pass performs the final authoritative fingerprint
                // check only after automatic observation is live again.
                currentPending.explicitDidComplete = true
                pendingExplicitCatchUp = currentPending
            }
            explicitShareInProgress = false
            await refreshAllState()
            return true
        } catch {
            explicitShareInProgress = false
            let errorMessage = error.localizedDescription
            telemetry.track(
                .createFailed,
                payload: [
                    "namespace": ownerNamespaceID.namespaceKey,
                    "reason": (error as NSError).localizedDescription
                ]
            )
            await refreshAllState()
            latestErrorMessage = errorMessage
            return false
        }
    }

    private func waitForOwnerPublicationsToSettle() async {
        guard ownerPublicationsInFlight > 0 else { return }
        await withCheckedContinuation { continuation in
            ownerPublicationWaiters.append(continuation)
        }
    }

    private func ownerPublicationDidFinish() {
        ownerPublicationsInFlight -= 1
        guard ownerPublicationsInFlight == 0 else { return }
        let waiters = ownerPublicationWaiters
        ownerPublicationWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
                containerProvider: prepared.containerProvider
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
        await refreshAllState()

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
        await refreshAllState()
        guard shouldRunOwnerRateRefreshDriver(for: ownerState) else {
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
        ownerLifecycleAuthorityGeneration &+= 1
        pendingExplicitCatchUp = nil
        revocationTombstoneStore.markPending(namespaceKey: ownerNamespaceID.namespaceKey)
        explicitShareRevocationGeneration &+= 1
        _ = await runSerializedOwnerRevocationOperation(
            maximumAuthorizedPublicationsInFlight: 0
        )
    }

    /// Retries a durable revocation left by a failed compensating delete.
    /// Called during bootstrap before remote owner state can reactivate publishing.
    @discardableResult
    func retryPendingOwnerRevocationIfNeeded() async -> Bool {
        let namespaceKey = ownerNamespaceID.namespaceKey
        if ownerRevocationOperation != nil {
            let outcome = await runSerializedOwnerRevocationOperation(
                maximumAuthorizedPublicationsInFlight: 0
            )
            return ownerRevocationDidComplete(outcome)
        }
        guard revocationTombstoneStore.isPending(namespaceKey: namespaceKey) else {
            resetOwnerRevocationRetryState()
            return true
        }
        let outcome = await runSerializedOwnerRevocationOperation(
            maximumAuthorizedPublicationsInFlight: 0
        )
        return ownerRevocationDidComplete(outcome)
    }

    private func runSerializedOwnerRevocationOperation(
        maximumAuthorizedPublicationsInFlight: Int
    ) async -> OwnerRevocationOperationOutcome {
        if let ownerRevocationOperation {
            return await ownerRevocationOperation.value
        }

        ownerRevocationOperationGeneration &+= 1
        let operationGeneration = ownerRevocationOperationGeneration
        let operation = Task { @MainActor [weak self] in
            guard let self else {
                return OwnerRevocationOperationOutcome.failed(
                    message: FamilyShareCloudKitError.accountUnavailable.localizedDescription
                )
            }
            let outcome = await self.performOwnerRevocationOperation(
                maximumAuthorizedPublicationsInFlight: maximumAuthorizedPublicationsInFlight
            )
            if self.ownerRevocationOperationGeneration == operationGeneration {
                self.ownerRevocationOperation = nil
            }
            return outcome
        }
        ownerRevocationOperation = operation
        return await operation.value
    }

    private func performOwnerRevocationOperation(
        maximumAuthorizedPublicationsInFlight: Int
    ) async -> OwnerRevocationOperationOutcome {
        ownerPublicationEpoch &+= 1
        explicitShareInProgress = false
        if hasCurrentActiveExplicitIntentCatchUp == false {
            pendingExplicitCatchUp = nil
        }
        await holdOwnerLifecycleInactiveWhileRevocationIsPending()

        do {
            guard cloudSync != nil else {
                throw FamilyShareCloudKitError.accountUnavailable
            }
            try await ownerSharingService.revoke(namespaceID: ownerNamespaceID)
            guard ownerPublicationsInFlight <= maximumAuthorizedPublicationsInFlight else {
                return .acknowledgedAwaitingPublicationSettlement
            }
            completeOwnerRevocationAfterAcknowledgement()
            latestErrorMessage = nil
            if ownerPublicationsInFlight == 0 {
                await refreshAllState()
            }
            return .completed
        } catch {
            await holdOwnerLifecycleInactiveWhileRevocationIsPending()
            schedulePendingOwnerRevocationRetry()
            latestErrorMessage = error.localizedDescription
            return .failed(message: error.localizedDescription)
        }
    }

    private func ownerRevocationDidComplete(
        _ outcome: OwnerRevocationOperationOutcome
    ) -> Bool {
        if case .completed = outcome {
            return true
        }
        return false
    }

    private func schedulePendingOwnerRevocationRetry() {
        guard revocationTombstoneStore.isPending(namespaceKey: ownerNamespaceID.namespaceKey) else {
            resetOwnerRevocationRetryState()
            return
        }

        revocationRetryFailureCount += 1
        let delay = revocationRetryPolicy.backoffDelay(
            forFailureCount: revocationRetryFailureCount
        )
        revocationRetryHandle?.cancel()
        revocationRetryHandle = revocationRetryScheduler.scheduleDebounce(delay: delay) { [weak self] in
            await self?.performScheduledOwnerRevocationRetry()
        }
    }

    private func performScheduledOwnerRevocationRetry() async {
        revocationRetryHandle = nil
        guard await retryPendingOwnerRevocationIfNeeded() else {
            return
        }
        await refreshAllState()
    }

    private func completeOwnerRevocationAfterAcknowledgement() {
        resetOwnerRevocationRetryState()
        revocationTombstoneStore.clear(namespaceKey: ownerNamespaceID.namespaceKey)
    }

    private func resetOwnerRevocationRetryState() {
        revocationRetryHandle?.cancel()
        revocationRetryHandle = nil
        revocationRetryFailureCount = 0
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
        if scenePhase == .active,
           revocationTombstoneStore.isPending(namespaceKey: ownerNamespaceID.namespaceKey) {
            Task { [weak self] in
                guard let self else { return }
                guard await self.retryPendingOwnerRevocationIfNeeded() else {
                    return
                }
                await self.refreshAllState()
            }
            return
        }

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

    private func publishProjectionImmediately(
        for goals: [Goal],
        publicationEpoch: Int,
        allowsInactiveLifecycle: Bool
    ) async throws -> FamilyShareProjectionAutoPublishOutcome {
        guard isOwnerPublicationAuthorized(
            epoch: publicationEpoch,
            allowsInactiveLifecycle: allowsInactiveLifecycle
        ) else {
            return .suppressed
        }

        // The automatic path receives authoritative live goals. Freeze every
        // projected value synchronously before this function's first await.
        let goalSnapshots = try makeGoalProjectionSnapshots(from: goals)
        return try await publishProjectionImmediately(
            for: goalSnapshots,
            publicationEpoch: publicationEpoch,
            allowsInactiveLifecycle: allowsInactiveLifecycle
        )
    }

    private func publishProjectionImmediately(
        for goalSnapshots: [FamilyShareGoalProjectionSnapshot],
        publicationEpoch: Int,
        allowsInactiveLifecycle: Bool
    ) async throws -> FamilyShareProjectionAutoPublishOutcome {
        guard isOwnerPublicationAuthorized(
            epoch: publicationEpoch,
            allowsInactiveLifecycle: allowsInactiveLifecycle
        ) else {
            return .suppressed
        }
        let buildResult = try await makeProjectionPayload(for: goalSnapshots)
        guard isOwnerPublicationAuthorized(
            epoch: publicationEpoch,
            allowsInactiveLifecycle: allowsInactiveLifecycle
        ) else {
            return .suppressed
        }
        let payload = buildResult.payload
        if let cachedPayload = try registry.seededState(for: ownerNamespaceID)?.projectionPayload,
           let incomingHash = payload.contentHash,
           let cachedHash = cachedPayload.contentHash,
           incomingHash == cachedHash {
            telemetry.track(.contentHashDedup, payload: ["namespace": ownerNamespaceID.namespaceKey])
            await recordPublishedProjection(
                payload: payload,
                rateSnapshot: buildResult.rateSnapshot,
                goalInputs: buildResult.goalInputs,
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
            return .deduplicated
        }
        ownerPublicationsInFlight += 1
        defer { ownerPublicationDidFinish() }
        let result: FamilySharePublicationResult
        do {
            result = try await publishCoordinator.publish(payload)
        } catch {
            if isOwnerPublicationAuthorized(
                epoch: publicationEpoch,
                allowsInactiveLifecycle: allowsInactiveLifecycle
            ) == false,
               try await compensateInvalidatedOwnerPublicationIfNeeded() {
                return .suppressed
            }
            throw error
        }
        guard isOwnerPublicationAuthorized(
            epoch: publicationEpoch,
            allowsInactiveLifecycle: allowsInactiveLifecycle
        ) else {
            _ = try await compensateInvalidatedOwnerPublicationIfNeeded()
            return .suppressed
        }
        await recordPublishedProjection(
            payload: payload,
            rateSnapshot: buildResult.rateSnapshot,
            goalInputs: buildResult.goalInputs,
            result: result
        )
        return .published(
            FamilySharePublishReceipt(
                serverTimestamp: result.projectionServerTimestamp ?? result.publishedAt,
                recordCount: result.goalCount + result.ownerSectionCount + 1
            )
        )
    }

    /// A revoke can finish while a previously-started remote publish is suspended.
    /// If that late publish subsequently commits, issue an idempotent second revoke
    /// so both the CloudKit projection and the local lifecycle end revoked.
    private func compensateInvalidatedOwnerPublicationIfNeeded() async throws -> Bool {
        let hasDefinitiveRevocation =
            revocationTombstoneStore.isPending(
                namespaceKey: ownerNamespaceID.namespaceKey
            )
            || ownerState.lifecycleState == .revoked
        guard explicitShareInProgress == false,
              hasDefinitiveRevocation else {
            return false
        }
        ownerLifecycleAuthorityGeneration &+= 1
        revocationTombstoneStore.markPending(namespaceKey: ownerNamespaceID.namespaceKey)
        var outcome = await runSerializedOwnerRevocationOperation(
            maximumAuthorizedPublicationsInFlight: 1
        )
        if case .acknowledgedAwaitingPublicationSettlement = outcome,
           ownerPublicationsInFlight <= 1 {
            outcome = await runSerializedOwnerRevocationOperation(
                maximumAuthorizedPublicationsInFlight: 1
            )
        }
        switch outcome {
        case .completed:
            return true
        case .acknowledgedAwaitingPublicationSettlement:
            return false
        case .failed(let message):
            throw NSError(
                domain: "FamilyShareOwnerRevocation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func recordPublishedProjection(
        payload: FamilyShareProjectionPayload,
        rateSnapshot: RateSnapshot,
        goalInputs: [GoalProgressInput],
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

        let publishedAmounts: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: updatedPayload.goals.compactMap { projectedGoal in
            guard let goalID = UUID(uuidString: projectedGoal.goalID) else { return nil }
            return (goalID, projectedGoal.currentAmount)
        })
        await rateDriftEvaluator.updateTrackedGoals(
            goalInputs,
            lastPublished: publishedAmounts,
            rateSnapshot: rateSnapshot
        )
    }

    private func makeGoalProgressInputs(from goals: [Goal]) -> [GoalProgressInput] {
        goals.compactMap { goal in
            let allocations = goal.allocations ?? []
            guard allocations.allSatisfy({ $0.asset != nil }) else {
                return nil
            }
            return GoalProgressInput(
                goalID: goal.id,
                currency: goal.currency,
                targetAmount: Decimal(goal.targetAmount),
                allocations: allocations.compactMap { alloc in
                    guard let asset = alloc.asset else { return nil }
                    return AllocationInput(
                        assetCurrency: asset.currency,
                        allocatedAmount: Decimal(alloc.amountValue)
                    )
                }
            )
        }
    }

    private func fetchRateSnapshot(for inputs: [GoalProgressInput]) async -> RateSnapshot {
        let requirements = FamilyShareRateRequirements(goalInputs: inputs)
        var rates: [String: Decimal] = [:]

        for pair in requirements.allPairs.sorted() {
            let currencies = pair.split(separator: "→", maxSplits: 1).map(String.init)
            guard currencies.count == 2 else { continue }
            if let rate = try? await exchangeRateService.fetchRate(
                from: currencies[0],
                to: currencies[1]
            ),
               rate.isFinite,
               rate > 0 {
                rates[pair] = Decimal(rate)
            }
        }

        let timestamp = exchangeRateService.rateSnapshotTimestamp(
            for: requirements.allPairs
        ) ?? Date()
        return RateSnapshot(rates: rates, timestamp: timestamp)
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

    private func isOwnerPublicationAuthorized(
        epoch: Int,
        allowsInactiveLifecycle: Bool
    ) -> Bool {
        guard epoch == ownerPublicationEpoch else {
            return false
        }
        guard revocationTombstoneStore.isPending(namespaceKey: ownerNamespaceID.namespaceKey) == false else {
            return false
        }
        return allowsInactiveLifecycle || shouldRunOwnerRateRefreshDriver(for: ownerState)
    }

    private func holdOwnerLifecycleInactiveWhileRevocationIsPending() async {
        await teardownOwnerFreshnessPipelineIfNeeded(
            preservingAutomaticDirtyState: false,
            forceCoordinatorTeardown: true,
            cause: "pendingRevocation"
        )
        let pendingOwnerState: FamilyShareOwnerViewState
        if let storedOwnerState = try? await stateProvider.ownerState(for: ownerNamespaceID),
           shouldRunOwnerRateRefreshDriver(for: storedOwnerState) == false {
            pendingOwnerState = storedOwnerState
        } else {
            pendingOwnerState = FamilyShareOwnerViewState(
                namespaceID: ownerNamespaceID,
                lifecycleState: .revoked,
                participantCount: 0,
                pendingParticipantCount: 0,
                activeParticipantCount: 0,
                revokedParticipantCount: 1,
                failedParticipantCount: 0,
                summaryCopy: "Finishing access revocation.",
                primaryActionCopy: "Share with Family"
            )
        }
        ownerState = pendingOwnerState
        if let seededState = try? registry.seededState(for: ownerNamespaceID) {
            try? registry.seed(
                FamilyShareSeededNamespaceState(
                    ownerDisplayName: seededState.ownerDisplayName,
                    ownerState: pendingOwnerState,
                    inviteeState: seededState.inviteeState,
                    projectionPayload: seededState.projectionPayload?.updatingLifecycleState(
                        FamilyShareOwnerLifecycleState.revoked.rawValue
                    )
                )
            )
        }
        ownerParticipants = []
    }

    private func lastKnownOwnerProjectionServerTimestamp() -> Date? {
        guard let payload = try? registry.seededState(for: ownerNamespaceID)?.projectionPayload else {
            return nil
        }
        return payload.projectionServerTimestamp ?? payload.publishedAt
    }

    private func teardownOwnerFreshnessPipelineIfNeeded(
        preservingAutomaticDirtyState: Bool? = nil,
        forceCoordinatorTeardown: Bool = false,
        cause: String = "lifecycleGuard"
    ) async {
        guard ownerFreshnessPipelineActive
                || ownerAutoRepublishConfigured
                || forceCoordinatorTeardown else {
            return
        }

        let shouldPreserveAutomaticDirtyState =
            preservingAutomaticDirtyState
            ?? (
                revocationTombstoneStore.isPending(
                    namespaceKey: ownerNamespaceID.namespaceKey
                ) == false
            )
        ownerPublicationEpoch &+= 1
        // Fence the coordinator before yielding to any other actor. Otherwise
        // a late CloudKit acknowledgement can complete in this suspension
        // window and clear the durable dirty marker before a preserving
        // lifecycle teardown records its generation.
        await autoRepublishCoordinator.teardown(
            preservingDirtyState: shouldPreserveAutomaticDirtyState,
            cause: cause
        )
        mutationObserver.teardown()
        await rateDriftEvaluator.teardown()
        rateRefreshDriver?.teardown()
        ownerFreshnessPipelineActive = false
        ownerAutoRepublishConfigured = false
    }

    private func teardownFreshnessPipelineIfNeeded() async {
        await teardownOwnerFreshnessPipelineIfNeeded(
            preservingAutomaticDirtyState: false,
            forceCoordinatorTeardown: true,
            cause: "fullPipelineTeardown"
        )
        guard freshnessPipelineActive else { return }
        inviteeRefreshScheduler.teardown()
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

    private func makeGoalProjectionSnapshots(
        from goals: [Goal]
    ) throws -> [FamilyShareGoalProjectionSnapshot] {
        var goalSnapshots = try goals.map { goal in
            var allocations = try (goal.allocations ?? []).map { allocation in
                guard let asset = allocation.asset else {
                    throw FamilyShareProjectionBuildError.orphanedAllocation(goal.id)
                }
                return AllocationInput(
                    assetCurrency: asset.currency,
                    allocatedAmount: Decimal(allocation.amountValue)
                )
            }
            allocations.sort {
                if $0.assetCurrency != $1.assetCurrency {
                    return $0.assetCurrency < $1.assetCurrency
                }
                return $0.allocatedAmount < $1.allocatedAmount
            }

            let targetAmount = Decimal(goal.targetAmount)
            return FamilyShareGoalProjectionSnapshot(
                id: goal.id,
                name: goal.name,
                emoji: goal.emoji,
                currency: goal.currency,
                targetAmount: targetAmount,
                targetAmountValue: goal.targetAmount,
                deadline: goal.deadline,
                lastModifiedAt: goal.lastModifiedDate,
                progressInput: GoalProgressInput(
                    goalID: goal.id,
                    currency: goal.currency,
                    targetAmount: targetAmount,
                    allocations: allocations
                )
            )
        }
        goalSnapshots.sort {
            if $0.deadline != $1.deadline {
                return $0.deadline < $1.deadline
            }
            let caseInsensitiveNameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if caseInsensitiveNameOrder != .orderedSame {
                return caseInsensitiveNameOrder == .orderedAscending
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return goalSnapshots
    }

    private func makeProjectionPayload(
        for goalSnapshots: [FamilyShareGoalProjectionSnapshot]
    ) async throws -> FamilyShareProjectionBuildResult {
        let ownerName = normalizedOwnerDisplayName()
        let existingVersion = try registry.seededState(for: ownerNamespaceID)?.projectionPayload?.projectionVersion ?? 0
        let projectionVersion = max(existingVersion + 1, 1)
        let participantCount = ownerState.participantCount
        let pendingCount = ownerState.pendingParticipantCount
        let revokedCount = ownerState.revokedParticipantCount
        let participantSnapshots = ownerParticipants
        let publishedAt = Date()

        let calculator = GoalProgressCalculator()
        let inputs = goalSnapshots.map(\.progressInput)

        let rateSnapshot = await fetchRateSnapshot(for: inputs)
        let rateTimestamp = rateSnapshot.timestamp
        let progressResults = calculator.calculateProgress(for: inputs, rates: rateSnapshot)
        let missingRatePairs = Set(
            progressResults.values.flatMap(\.missingRatePairs)
        )
        guard missingRatePairs.isEmpty else {
            throw FamilyShareProjectionBuildError.incompleteExchangeRates(
                missingRatePairs.sorted()
            )
        }

        let goalPayloads = try goalSnapshots.enumerated().map { index, goalSnapshot in
            guard let result = progressResults[goalSnapshot.id] else {
                throw FamilyShareProjectionBuildError.missingGoalProgress(goalSnapshot.id)
            }

            return FamilyShareProjectedGoalPayload(
                id: "\(ownerNamespaceID.namespaceKey)|\(goalSnapshot.id.uuidString)",
                namespaceID: ownerNamespaceID,
                ownerID: ownerNamespaceID.ownerID,
                ownerDisplayName: ownerName,
                goalID: goalSnapshot.id.uuidString,
                goalName: goalSnapshot.name,
                goalEmoji: goalSnapshot.emoji,
                currency: goalSnapshot.currency,
                targetAmount: goalSnapshot.targetAmount,
                currentAmount: result.currentAmount,
                progressRatio: result.progressRatio,
                deadline: goalSnapshot.deadline,
                goalStatusRawValue: projectedGoalStatus(
                    currentAmount: result.currentAmount,
                    targetAmount: goalSnapshot.targetAmount,
                    progressRatio: result.progressRatio,
                    deadline: goalSnapshot.deadline,
                    at: publishedAt
                ),
                forecastStateRawValue: nil,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lastUpdatedAt: goalSnapshot.lastModifiedAt,
                summaryCopy: FamilyShareOwnerIdentityResolver.canonicalGoalContributionSummary(
                    currency: goalSnapshot.currency,
                    currentAmount: NSDecimalNumber(decimal: result.currentAmount).doubleValue,
                    targetAmount: goalSnapshot.targetAmountValue
                ),
                sortIndex: index
            )
        }

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
        let freshnessStateRawValue = FamilyShareLifecycleState.active.rawValue
        let lifecycleStateRawValue = FamilyShareOwnerLifecycleState.sharedActive.rawValue
        let summaryTitle = FamilyShareOwnerIdentityResolver.inviteeEntryTitle
        let summaryCopy = FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
            lifecycleState: .active,
            fallback: "All current goals are shared in read-only mode."
        )

        // Compute contentHash over all semantic invitee-visible state.
        let contentHash = FamilyShareContentHasher().hash(
            FamilyShareContentHashInput(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: ownerName,
                freshnessStateRawValue: freshnessStateRawValue,
                lifecycleStateRawValue: lifecycleStateRawValue,
                summaryTitle: summaryTitle,
                summaryCopy: summaryCopy,
                participantCount: participantCount,
                pendingParticipantCount: pendingCount,
                revokedParticipantCount: revokedCount,
                goals: goalPayloads,
                ownerSections: ownerSections,
                participants: participantSnapshots,
                rateSnapshotTimestamp: rateTimestamp
            )
        )

        let payload = FamilyShareProjectionPayload(
            namespaceID: ownerNamespaceID,
            ownerDisplayName: ownerName,
            schemaVersion: FamilyShareCacheSchema.currentVersion,
            projectionVersion: projectionVersion,
            activeProjectionVersion: projectionVersion,
            freshnessStateRawValue: freshnessStateRawValue,
            lifecycleStateRawValue: lifecycleStateRawValue,
            publishedAt: publishedAt,
            lastReconciledAt: publishedAt,
            lastRefreshAttemptAt: publishedAt,
            lastRefreshErrorCode: nil,
            lastRefreshErrorMessage: nil,
            summaryTitle: summaryTitle,
            summaryCopy: summaryCopy,
            participantCount: participantCount,
            pendingParticipantCount: pendingCount,
            revokedParticipantCount: revokedCount,
            goals: goalPayloads,
            ownerSections: ownerSections,
            rateSnapshotTimestamp: rateTimestamp,
            projectionServerTimestamp: nil, // Set from CKRecord.modificationDate after publish
            contentHash: contentHash
        )
        return FamilyShareProjectionBuildResult(
            payload: payload,
            rateSnapshot: rateSnapshot,
            goalInputs: inputs
        )
    }

    private func projectedGoalStatus(
        currentAmount: Decimal,
        targetAmount: Decimal,
        progressRatio: Double,
        deadline: Date,
        at date: Date
    ) -> String {
        if currentAmount >= targetAmount {
            return "Achieved"
        }
        if deadline < date {
            return "Expired"
        }

        let daysRemaining = max(
            Calendar.current.dateComponents([.day], from: date, to: deadline).day ?? 0,
            0
        )
        if daysRemaining < 7 {
            return "Urgent"
        }
        if progressRatio > 0.7 {
            return "On Track"
        }
        if progressRatio > 0.3 {
            return "In Progress"
        }
        return "Just Started"
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

#if canImport(CloudKit)
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

#if canImport(UIKit)
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
