//
//  FamilyShareServices.swift
//  CryptoSavingsTracker
//

import Combine
import Foundation
import UIKit
import SwiftData
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
    func sharedOwnerSections() async throws -> [FamilyShareOwnerSection]
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
    func acceptPendingInvitation(from connectionOptions: UIScene.ConnectionOptions)
}

struct FamilySharePublicationResult: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let projectionVersion: Int
    let activeProjectionVersion: Int
    let goalCount: Int
    let ownerSectionCount: Int
    let publishedAt: Date
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

actor FamilyShareNamespaceActor: FamilyShareNamespaceManaging {
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

    func sharedOwnerSections() async throws -> [FamilyShareOwnerSection] {
        try registry
            .seededStates()
            .map { seededState in
                let namespaceID = seededState.ownerState.namespaceID
                let inviteeState = seededState.inviteeState
                let surfaceState = FamilyShareSurfaceState(rawValue: inviteeState?.lifecycleState.rawValue ?? "") ?? .active
                let goals = seededState.projectionPayload?.goals
                    .sorted(by: { $0.sortIndex < $1.sortIndex })
                    .map { payload in
                        FamilySharedGoalSummary(
                            id: payload.id,
                            namespaceID: payload.namespaceID,
                            ownerName: payload.ownerDisplayName,
                            goalName: payload.goalName,
                            emoji: payload.goalEmoji,
                            currency: payload.currency,
                            targetAmount: NSDecimalNumber(decimal: payload.targetAmount).doubleValue,
                            currentAmount: NSDecimalNumber(decimal: payload.currentAmount).doubleValue,
                            deadline: payload.deadline,
                            lastUpdatedAt: payload.lastUpdatedAt,
                            state: FamilyShareSurfaceState(rawValue: payload.freshnessStateRawValue) ?? surfaceState,
                            contributionSummary: payload.summaryCopy,
                            currentMonthSummary: payload.goalStatusRawValue
                        )
                    } ?? []

                return FamilyShareOwnerSection(
                    ownerID: namespaceID.ownerID,
                    shareID: namespaceID.shareID,
                    ownerName: seededState.ownerDisplayName,
                    goals: goals,
                    isCurrentOwner: false,
                    state: surfaceState,
                    summaryCopy: inviteeState?.messageCopy ?? seededState.ownerState.summaryCopy,
                    primaryActionTitle: inviteeState?.primaryActionCopy
                )
            }
            .sorted { lhs, rhs in
                let ownerSort = lhs.ownerName.localizedCaseInsensitiveCompare(rhs.ownerName)
                if ownerSort != .orderedSame {
                    return ownerSort == .orderedAscending
                }
                if lhs.ownerID != rhs.ownerID {
                    return lhs.ownerID < rhs.ownerID
                }
                return lhs.shareID < rhs.shareID
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

        return FamilySharePublicationResult(
            namespaceID: payload.namespaceID,
            projectionVersion: payload.projectionVersion,
            activeProjectionVersion: payload.activeProjectionVersion,
            goalCount: payload.goals.count,
            ownerSectionCount: payload.ownerSections.count,
            publishedAt: payload.publishedAt ?? Date()
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
    }
}

@MainActor
final class FamilyShareCacheMigrationCoordinator: FamilyShareCacheMigrating {
    private let registry: FamilyShareNamespaceRegistry

    init(registry: FamilyShareNamespaceRegistry? = nil) {
        self.registry = registry ?? FamilyShareNamespaceRegistry()
    }

    func ensureCompatible(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareCacheMigrationResult {
        guard let current = try registry.seededState(for: namespaceID) else {
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
            return FamilyShareCacheMigrationResult(
                namespaceID: namespaceID,
                previousSchemaVersion: nil,
                currentSchemaVersion: FamilyShareCacheSchema.currentVersion,
                didMigrate: false,
                requiresRebuild: true,
                quarantined: false
            )
        }

        let previousVersion = projectionPayload.schemaVersion
        let currentVersion = FamilyShareCacheSchema.currentVersion

        if previousVersion > currentVersion {
            throw FamilyShareCacheMigrationError.unsupportedFutureSchemaVersion(
                current: currentVersion,
                required: previousVersion
            )
        }

        if previousVersion < FamilyShareCacheSchema.supportedVersions.lowerBound {
            throw FamilyShareCacheMigrationError.unsupportedHistoricalSchemaVersion(
                current: FamilyShareCacheSchema.supportedVersions.lowerBound,
                required: previousVersion
            )
        }

        if previousVersion < currentVersion {
            try registry.seed(
                FamilyShareSeededNamespaceState(
                    ownerDisplayName: current.ownerDisplayName,
                    ownerState: current.ownerState,
                    inviteeState: current.inviteeState,
                    projectionPayload: projectionPayload.updatingSchemaVersion(currentVersion)
                )
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
        let generated = UIDevice.current.name.isEmpty ? "My Goals" : UIDevice.current.name
        userDefaults.set(generated, forKey: Keys.ownerName)
        return generated
    }

    func ownerNamespaceID() -> FamilyShareNamespaceID {
        FamilyShareNamespaceID(ownerID: ownerID(), shareID: shareID())
    }

    func namespaceID(for snapshot: FamilyShareInvitationMetadataSnapshot) -> FamilyShareNamespaceID {
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
    @Published private(set) var sharedSections: [FamilyShareOwnerSection] = []
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
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker()
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
        FamilyShareSceneBridgeHub.shared.acceptanceSink = self
        Task { [weak self] in
            await self?.refreshAllState()
        }
    }

    func refreshAllState() async {
        guard rollout.isEnabled() else {
            inviteeStates = []
            sharedSections = []
            ownerState = defaultOwnerState()
            ownerParticipants = []
            return
        }
        do {
            let namespaceIDs = registry.allNamespaceIDs()
            for namespaceID in namespaceIDs {
                do {
                    _ = try await cacheMigrationCoordinator.ensureCompatible(namespaceID: namespaceID)
                } catch {
                    telemetry.track(
                        .migrationFailed,
                        payload: ["namespace": namespaceID.namespaceKey, "reason": error.localizedDescription]
                    )
                    throw error
                }
            }

            let storedOwnerState = try await stateProvider.ownerState(for: ownerNamespaceID) ?? defaultOwnerState()
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

            ownerState = resolvedOwnerState
            ownerParticipants = resolvedOwnerParticipants
            inviteeStates = try await inviteeStateProvider.inviteeStates()
                .filter { $0.namespaceID != ownerNamespaceID }
            sharedSections = try await inviteeStateProvider.sharedOwnerSections()
                .filter { $0.ownerID != ownerNamespaceID.ownerID || $0.shareID != ownerNamespaceID.shareID }
            latestErrorMessage = ownerShareErrorMessage
        } catch {
            latestErrorMessage = error.localizedDescription
            inviteeStates = []
            sharedSections = []
            ownerState = defaultOwnerState()
            ownerParticipants = []
        }
    }

    func makeFamilyAccessModel(currentGoals: [Goal]) -> FamilyAccessModel {
        let currentOwnerState = ownerState
        let ownerName = identityStore.ownerDisplayName()
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

        do {
            telemetry.track(.shareRequested, payload: ["goal_count": "\(goals.count)"])
            let payload = try makeProjectionPayload(for: goals)
            _ = try await publishCoordinator.publish(payload)
            guard let cloudSync else {
                latestErrorMessage = "Family sharing cloud sync is unavailable."
                return
            }
            let prepared = try await cloudSync.prepareShare(
                for: FamilyShareCloudSharingPreparationRequest(
                    namespaceID: ownerNamespaceID,
                    ownerDisplayName: identityStore.ownerDisplayName(),
                    shareTitle: "\(identityStore.ownerDisplayName())'s Shared Goals"
                )
            )
            pendingCloudSharingRequest = FamilyShareCloudSharingRequest(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: identityStore.ownerDisplayName(),
                shareTitle: "\(identityStore.ownerDisplayName())'s Shared Goals",
                share: prepared.share,
                container: prepared.container
            )
            await refreshAllState()
        } catch {
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
            latestErrorMessage = "Family sharing cloud sync is unavailable."
            return
        }

        do {
            let prepared = try await cloudSync.prepareShare(
                for: FamilyShareCloudSharingPreparationRequest(
                    namespaceID: ownerNamespaceID,
                    ownerDisplayName: identityStore.ownerDisplayName(),
                    shareTitle: "\(identityStore.ownerDisplayName())'s Shared Goals"
                )
            )
            pendingCloudSharingRequest = FamilyShareCloudSharingRequest(
                namespaceID: ownerNamespaceID,
                ownerDisplayName: identityStore.ownerDisplayName(),
                shareTitle: "\(identityStore.ownerDisplayName())'s Shared Goals",
                share: prepared.share,
                container: prepared.container
            )
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func revokeOwnerShare() async {
        do {
            try await ownerSharingService.revoke(namespaceID: ownerNamespaceID)
            await refreshAllState()
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func handlePrimaryAction(for section: FamilyShareOwnerSection) async {
        let namespaceID = FamilyShareNamespaceID(ownerID: section.ownerID, shareID: section.shareID)
        do {
            switch section.state {
            case .active, .stale, .temporarilyUnavailable, .emptySharedDataset:
                try await refreshNamespace(namespaceID)
            case .invitePendingAcceptance:
                latestErrorMessage = "Accept the CloudKit invitation from Mail or Messages to finish setup."
            case .revoked:
                latestErrorMessage = "The owner needs to share this goal set again."
            case .removedOrNoLongerShared:
                registry.purge(namespaceID: namespaceID)
            }
            await refreshAllState()
        } catch {
            latestErrorMessage = error.localizedDescription
        }
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

    func seedUITestScenario(_ scenario: UITestFlags.FamilyShareScenario) async {
        guard let mappedScenario = FamilyShareTestScenario(rawValue: scenario.rawValue) else { return }
        let namespaceID: FamilyShareNamespaceID
        switch mappedScenario {
        case .ownerNotShared, .ownerSharedActive:
            namespaceID = ownerNamespaceID
        case .inviteeActive, .inviteeEmpty, .inviteeStale, .inviteeRevoked, .inviteeRemoved, .inviteeUnavailable:
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

    func resetAllNamespaces() async {
        registry.purgeAllNamespaces()
        inviteeStates = []
        sharedSections = []
        pendingCloudSharingRequest = nil
        latestErrorMessage = nil
        lastSeededScenario = nil
        ownerState = defaultOwnerState()
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

    func acceptPendingInvitation(from connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        let snapshot = FamilyShareInvitationMetadataSnapshot(metadata: metadata)
        latestConnectionOptionsSnapshot = snapshot
        acceptInvitation(metadata)
    }

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
                telemetry.track(.accepted, payload: ["namespace": seededState.ownerState.namespaceID.namespaceKey])
            } else {
                let namespaceID = identityStore.namespaceID(for: snapshot)
                if try registry.seededState(for: namespaceID) == nil {
                    try registry.seed(
                        FamilyShareSeededNamespaceState(
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
                                titleCopy: "Shared Goals",
                                messageCopy: "The invitation was accepted. Pull the latest shared goals to populate this section.",
                                primaryActionCopy: "Retry",
                                isReadOnly: true
                            ),
                            projectionPayload: nil
                        )
                    )
                }
            }
            await refreshAllState()
        } catch {
            telemetry.track(.acceptFailed, payload: ["reason": error.localizedDescription])
            latestErrorMessage = error.localizedDescription
        }
    }

    private func refreshNamespace(_ namespaceID: FamilyShareNamespaceID) async throws {
        telemetry.track(.refreshRequested, payload: ["namespace": namespaceID.namespaceKey])
        if let cloudSync {
            do {
                let seededState = try await cloudSync.refreshProjection(namespaceID: namespaceID)
                try registry.seed(seededState)
                telemetry.track(.refreshSucceeded, payload: ["namespace": namespaceID.namespaceKey])
                return
            } catch {
                telemetry.track(.refreshFailed, payload: ["namespace": namespaceID.namespaceKey, "reason": error.localizedDescription])
            }
        }
        guard let current = try await stateProvider.seededState(for: namespaceID) else { return }
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
            titleCopy: current.inviteeState?.titleCopy ?? "Shared Goals",
            messageCopy: refreshedState == .active ? "Latest shared goal set is available." : (current.inviteeState?.messageCopy ?? "Shared goals are not ready yet."),
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
                ownerSections: payload.ownerSections
            )
        }

        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: current.ownerDisplayName,
                ownerState: current.ownerState,
                inviteeState: inviteeState,
                projectionPayload: updatedPayload
            )
        )
    }

    private func makeProjectionPayload(for goals: [Goal]) throws -> FamilyShareProjectionPayload {
        let ownerName = identityStore.ownerDisplayName()
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

        let goalPayloads = sortedGoals.enumerated().map { index, goal in
            FamilyShareProjectedGoalPayload(
                id: "\(ownerNamespaceID.namespaceKey)|\(goal.id.uuidString)",
                namespaceID: ownerNamespaceID,
                ownerID: ownerNamespaceID.ownerID,
                ownerDisplayName: ownerName,
                goalID: goal.id.uuidString,
                goalName: goal.name,
                goalEmoji: goal.emoji,
                currency: goal.currency,
                targetAmount: Decimal(goal.targetAmount),
                currentAmount: Decimal(goal.manualTotal),
                progressRatio: goal.targetAmount > 0 ? min(max(goal.manualTotal / goal.targetAmount, 0), 1) : 0,
                deadline: goal.deadline,
                goalStatusRawValue: goal.status,
                forecastStateRawValue: nil,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lastUpdatedAt: goal.lastModifiedDate,
                summaryCopy: goal.status,
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
                inlineChipCopy: "Shared by \(ownerName)"
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
            summaryTitle: "Shared Goals",
            summaryCopy: "All current goals are shared in read-only mode.",
            participantCount: participantCount,
            pendingParticipantCount: pendingCount,
            revokedParticipantCount: ownerState.revokedParticipantCount,
            goals: goalPayloads,
            ownerSections: ownerSections
        )
    }

    private func defaultOwnerState() -> FamilyShareOwnerViewState {
        FamilyShareOwnerViewState(
            namespaceID: ownerNamespaceID,
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
        self.init(
            ownerDisplayName: metadata.ownerIdentity.nameComponents?.formatted() ?? "Shared Family",
            shareURLString: metadata.share.url?.absoluteString,
            participantStatusRawValue: String(describing: metadata.participantStatus),
            participantRoleRawValue: String(describing: metadata.participantRole),
            participantPermissionRawValue: String(describing: metadata.participantPermission),
            rootRecordName: metadata.rootRecordID.recordName,
            rootZoneName: metadata.rootRecordID.zoneID.zoneName,
            rootZoneOwnerName: metadata.rootRecordID.zoneID.ownerName,
            hierarchicalRootRecordName: metadata.hierarchicalRootRecordID?.recordName,
            hierarchicalRootZoneName: metadata.hierarchicalRootRecordID?.zoneID.zoneName,
            hierarchicalRootZoneOwnerName: metadata.hierarchicalRootRecordID?.zoneID.ownerName
        )
    }
}
#endif

private extension FamilyShareProjectionPayload {
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
            ownerSections: ownerSections
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
            ownerSections: ownerSections
        )
    }
}
