//
//  FamilyShareCacheStore.swift
//  CryptoSavingsTracker
//

import Foundation
import SwiftData

struct FamilyShareCacheStoreDescriptor: Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let storeName: String
    let storeURL: URL?
    let schemaVersion: Int
    let isStoredInMemoryOnly: Bool

    init(namespaceID: FamilyShareNamespaceID, storeURL: URL?, schemaVersion: Int, isStoredInMemoryOnly: Bool) {
        self.namespaceID = namespaceID
        self.storeName = namespaceID.storeName
        self.storeURL = storeURL
        self.schemaVersion = schemaVersion
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }
}

final class FamilyShareNamespaceStore {
    let descriptor: FamilyShareCacheStoreDescriptor
    let container: ModelContainer
    let mainContext: ModelContext
    private(set) var lastAccessedAt: Date = Date()

    init(descriptor: FamilyShareCacheStoreDescriptor, container: ModelContainer) {
        self.descriptor = descriptor
        self.container = container
        self.mainContext = ModelContext(container)
    }

    func touch() {
        lastAccessedAt = Date()
    }
}

struct FamilyShareCacheStoreEnvironment: Sendable {
    let isTestRun: Bool
    let applicationSupportURL: URL?

    static func current(fileManager: FileManager = .default, processInfo: ProcessInfo = .processInfo) -> Self {
        let isXCTestRun = processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITestRun = processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") })
        let isPreviewRun = processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let isTestRun = isXCTestRun || isUITestRun || isPreviewRun
        let supportURL = isTestRun ? nil : fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return Self(isTestRun: isTestRun, applicationSupportURL: supportURL)
    }

    static var preview: Self {
        Self(isTestRun: true, applicationSupportURL: nil)
    }
}

@MainActor
final class FamilyShareNamespaceStoreFactory {
    private let environment: FamilyShareCacheStoreEnvironment
    private let fileManager: FileManager

    init(environment: FamilyShareCacheStoreEnvironment? = nil, fileManager: FileManager = .default) {
        self.environment = environment ?? .current()
        self.fileManager = fileManager
    }

    func descriptor(for namespaceID: FamilyShareNamespaceID, schemaVersion: Int? = nil) -> FamilyShareCacheStoreDescriptor {
        let storeURL = storeURL(for: namespaceID)
        let resolvedSchemaVersion = schemaVersion ?? FamilyShareCacheSchema.currentVersion
        return FamilyShareCacheStoreDescriptor(
            namespaceID: namespaceID,
            storeURL: storeURL,
            schemaVersion: resolvedSchemaVersion,
            isStoredInMemoryOnly: environment.isTestRun
        )
    }

    func makeStore(for namespaceID: FamilyShareNamespaceID, schemaVersion: Int? = nil) throws -> FamilyShareNamespaceStore {
        let descriptor = descriptor(for: namespaceID, schemaVersion: schemaVersion)
        let container = try makeContainer(for: descriptor)
        return FamilyShareNamespaceStore(descriptor: descriptor, container: container)
    }

    func makeContainer(for descriptor: FamilyShareCacheStoreDescriptor) throws -> ModelContainer {
        ensureStoreDirectoryExists()

        let configuration: ModelConfiguration
        if let storeURL = descriptor.storeURL, descriptor.isStoredInMemoryOnly == false {
            configuration = ModelConfiguration(
                descriptor.storeName,
                schema: FamilyShareCacheSchema.schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                descriptor.storeName,
                schema: FamilyShareCacheSchema.schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(for: FamilyShareCacheSchema.schema, configurations: [configuration])
    }

    func removeStoreFiles(for descriptor: FamilyShareCacheStoreDescriptor) {
        guard let storeURL = descriptor.storeURL else { return }
        let suffixes = ["", "-shm", "-wal", "-journal"]
        for suffix in suffixes {
            let path = storeURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    private func ensureStoreDirectoryExists() {
        guard let storeDirectory = storeDirectoryURL else { return }
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private var storeDirectoryURL: URL? {
        environment.applicationSupportURL?.appendingPathComponent("FamilySharing", isDirectory: true)
    }

    private func storeURL(for namespaceID: FamilyShareNamespaceID) -> URL? {
        storeDirectoryURL?.appendingPathComponent("\(namespaceID.storeName).store")
    }
}

@MainActor
final class FamilyShareNamespaceRegistry {
    private let factory: FamilyShareNamespaceStoreFactory
    private let maximumOpenStores: Int
    private var stores: [FamilyShareNamespaceID: FamilyShareNamespaceStore] = [:]
    private var accessOrder: [FamilyShareNamespaceID: Date] = [:]
    private var knownNamespaceIDs: Set<FamilyShareNamespaceID> = []

    init(factory: FamilyShareNamespaceStoreFactory? = nil, maximumOpenStores: Int = 2) {
        self.factory = factory ?? FamilyShareNamespaceStoreFactory()
        self.maximumOpenStores = max(1, maximumOpenStores)
    }

    func store(for namespaceID: FamilyShareNamespaceID) throws -> FamilyShareNamespaceStore {
        if let existing = stores[namespaceID] {
            existing.touch()
            accessOrder[namespaceID] = existing.lastAccessedAt
            knownNamespaceIDs.insert(namespaceID)
            return existing
        }

        evictIfNeeded(beforeAdding: namespaceID)
        let store = try factory.makeStore(for: namespaceID)
        stores[namespaceID] = store
        accessOrder[namespaceID] = Date()
        knownNamespaceIDs.insert(namespaceID)
        return store
    }

    func seed(_ seededState: FamilyShareSeededNamespaceState) throws {
        let namespaceID = seededState.ownerState.namespaceID
        let store = try store(for: namespaceID)
        let context = store.mainContext
        let canonicalProjection = seededState.canonicalInviteeProjection

        let existingRoots = try context.fetch(FetchDescriptor<FamilySharedDatasetCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        }))
        let existingGoals = try context.fetch(FetchDescriptor<FamilySharedGoalCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        }))
        let existingSections = try context.fetch(FetchDescriptor<FamilySharedOwnerSectionCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        }))

        existingGoals.forEach { context.delete($0) }
        existingSections.forEach { context.delete($0) }
        existingRoots.forEach { context.delete($0) }

        let root = FamilySharedDatasetCache(
            namespaceID: namespaceID,
            ownerDisplayName: FamilyShareOwnerIdentityResolver.resolve(displayName: seededState.ownerDisplayName).displayName,
            schemaVersion: seededState.projectionPayload?.schemaVersion ?? FamilyShareCacheSchema.currentVersion,
            projectionVersion: seededState.projectionPayload?.projectionVersion ?? 1,
            activeProjectionVersion: seededState.projectionPayload?.activeProjectionVersion ?? 1,
            freshnessStateRawValue: seededState.inviteeState.map { $0.lifecycleState.rawValue } ?? FamilyShareLifecycleState.active.rawValue,
            lifecycleStateRawValue: seededState.ownerState.lifecycleState.rawValue,
            publishedAt: seededState.projectionPayload?.publishedAt,
            lastReconciledAt: seededState.projectionPayload?.lastReconciledAt,
            lastRefreshAttemptAt: seededState.projectionPayload?.lastRefreshAttemptAt,
            lastRefreshErrorCode: seededState.projectionPayload?.lastRefreshErrorCode,
            lastRefreshErrorMessage: seededState.projectionPayload?.lastRefreshErrorMessage,
            summaryTitle: canonicalProjection.entryTitle,
            summaryCopy: canonicalProjection.entrySummary,
            participantCount: seededState.ownerState.participantCount,
            pendingParticipantCount: seededState.ownerState.pendingParticipantCount,
            revokedParticipantCount: seededState.ownerState.revokedParticipantCount
        )
        context.insert(root)

        for (sectionIndex, section) in canonicalProjection.sections.enumerated() {
            for (goalIndex, goal) in section.goals.enumerated() {
                context.insert(FamilySharedGoalCache(
                    namespaceID: namespaceID,
                    ownerDisplayName: goal.ownerIdentity.displayName,
                    goalID: goal.id,
                    goalName: goal.goalName,
                    goalEmoji: goal.emoji,
                    currency: goal.currency,
                    targetAmount: Decimal(goal.targetAmount),
                    currentAmount: Decimal(goal.currentAmount),
                    progressRatio: goal.progress,
                    deadline: goal.deadline,
                    goalStatusRawValue: goal.lifecycleState.rawValue,
                    forecastStateRawValue: nil,
                    freshnessStateRawValue: goal.shareState.rawValue,
                    lastUpdatedAt: goal.lastUpdatedAt,
                    summaryCopy: goal.detailSummary ?? goal.amountSummary,
                    sortIndex: goalIndex
                ))
            }

            context.insert(FamilySharedOwnerSectionCache(
                namespaceID: namespaceID,
                ownerDisplayName: section.ownerIdentity.displayName,
                goalCount: section.goals.count,
                freshnessStateRawValue: section.state.rawValue,
                lifecycleStateRawValue: seededState.ownerState.lifecycleState.rawValue,
                sortIndex: sectionIndex,
                inlineChipCopy: section.ownerIdentity.displayName
            ))
        }

        try context.save()
        knownNamespaceIDs.insert(namespaceID)
    }

    func seedTestScenario(_ scenario: FamilyShareTestScenario, namespaceID: FamilyShareNamespaceID) throws {
        try seed(FamilyShareTestSeeder.makeSeed(for: scenario, namespaceID: namespaceID))
    }

    func seededState(for namespaceID: FamilyShareNamespaceID) throws -> FamilyShareSeededNamespaceState? {
        let store = try store(for: namespaceID)
        let context = store.mainContext
        let root = try context.fetch(FetchDescriptor<FamilySharedDatasetCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        })).first
        guard let root else { return nil }
        let ownerIdentity = FamilyShareOwnerIdentityResolver.resolve(displayName: root.ownerDisplayName)

        let goals = try context.fetch(FetchDescriptor<FamilySharedGoalCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        }))
        let sections = try context.fetch(FetchDescriptor<FamilySharedOwnerSectionCache>(predicate: #Predicate {
            $0.namespaceKey == namespaceID.namespaceKey
        }))

        let projectionPayload = root.projectionVersion > 0 ? FamilyShareProjectionPayload(
            namespaceID: namespaceID,
            ownerDisplayName: ownerIdentity.displayName,
            schemaVersion: root.schemaVersion,
            projectionVersion: root.projectionVersion,
            activeProjectionVersion: root.activeProjectionVersion,
            freshnessStateRawValue: root.freshnessStateRawValue,
            lifecycleStateRawValue: root.lifecycleStateRawValue,
            publishedAt: root.publishedAt,
            lastReconciledAt: root.lastReconciledAt,
            lastRefreshAttemptAt: root.lastRefreshAttemptAt,
            lastRefreshErrorCode: root.lastRefreshErrorCode,
            lastRefreshErrorMessage: root.lastRefreshErrorMessage,
            summaryTitle: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                lifecycleState: FamilyShareLifecycleState(rawValue: root.freshnessStateRawValue) ?? .active,
                fallback: root.summaryTitle
            ),
            summaryCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: FamilyShareLifecycleState(rawValue: root.freshnessStateRawValue) ?? .active,
                fallback: root.summaryCopy
            ),
            participantCount: root.participantCount,
            pendingParticipantCount: root.pendingParticipantCount,
            revokedParticipantCount: root.revokedParticipantCount,
            goals: goals.sorted(by: { $0.sortIndex < $1.sortIndex }).map { cache in
                let resolvedOwnerIdentity = FamilyShareOwnerIdentityResolver.resolve(displayName: cache.ownerDisplayName)
                return FamilyShareProjectedGoalPayload(
                    id: cache.cacheKey,
                    namespaceID: namespaceID,
                    ownerID: cache.ownerID,
                    ownerDisplayName: resolvedOwnerIdentity.displayName,
                    goalID: cache.goalID,
                    goalName: cache.goalName,
                    goalEmoji: cache.goalEmoji,
                    currency: cache.currency,
                    targetAmount: cache.targetAmount,
                    currentAmount: cache.currentAmount,
                    progressRatio: cache.progressRatio,
                    deadline: cache.deadline,
                    goalStatusRawValue: cache.goalStatusRawValue,
                    forecastStateRawValue: cache.forecastStateRawValue,
                    freshnessStateRawValue: cache.freshnessStateRawValue,
                    lastUpdatedAt: cache.lastUpdatedAt,
                    summaryCopy: FamilyShareOwnerIdentityResolver.canonicalGoalContributionSummary(
                        currency: cache.currency,
                        currentAmount: NSDecimalNumber(decimal: cache.currentAmount).doubleValue,
                        targetAmount: NSDecimalNumber(decimal: cache.targetAmount).doubleValue
                    ),
                    sortIndex: cache.sortIndex
                )
            },
            ownerSections: sections.sorted(by: { $0.sortIndex < $1.sortIndex }).map { cache in
                let resolvedOwnerIdentity = FamilyShareOwnerIdentityResolver.resolve(displayName: cache.ownerDisplayName)
                return FamilyShareOwnerSectionPayload(
                    id: cache.cacheKey,
                    namespaceID: namespaceID,
                    ownerID: cache.ownerID,
                    ownerDisplayName: resolvedOwnerIdentity.displayName,
                    goalCount: cache.goalCount,
                    freshnessStateRawValue: cache.freshnessStateRawValue,
                    sortIndex: cache.sortIndex,
                    inlineChipCopy: resolvedOwnerIdentity.displayName
                )
            }
        ) : nil

        let lifecycleState = FamilyShareLifecycleState(rawValue: root.freshnessStateRawValue) ?? .active
        let primaryActionCopy: String
        switch lifecycleState {
        case .invitePendingAcceptance:
            primaryActionCopy = "Accept"
        case .emptySharedDataset:
            primaryActionCopy = "Retry"
        case .active:
            primaryActionCopy = "Retry"
        case .stale:
            primaryActionCopy = "Retry Refresh"
        case .temporarilyUnavailable:
            primaryActionCopy = "Retry"
        case .revoked:
            primaryActionCopy = "Ask owner to re-share"
        case .removedOrNoLongerShared:
            primaryActionCopy = "Dismiss"
        }

        let inviteeState = FamilyShareInviteeViewState(
            namespaceID: namespaceID,
            ownerDisplayName: ownerIdentity.displayName,
            lifecycleState: lifecycleState,
            goalCount: goals.count,
            lastUpdatedAt: root.lastReconciledAt ?? root.publishedAt,
            asOfCopy: root.publishedAt.map { "As of \($0.formatted(date: .abbreviated, time: .shortened))" },
            titleCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                lifecycleState: lifecycleState,
                fallback: root.summaryTitle
            ),
            messageCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: lifecycleState,
                fallback: root.summaryCopy
            ),
            primaryActionCopy: primaryActionCopy,
            isReadOnly: true
        )

        let ownerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: FamilyShareOwnerLifecycleState(rawValue: root.lifecycleStateRawValue) ?? .sharedActive,
            participantCount: root.participantCount,
            pendingParticipantCount: root.pendingParticipantCount,
            activeParticipantCount: max(0, root.participantCount - root.pendingParticipantCount - root.revokedParticipantCount),
            revokedParticipantCount: root.revokedParticipantCount,
            failedParticipantCount: 0,
            summaryCopy: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: lifecycleState,
                fallback: root.summaryCopy
            ),
            primaryActionCopy: root.lifecycleStateRawValue == FamilyShareOwnerLifecycleState.notShared.rawValue ? "Share with Family" : "Manage Participants"
        )

        return FamilyShareSeededNamespaceState(
            ownerDisplayName: ownerIdentity.displayName,
            ownerState: ownerState,
            inviteeState: inviteeState,
            projectionPayload: projectionPayload
        )
    }

    func snapshot(for namespaceID: FamilyShareNamespaceID) throws -> FamilyShareInviteeViewState? {
        return try seededState(for: namespaceID)?.inviteeState
    }

    func seededStates() throws -> [FamilyShareSeededNamespaceState] {
        try allNamespaceIDs().compactMap { namespaceID in
            try seededState(for: namespaceID)
        }
    }

    func purge(namespaceID: FamilyShareNamespaceID) {
        let descriptor = stores[namespaceID]?.descriptor ?? factory.descriptor(for: namespaceID)
        stores.removeValue(forKey: namespaceID)
        factory.removeStoreFiles(for: descriptor)
        accessOrder.removeValue(forKey: namespaceID)
        knownNamespaceIDs.remove(namespaceID)
    }

    func purgeAllNamespaces() {
        let namespaces = Array(knownNamespaceIDs)
        namespaces.forEach { purge(namespaceID: $0) }
        stores.removeAll()
        accessOrder.removeAll()
        knownNamespaceIDs.removeAll()
    }

    func allNamespaceIDs() -> [FamilyShareNamespaceID] {
        knownNamespaceIDs.sorted { lhs, rhs in
            lhs.namespaceKey < rhs.namespaceKey
        }
    }

    private func evictIfNeeded(beforeAdding namespaceID: FamilyShareNamespaceID) {
        if factory.descriptor(for: namespaceID).isStoredInMemoryOnly || stores.values.contains(where: { $0.descriptor.isStoredInMemoryOnly }) {
            return
        }

        guard stores.count >= maximumOpenStores else { return }
        let evictionCandidates = accessOrder
            .filter { $0.key != namespaceID }
            .sorted { $0.value < $1.value }
        guard let oldest = evictionCandidates.first?.key else { return }
        stores.removeValue(forKey: oldest)
        accessOrder.removeValue(forKey: oldest)
    }
}
