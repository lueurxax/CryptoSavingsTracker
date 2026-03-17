//
//  FamilySharingSupport.swift
//  CryptoSavingsTracker
//

import Foundation
import SwiftData

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

struct FamilyShareNamespaceID: Hashable, Codable, Sendable, Identifiable {
    let ownerID: String
    let shareID: String

    var id: String { namespaceKey }

    var namespaceKey: String {
        "\(ownerID)|\(shareID)"
    }

    var cacheSlug: String {
        let components = [ownerID, shareID].map { value in
            value
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
        }
        return components.joined(separator: "_")
    }

    var storeName: String {
        "family-share-\(cacheSlug)"
    }

    var storeFolderName: String {
        "FamilySharing"
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
        summaryTitle: String = "Shared Goals",
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
