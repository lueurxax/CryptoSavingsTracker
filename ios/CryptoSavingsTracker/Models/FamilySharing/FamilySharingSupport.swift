//
//  FamilySharingSupport.swift
//  CryptoSavingsTracker
//

import Foundation
import SwiftData

enum FamilyShareReadOnlyAccessError: LocalizedError, Equatable {
    case sharedGoalReadOnly

    var errorDescription: String? {
        switch self {
        case .sharedGoalReadOnly:
            return FamilyShareTelemetryRedactor.readOnlyRejectionCopy
        }
    }
}

@MainActor
protocol FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool
    func assertOwnerWritable(goalID: UUID) throws
    func assertOwnerWritable(goal: Goal) throws
    func assertOwnerWritable(asset: Asset) throws
    func assertOwnerWritable(transaction: Transaction) throws
    func assertOwnerWritable(plan: MonthlyPlan) throws
    func assertOwnerWritable(plans: [MonthlyPlan]) throws
    func assertOwnerWritable(goals: [Goal]) throws
}

enum FamilySharePermission: String, Codable, CaseIterable, Sendable {
    case readOnly
}

enum FamilyShareLifecycleState: String, Codable, CaseIterable, Sendable {
    case invitePendingAcceptance
    case emptySharedDataset
    case active
    case stale
    case temporarilyUnavailable
    case revoked
    case removedOrNoLongerShared
}

enum FamilyShareOwnerLifecycleState: String, Codable, CaseIterable, Sendable {
    case notShared
    case invitePending
    case sharedActive
    case revoked
    case shareFailed
}

enum FamilyShareAcceptanceOutcome: String, Codable, CaseIterable, Sendable {
    case accepted
    case pending
    case rejected
    case failed
}

enum FamilyShareParticipantLifecycleState: String, Codable, CaseIterable, Sendable {
    case pending
    case active
    case revoked
    case failed
}

struct FamilyShareNamespaceID: Hashable, Codable, Sendable, Identifiable {
    let ownerID: String
    let shareID: String

    init(ownerID: String, shareID: String) {
        self.ownerID = ownerID
        self.shareID = shareID
    }

    nonisolated var id: String { namespaceKey }

    nonisolated var namespaceKey: String {
        "\(ownerID)|\(shareID)"
    }

    nonisolated var cacheSlug: String {
        let components = [ownerID, shareID].map { value in
            value
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
        }
        return components.joined(separator: "_")
    }

    nonisolated var storeName: String {
        "family-share-\(cacheSlug)"
    }

    nonisolated var storeFolderName: String {
        "FamilySharing"
    }

    init?(rootRecordName: String) {
        guard rootRecordName.hasPrefix("family-share."),
              rootRecordName.hasSuffix(".root") else {
            return nil
        }
        let trimmed = rootRecordName
            .replacingOccurrences(of: "family-share.", with: "")
            .replacingOccurrences(of: ".root", with: "")
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        self.init(ownerID: String(components[0]), shareID: String(components[1]))
    }

    init?(zoneName: String) {
        guard zoneName.hasPrefix("family-share."),
              zoneName.hasSuffix(".zone") else {
            return nil
        }
        let trimmed = zoneName
            .replacingOccurrences(of: "family-share.", with: "")
            .replacingOccurrences(of: ".zone", with: "")
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        self.init(ownerID: String(components[0]), shareID: String(components[1]))
    }

    init?(recordLocator: FamilyShareInvitationRecordLocator) {
        if let namespaceID = FamilyShareNamespaceID(rootRecordName: recordLocator.recordName) {
            self = namespaceID
            return
        }
        guard let zoneName = recordLocator.zoneName,
              let namespaceID = FamilyShareNamespaceID(zoneName: zoneName) else {
            return nil
        }
        self = namespaceID
    }

    nonisolated static func == (lhs: FamilyShareNamespaceID, rhs: FamilyShareNamespaceID) -> Bool {
        lhs.ownerID == rhs.ownerID && lhs.shareID == rhs.shareID
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ownerID)
        hasher.combine(shareID)
    }
}

struct FamilyShareInvitationMetadataSnapshot: Codable, Equatable, Sendable {
    let ownerDisplayName: String
    let shareURLString: String?
    let participantStatusRawValue: String
    let participantRoleRawValue: String?
    let participantPermissionRawValue: String?
    let rootRecordName: String?
    let rootZoneName: String?
    let rootZoneOwnerName: String?
    let hierarchicalRootRecordName: String?
    let hierarchicalRootZoneName: String?
    let hierarchicalRootZoneOwnerName: String?

    var rootRecordLookupCandidates: [FamilyShareInvitationRecordLocator] {
        var seen = Set<String>()
        var candidates: [FamilyShareInvitationRecordLocator] = []

        func append(recordName: String?, zoneName: String?, zoneOwnerName: String?) {
            guard let recordName, recordName.isEmpty == false else { return }
            let key = [recordName, zoneName ?? "", zoneOwnerName ?? ""].joined(separator: "|")
            guard seen.insert(key).inserted else { return }
            candidates.append(
                FamilyShareInvitationRecordLocator(
                    recordName: recordName,
                    zoneName: zoneName,
                    zoneOwnerName: zoneOwnerName
                )
            )
        }

        append(recordName: rootRecordName, zoneName: rootZoneName, zoneOwnerName: rootZoneOwnerName)
        append(
            recordName: hierarchicalRootRecordName,
            zoneName: hierarchicalRootZoneName,
            zoneOwnerName: hierarchicalRootZoneOwnerName
        )
        return candidates
    }
}

struct FamilyShareInvitationRecordLocator: Codable, Equatable, Sendable {
    let recordName: String
    let zoneName: String?
    let zoneOwnerName: String?
}

struct FamilyShareParticipantSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let emailOrAlias: String?
    let state: FamilyShareParticipantLifecycleState
    let lastUpdatedAt: Date?
    let isCurrentUser: Bool
}

struct FamilyShareOwnerShareSnapshot: Codable, Equatable, Sendable {
    let ownerState: FamilyShareOwnerViewState
    let participants: [FamilyShareParticipantSnapshot]

    var participantCount: Int {
        participants.count
    }

    var pendingParticipantCount: Int {
        participants.filter { $0.state == .pending }.count
    }

    var activeParticipantCount: Int {
        participants.filter { $0.state == .active }.count
    }

    var revokedParticipantCount: Int {
        participants.filter { $0.state == .revoked }.count
    }

    var failedParticipantCount: Int {
        participants.filter { $0.state == .failed }.count
    }
}

struct FamilyShareScopePreviewSummary: Codable, Equatable, Sendable {
    let title: String
    let summaryPoints: [String]
    let visibleDataSections: [String]
    let excludedDataSections: [String]
    let revokeBehavior: [String]
    let primaryActionCopy: String
}

struct FamilyShareInviteeViewState: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let ownerDisplayName: String
    let lifecycleState: FamilyShareLifecycleState
    let goalCount: Int
    let lastUpdatedAt: Date?
    let asOfCopy: String?
    let titleCopy: String
    let messageCopy: String
    let primaryActionCopy: String
    let isReadOnly: Bool
}

struct FamilyShareOwnerViewState: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let lifecycleState: FamilyShareOwnerLifecycleState
    let participantCount: Int
    let pendingParticipantCount: Int
    let activeParticipantCount: Int
    let revokedParticipantCount: Int
    let failedParticipantCount: Int
    let summaryCopy: String
    let primaryActionCopy: String
}

struct FamilyShareProjectedGoalPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let namespaceID: FamilyShareNamespaceID
    let ownerID: String
    let ownerDisplayName: String
    let goalID: String
    let goalName: String
    let goalEmoji: String?
    let currency: String
    let targetAmount: Decimal
    let currentAmount: Decimal
    let progressRatio: Double
    let deadline: Date
    let goalStatusRawValue: String
    let forecastStateRawValue: String?
    let freshnessStateRawValue: String
    let lastUpdatedAt: Date?
    let summaryCopy: String
    let sortIndex: Int
}

struct FamilyShareOwnerSectionPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let namespaceID: FamilyShareNamespaceID
    let ownerID: String
    let ownerDisplayName: String
    let goalCount: Int
    let freshnessStateRawValue: String
    let sortIndex: Int
    let inlineChipCopy: String
}

struct FamilyShareProjectionPayload: Codable, Equatable, Sendable {
    let namespaceID: FamilyShareNamespaceID
    let ownerDisplayName: String
    let schemaVersion: Int
    let projectionVersion: Int
    let activeProjectionVersion: Int
    let freshnessStateRawValue: String
    let lifecycleStateRawValue: String
    let publishedAt: Date?
    let lastReconciledAt: Date?
    let lastRefreshAttemptAt: Date?
    let lastRefreshErrorCode: String?
    let lastRefreshErrorMessage: String?
    let summaryTitle: String
    let summaryCopy: String
    let participantCount: Int
    let pendingParticipantCount: Int
    let revokedParticipantCount: Int
    let goals: [FamilyShareProjectedGoalPayload]
    let ownerSections: [FamilyShareOwnerSectionPayload]
}

struct FamilyShareSeededNamespaceState: Codable, Equatable, Sendable {
    let ownerDisplayName: String
    let ownerState: FamilyShareOwnerViewState
    let inviteeState: FamilyShareInviteeViewState?
    let projectionPayload: FamilyShareProjectionPayload?
}

enum FamilyShareCacheSchema {
    static let currentVersion = 1
    static let supportedVersions: ClosedRange<Int> = 1...1

    static var schema: Schema {
        Schema([
            FamilySharedDatasetCache.self,
            FamilySharedGoalCache.self,
            FamilySharedOwnerSectionCache.self
        ])
    }
}

@Model
final class FamilySharedDatasetCache {
    @Attribute(.unique) var namespaceKey: String
    var ownerID: String
    var shareID: String
    var ownerDisplayName: String
    var schemaVersion: Int
    var projectionVersion: Int
    var activeProjectionVersion: Int
    var freshnessStateRawValue: String
    var lifecycleStateRawValue: String
    var publishedAt: Date?
    var lastReconciledAt: Date?
    var lastRefreshAttemptAt: Date?
    var lastRefreshErrorCode: String?
    var lastRefreshErrorMessage: String?
    var summaryTitle: String
    var summaryCopy: String
    var participantCount: Int
    var pendingParticipantCount: Int
    var revokedParticipantCount: Int

    init(
        namespaceID: FamilyShareNamespaceID,
        ownerDisplayName: String,
        schemaVersion: Int = FamilyShareCacheSchema.currentVersion,
        projectionVersion: Int = 1,
        activeProjectionVersion: Int = 1,
        freshnessStateRawValue: String = FamilyShareLifecycleState.active.rawValue,
        lifecycleStateRawValue: String = FamilyShareOwnerLifecycleState.sharedActive.rawValue,
        publishedAt: Date? = nil,
        lastReconciledAt: Date? = nil,
        lastRefreshAttemptAt: Date? = nil,
        lastRefreshErrorCode: String? = nil,
        lastRefreshErrorMessage: String? = nil,
        summaryTitle: String = "Shared with You",
        summaryCopy: String = "",
        participantCount: Int = 0,
        pendingParticipantCount: Int = 0,
        revokedParticipantCount: Int = 0
    ) {
        self.namespaceKey = namespaceID.namespaceKey
        self.ownerID = namespaceID.ownerID
        self.shareID = namespaceID.shareID
        self.ownerDisplayName = ownerDisplayName
        self.schemaVersion = schemaVersion
        self.projectionVersion = projectionVersion
        self.activeProjectionVersion = activeProjectionVersion
        self.freshnessStateRawValue = freshnessStateRawValue
        self.lifecycleStateRawValue = lifecycleStateRawValue
        self.publishedAt = publishedAt
        self.lastReconciledAt = lastReconciledAt
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastRefreshErrorCode = lastRefreshErrorCode
        self.lastRefreshErrorMessage = lastRefreshErrorMessage
        self.summaryTitle = summaryTitle
        self.summaryCopy = summaryCopy
        self.participantCount = participantCount
        self.pendingParticipantCount = pendingParticipantCount
        self.revokedParticipantCount = revokedParticipantCount
    }
}

@Model
final class FamilySharedGoalCache {
    @Attribute(.unique) var cacheKey: String
    var namespaceKey: String
    var ownerID: String
    var shareID: String
    var ownerDisplayName: String
    var goalID: String
    var goalName: String
    var goalEmoji: String?
    var currency: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var progressRatio: Double
    var deadline: Date
    var goalStatusRawValue: String
    var forecastStateRawValue: String?
    var freshnessStateRawValue: String
    var lastUpdatedAt: Date?
    var summaryCopy: String
    var sortIndex: Int

    init(
        namespaceID: FamilyShareNamespaceID,
        ownerDisplayName: String,
        goalID: String,
        goalName: String,
        goalEmoji: String? = nil,
        currency: String,
        targetAmount: Decimal,
        currentAmount: Decimal,
        progressRatio: Double,
        deadline: Date,
        goalStatusRawValue: String,
        forecastStateRawValue: String? = nil,
        freshnessStateRawValue: String = FamilyShareLifecycleState.active.rawValue,
        lastUpdatedAt: Date? = nil,
        summaryCopy: String = "",
        sortIndex: Int = 0
    ) {
        self.cacheKey = "\(namespaceID.namespaceKey)|\(goalID)"
        self.namespaceKey = namespaceID.namespaceKey
        self.ownerID = namespaceID.ownerID
        self.shareID = namespaceID.shareID
        self.ownerDisplayName = ownerDisplayName
        self.goalID = goalID
        self.goalName = goalName
        self.goalEmoji = goalEmoji
        self.currency = currency
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.progressRatio = progressRatio
        self.deadline = deadline
        self.goalStatusRawValue = goalStatusRawValue
        self.forecastStateRawValue = forecastStateRawValue
        self.freshnessStateRawValue = freshnessStateRawValue
        self.lastUpdatedAt = lastUpdatedAt
        self.summaryCopy = summaryCopy
        self.sortIndex = sortIndex
    }
}

@Model
final class FamilySharedOwnerSectionCache {
    @Attribute(.unique) var cacheKey: String
    var namespaceKey: String
    var ownerID: String
    var shareID: String
    var ownerDisplayName: String
    var goalCount: Int
    var freshnessStateRawValue: String
    var lifecycleStateRawValue: String
    var sortIndex: Int
    var inlineChipCopy: String

    init(
        namespaceID: FamilyShareNamespaceID,
        ownerDisplayName: String,
        goalCount: Int,
        freshnessStateRawValue: String = FamilyShareLifecycleState.active.rawValue,
        lifecycleStateRawValue: String = FamilyShareOwnerLifecycleState.sharedActive.rawValue,
        sortIndex: Int = 0,
        inlineChipCopy: String = ""
    ) {
        self.cacheKey = "\(namespaceID.namespaceKey)|\(ownerDisplayName.lowercased())|\(sortIndex)"
        self.namespaceKey = namespaceID.namespaceKey
        self.ownerID = namespaceID.ownerID
        self.shareID = namespaceID.shareID
        self.ownerDisplayName = ownerDisplayName
        self.goalCount = goalCount
        self.freshnessStateRawValue = freshnessStateRawValue
        self.lifecycleStateRawValue = lifecycleStateRawValue
        self.sortIndex = sortIndex
        self.inlineChipCopy = inlineChipCopy
    }
}
