//
//  FamilySharingModels.swift
//  CryptoSavingsTracker
//
//  Self-contained models for family sharing UI.
//

import Foundation
import SwiftUI

enum FamilyShareParticipantState: String, CaseIterable, Identifiable, Codable, Sendable {
    case pending
    case active
    case revoked
    case failed

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Active"
        case .revoked: return "Revoked"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .active: return "person.crop.circle.badge.checkmark"
        case .revoked: return "person.crop.circle.badge.xmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return AccessibleColors.warning
        case .active: return AccessibleColors.success
        case .revoked: return AccessibleColors.secondaryInteractive
        case .failed: return AccessibleColors.error
        }
    }
}

enum FamilyShareSurfaceState: String, CaseIterable, Identifiable, Codable, Sendable {
    case invitePendingAcceptance
    case emptySharedDataset
    case active
    case stale
    case temporarilyUnavailable
    case revoked
    case removedOrNoLongerShared

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .invitePendingAcceptance: return "Invitation pending"
        case .emptySharedDataset: return "No shared goals"
        case .active: return "Active"
        case .stale: return "Out of date"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        case .revoked: return "Access revoked"
        case .removedOrNoLongerShared: return "No longer shared"
        }
    }

    var systemImage: String {
        switch self {
        case .invitePendingAcceptance: return "clock.badge.questionmark"
        case .emptySharedDataset: return "tray"
        case .active: return "person.2.fill"
        case .stale: return "exclamationmark.circle.fill"
        case .temporarilyUnavailable: return "wifi.exclamationmark"
        case .revoked: return "person.crop.circle.badge.xmark"
        case .removedOrNoLongerShared: return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .invitePendingAcceptance: return AccessibleColors.warning
        case .emptySharedDataset: return AccessibleColors.secondaryInteractive
        case .active: return AccessibleColors.success
        case .stale: return AccessibleColors.warning
        case .temporarilyUnavailable: return AccessibleColors.error
        case .revoked: return AccessibleColors.secondaryInteractive
        case .removedOrNoLongerShared: return AccessibleColors.error
        }
    }

    var supportingCopy: String {
        switch self {
        case .invitePendingAcceptance:
            return "Waiting for the participant to accept the CloudKit invitation."
        case .emptySharedDataset:
            return "The share is active, but there are no visible goals yet."
        case .active:
            return "Shared read-only data is available and current."
        case .stale:
            return "The shared cache may not reflect the latest owner changes."
        case .temporarilyUnavailable:
            return "CloudKit or the local cache cannot be trusted right now."
        case .revoked:
            return "The owner removed access to the shared dataset."
        case .removedOrNoLongerShared:
            return "The shared dataset is no longer available for this invitee."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .invitePendingAcceptance: return "Accept"
        case .emptySharedDataset: return "Retry"
        case .active: return "Refresh"
        case .stale: return "Retry Refresh"
        case .temporarilyUnavailable: return "Retry"
        case .revoked: return "Ask owner to re-share"
        case .removedOrNoLongerShared: return "Dismiss"
        }
    }
}

enum FamilyShareGoalLifecycleState: String, CaseIterable, Codable, Sendable {
    case current
    case onTrack
    case justStarted
    case achieved
    case expired

    var displayTitle: String {
        switch self {
        case .current: return "Current"
        case .onTrack: return "On track"
        case .justStarted: return "Just started"
        case .achieved: return "Achieved"
        case .expired: return "Expired"
        }
    }

    var tint: Color {
        switch self {
        case .current: return AccessibleColors.primaryInteractive
        case .onTrack: return AccessibleColors.secondaryInteractive
        case .justStarted: return AccessibleColors.primaryInteractive
        case .achieved: return AccessibleColors.success
        case .expired: return AccessibleColors.error
        }
    }

    var defaultRowChipTitle: String? {
        switch self {
        case .achieved, .expired:
            return displayTitle
        case .current, .onTrack, .justStarted:
            return nil
        }
    }

    static func from(rawValue: String) -> Self {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("achiev") || normalized.contains("complet") {
            return .achieved
        }
        if normalized.contains("expir") {
            return .expired
        }
        if normalized.contains("just started") || normalized.contains("just_started") || normalized == "started" {
            return .justStarted
        }
        if normalized.contains("on track") || normalized.contains("on_track") {
            return .onTrack
        }
        return .current
    }
}

struct FamilyShareOwnerIdentity: Hashable, Codable, Sendable {
    var displayName: String
    var accessibilityLabel: String
    var isFallback: Bool
}

enum FamilyShareOwnerIdentityResolver {
    static let inviteeEntryTitle = "Shared with You"
    static let inviteeFallbackOwnerLabel = "Family member"

    static func resolve(displayName rawValue: String) -> FamilyShareOwnerIdentity {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return FamilyShareOwnerIdentity(
                displayName: inviteeFallbackOwnerLabel,
                accessibilityLabel: inviteeFallbackOwnerLabel,
                isFallback: true
            )
        }

        let lower = trimmed.lowercased()
        if lower == inviteeFallbackOwnerLabel.lowercased() || isBlockedDisplayName(lower) {
            return FamilyShareOwnerIdentity(
                displayName: inviteeFallbackOwnerLabel,
                accessibilityLabel: "Shared by family member",
                isFallback: true
            )
        }

        return FamilyShareOwnerIdentity(
            displayName: trimmed,
            accessibilityLabel: trimmed,
            isFallback: false
        )
    }

    static func canonicalInviteeTitle(
        lifecycleState: FamilyShareLifecycleState,
        fallback: String? = nil
    ) -> String {
        let sanitizedFallback = sanitizeCopy(fallback)
        switch lifecycleState {
        case .active:
            return inviteeEntryTitle
        case .invitePendingAcceptance:
            return sanitizedFallback ?? "Invitation pending"
        case .emptySharedDataset:
            return sanitizedFallback ?? "No shared goals"
        case .stale:
            return sanitizedFallback ?? "Out of date"
        case .temporarilyUnavailable:
            return sanitizedFallback ?? "Temporarily unavailable"
        case .revoked:
            return sanitizedFallback ?? "Access revoked"
        case .removedOrNoLongerShared:
            return sanitizedFallback ?? "No longer shared"
        }
    }

    static func canonicalInviteeSummary(
        lifecycleState: FamilyShareLifecycleState,
        fallback: String? = nil
    ) -> String {
        if let fallback = sanitizeCopy(fallback) {
            return fallback
        }

        switch lifecycleState {
        case .invitePendingAcceptance:
            return "Finish accepting the invitation to view the shared goal set."
        case .emptySharedDataset:
            return "This shared goal set is available, but no goals are visible yet."
        case .active:
            return "Goals are grouped by owner and stay read-only."
        case .stale:
            return "Shared goals may be out of date. Retry to refresh this goal set."
        case .temporarilyUnavailable:
            return "Shared goals are temporarily unavailable. Try again in a moment."
        case .revoked:
            return "Access to this shared goal set was revoked. Ask the owner to share it again."
        case .removedOrNoLongerShared:
            return "This shared goal set is no longer available."
        }
    }

    static func canonicalSectionSummary(
        lifecycleState: FamilyShareLifecycleState,
        fallback: String? = nil
    ) -> String? {
        if let fallback = sanitizeCopy(fallback) {
            return fallback
        }

        switch lifecycleState {
        case .active:
            return nil
        case .invitePendingAcceptance:
            return "Waiting for the participant to accept the CloudKit invitation."
        case .emptySharedDataset:
            return "The share is active, but there are no visible goals yet."
        case .stale:
            return "The shared cache may not reflect the latest owner changes."
        case .temporarilyUnavailable:
            return "CloudKit or the local cache cannot be trusted right now."
        case .revoked:
            return "The owner removed access to the shared dataset."
        case .removedOrNoLongerShared:
            return "The shared dataset is no longer available for this invitee."
        }
    }

    static func canonicalPrimaryAction(
        lifecycleState: FamilyShareLifecycleState,
        fallback: String? = nil
    ) -> String? {
        if let fallback = sanitizeCopy(fallback) {
            return fallback
        }
        return FamilyShareSurfaceState(rawValue: lifecycleState.rawValue)?.primaryActionTitle
    }

    static func canonicalGoalLifecycleState(rawValue: String) -> FamilyShareGoalLifecycleState {
        FamilyShareGoalLifecycleState.from(rawValue: rawValue)
    }

    static func canonicalGoalDetailSummary(_ value: String?) -> String? {
        sanitizeCopy(value)
    }

    static func canonicalGoalContributionSummary(currency: String, currentAmount: Double, targetAmount: Double) -> String {
        let current = currentAmount.formatted(.number.precision(.fractionLength(0...2)))
        let target = targetAmount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(currency) \(current) of \(currency) \(target)"
    }

    static func ownershipLine(for identity: FamilyShareOwnerIdentity) -> String {
        if identity.isFallback {
            return "Shared by family member · Read-only"
        }
        return "Shared by \(identity.displayName) · Read-only"
    }

    static func disambiguatedSectionOwnerIdentities(
        for sections: [FamilyShareInviteeSectionProjection]
    ) -> [FamilyShareInviteeSectionProjection] {
        let fallbackIndices = sections.indices.filter { sections[$0].ownerIdentity.isFallback }
        guard fallbackIndices.count > 1 else {
            return sections
        }

        var disambiguatedSections = sections
        for (offset, index) in fallbackIndices.enumerated() {
            disambiguatedSections[index].ownerIdentity = FamilyShareOwnerIdentity(
                displayName: "\(inviteeFallbackOwnerLabel) \(offset + 1)",
                accessibilityLabel: "\(inviteeFallbackOwnerLabel) \(offset + 1)",
                isFallback: true
            )
        }
        return disambiguatedSections
    }

    private static func sanitizeCopy(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false, isLegacyCopy(normalized) == false else {
            return nil
        }
        return normalized
    }

    private static func isBlockedDisplayName(_ lowercasedValue: String) -> Bool {
        let blockedTokens = [
            "iphone",
            "ipad",
            "ipod",
            "macbook",
            "shared family",
            "shared goals",
            "family share",
            "device"
        ]
        return blockedTokens.contains(where: { lowercasedValue.contains($0) })
    }

    private static func isLegacyCopy(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "shared goals"
            || lower == "shared goals are read-only."
            || lower == "shared by family"
            || lower == "all current goals are shared in read-only mode."
            || lower == "read-only shared dataset seeded for tests."
            || lower == "latest shared goal set is available."
            || lower == "read-only shared goals appear here by owner."
            || lower == "shared goals appear here by owner."
            || lower == "read-only shared goals grouped by owner."
            || lower == "shared goal set available for read-only access."
            || lower == "goals are grouped by owner and stay read-only."
    }
}

struct FamilyShareInviteeGoalProjection: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var namespaceID: FamilyShareNamespaceID?
    var ownerIdentity: FamilyShareOwnerIdentity
    var goalName: String
    var emoji: String?
    var currency: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Date
    var lastUpdatedAt: Date?
    var shareState: FamilyShareSurfaceState
    var lifecycleState: FamilyShareGoalLifecycleState
    var detailSummary: String?

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(currentAmount / targetAmount, 0), 1)
    }

    var ownershipLine: String {
        FamilyShareOwnerIdentityResolver.ownershipLine(for: ownerIdentity)
    }

    var amountSummary: String {
        FamilyShareOwnerIdentityResolver.canonicalGoalContributionSummary(
            currency: currency,
            currentAmount: currentAmount,
            targetAmount: targetAmount
        )
    }

    var formattedTarget: String {
        "\(currency) \(targetAmount.formatted(.number.precision(.fractionLength(0...2))))"
    }

    var formattedCurrent: String {
        "\(currency) \(currentAmount.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

struct FamilyShareInviteeSectionProjection: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var namespaceID: FamilyShareNamespaceID
    var ownerIdentity: FamilyShareOwnerIdentity
    var goals: [FamilyShareInviteeGoalProjection]
    var state: FamilyShareSurfaceState
    var summaryCopy: String?
    var primaryActionTitle: String?

    var showsStateBanner: Bool {
        state != .active || goals.isEmpty
    }
}

struct FamilyShareInviteeProjection: Hashable, Codable, Sendable {
    var entryTitle: String
    var entrySummary: String
    var sections: [FamilyShareInviteeSectionProjection]

    static let empty = Self(
        entryTitle: FamilyShareOwnerIdentityResolver.inviteeEntryTitle,
        entrySummary: "Goals are grouped by owner and stay read-only.",
        sections: []
    )
}

struct FamilyShareParticipant: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var emailOrAlias: String?
    var state: FamilyShareParticipantState
    var lastUpdatedAt: Date?
    var isCurrentUser: Bool = false

    var initials: String {
        let components = displayName.split(separator: " ")
        let letters = components.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters)
    }
}

struct FamilySharedGoalSummary: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var namespaceID: FamilyShareNamespaceID?
    var ownerName: String
    var goalName: String
    var emoji: String?
    var currency: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Date
    var lastUpdatedAt: Date?
    var state: FamilyShareSurfaceState
    var contributionSummary: String
    var currentMonthSummary: String

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(currentAmount / targetAmount, 0), 1)
    }

    var ownerChip: String {
        ownerName
    }

    var formattedTarget: String {
        "\(currency) \(targetAmount.formatted(.number.precision(.fractionLength(0...2))))"
    }

    var formattedCurrent: String {
        "\(currency) \(currentAmount.formatted(.number.precision(.fractionLength(0...2))))"
    }

    init(
        id: String = UUID().uuidString,
        namespaceID: FamilyShareNamespaceID? = nil,
        ownerName: String,
        goalName: String,
        emoji: String? = nil,
        currency: String,
        targetAmount: Double,
        currentAmount: Double,
        deadline: Date,
        lastUpdatedAt: Date? = nil,
        state: FamilyShareSurfaceState,
        contributionSummary: String,
        currentMonthSummary: String
    ) {
        self.id = id
        self.namespaceID = namespaceID
        self.ownerName = ownerName
        self.goalName = goalName
        self.emoji = emoji
        self.currency = currency
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.deadline = deadline
        self.lastUpdatedAt = lastUpdatedAt
        self.state = state
        self.contributionSummary = contributionSummary
        self.currentMonthSummary = currentMonthSummary
    }
}

extension FamilySharedGoalSummary {
    init(goal: Goal, ownerName: String, state: FamilyShareSurfaceState = .active) {
        self.init(
            id: goal.id.uuidString,
            ownerName: ownerName,
            goalName: goal.name,
            emoji: goal.emoji,
            currency: goal.currency,
            targetAmount: goal.targetAmount,
            currentAmount: goal.manualTotal,
            deadline: goal.deadline,
            lastUpdatedAt: goal.lifecycleStatusChangedAt ?? goal.lastModifiedDate,
            state: state,
            contributionSummary: FamilyShareOwnerIdentityResolver.canonicalGoalContributionSummary(
                currency: goal.currency,
                currentAmount: goal.manualTotal,
                targetAmount: goal.targetAmount
            ),
            currentMonthSummary: FamilyShareGoalLifecycleState.from(rawValue: goal.status).displayTitle
        )
    }

    init(projection: FamilyShareInviteeGoalProjection) {
        self.init(
            id: projection.id,
            namespaceID: projection.namespaceID,
            ownerName: projection.ownerIdentity.displayName,
            goalName: projection.goalName,
            emoji: projection.emoji,
            currency: projection.currency,
            targetAmount: projection.targetAmount,
            currentAmount: projection.currentAmount,
            deadline: projection.deadline,
            lastUpdatedAt: projection.lastUpdatedAt,
            state: projection.shareState,
            contributionSummary: projection.amountSummary,
            currentMonthSummary: projection.lifecycleState.displayTitle
        )
    }
}

struct FamilyShareOwnerSection: Identifiable, Hashable, Codable, Sendable {
    var ownerID: String
    var shareID: String
    var ownerName: String
    var goals: [FamilySharedGoalSummary]
    var isCurrentOwner: Bool = false
    var state: FamilyShareSurfaceState = .active
    var summaryCopy: String? = nil
    var primaryActionTitle: String? = nil

    var id: String {
        "\(ownerID.lowercased())-\(shareID.lowercased())"
    }
}

extension FamilyShareOwnerSection {
    init(projection: FamilyShareInviteeSectionProjection) {
        self.init(
            ownerID: projection.namespaceID.ownerID,
            shareID: projection.namespaceID.shareID,
            ownerName: projection.ownerIdentity.displayName,
            goals: projection.goals.map(FamilySharedGoalSummary.init(projection:)),
            isCurrentOwner: false,
            state: projection.state,
            summaryCopy: projection.summaryCopy,
            primaryActionTitle: projection.primaryActionTitle
        )
    }
}

struct FamilyShareScopeDisclosureSection: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case visibleData
        case excludedData
        case revokeBehavior
    }

    var kind: Kind
    var title: String
    var rows: [String]

    var id: String { kind.rawValue }
}

struct FamilyShareScopePreviewModel: Hashable, Codable, Sendable {
    var ownerName: String
    var summaryPoints: [String]
    var sections: [FamilyShareScopeDisclosureSection]

    static var demo: Self {
        Self(
            ownerName: "Alex",
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
}

struct FamilyAccessModel: Hashable, Codable, Sendable {
    var ownerName: String
    var subtitle: String
    var participants: [FamilyShareParticipant]
    var ownerSections: [FamilyShareOwnerSection]
    var state: FamilyShareSurfaceState
    var scopePreview: FamilyShareScopePreviewModel

    static var demo: Self {
        Self(
            ownerName: "Alex",
            subtitle: "Invite family members to view all of your goals in read-only mode.",
            participants: [
                FamilyShareParticipant(displayName: "Marta", emailOrAlias: "marta@example.com", state: .active, lastUpdatedAt: Date()),
                FamilyShareParticipant(displayName: "Chris", emailOrAlias: "pending", state: .pending, lastUpdatedAt: Date()),
                FamilyShareParticipant(displayName: "Family Sync", emailOrAlias: nil, state: .failed, lastUpdatedAt: Date())
            ],
            ownerSections: [
                FamilyShareOwnerSection(
                    ownerID: "alex-owner",
                    shareID: "alex-share",
                    ownerName: "Alex",
                    goals: [
                        FamilySharedGoalSummary(
                            namespaceID: FamilyShareNamespaceID(ownerID: "alex-owner", shareID: "alex-share"),
                            ownerName: "Alex",
                            goalName: "For daughter's school",
                            emoji: "🎓",
                            currency: "USD",
                            targetAmount: 1276,
                            currentAmount: 749,
                            deadline: Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now,
                            lastUpdatedAt: .now,
                            state: .active,
                            contributionSummary: "Planned: USD 749 of USD 1,276",
                            currentMonthSummary: "On track"
                        ),
                        FamilySharedGoalSummary(
                            namespaceID: FamilyShareNamespaceID(ownerID: "alex-owner", shareID: "alex-share"),
                            ownerName: "Alex",
                            goalName: "Emergency fund",
                            emoji: "🛡️",
                            currency: "USD",
                            targetAmount: 5000,
                            currentAmount: 2400,
                            deadline: Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now,
                            lastUpdatedAt: .now,
                            state: .stale,
                            contributionSummary: "Cached view may be out of date",
                            currentMonthSummary: "Current"
                        )
                    ],
                    isCurrentOwner: true,
                    state: .active
                )
            ],
            state: .active,
            scopePreview: .demo
        )
    }
}

extension FamilyShareSeededNamespaceState {
    var canonicalInviteeProjection: FamilyShareInviteeProjection {
        let inviteeLifecycle = inviteeState?.lifecycleState ?? (projectionPayload?.goals.isEmpty == false ? .active : .emptySharedDataset)
        let sectionState = FamilyShareSurfaceState(rawValue: inviteeLifecycle.rawValue) ?? .active
        let ownerIdentity = FamilyShareOwnerIdentityResolver.resolve(displayName: ownerDisplayName)
        let goals = projectionPayload?.goals
            .sorted(by: { $0.sortIndex < $1.sortIndex })
            .map { goal in
                FamilyShareInviteeGoalProjection(
                    id: goal.id,
                    namespaceID: goal.namespaceID,
                    ownerIdentity: FamilyShareOwnerIdentityResolver.resolve(displayName: goal.ownerDisplayName),
                    goalName: goal.goalName,
                    emoji: goal.goalEmoji,
                    currency: goal.currency,
                    targetAmount: NSDecimalNumber(decimal: goal.targetAmount).doubleValue,
                    currentAmount: NSDecimalNumber(decimal: goal.currentAmount).doubleValue,
                    deadline: goal.deadline,
                    lastUpdatedAt: goal.lastUpdatedAt,
                    shareState: sectionState,
                    lifecycleState: FamilyShareOwnerIdentityResolver.canonicalGoalLifecycleState(rawValue: goal.goalStatusRawValue),
                    detailSummary: FamilyShareOwnerIdentityResolver.canonicalGoalDetailSummary(goal.summaryCopy)
                )
            } ?? []

        let section = FamilyShareInviteeSectionProjection(
            id: projectionPayload?.namespaceID.namespaceKey ?? ownerState.namespaceID.namespaceKey,
            namespaceID: projectionPayload?.namespaceID ?? ownerState.namespaceID,
            ownerIdentity: ownerIdentity,
            goals: goals,
            state: sectionState,
            summaryCopy: FamilyShareOwnerIdentityResolver.canonicalSectionSummary(
                lifecycleState: inviteeLifecycle,
                fallback: inviteeState?.messageCopy
            ),
            primaryActionTitle: FamilyShareOwnerIdentityResolver.canonicalPrimaryAction(
                lifecycleState: inviteeLifecycle,
                fallback: inviteeState?.primaryActionCopy
            )
        )

        return FamilyShareInviteeProjection(
            entryTitle: FamilyShareOwnerIdentityResolver.canonicalInviteeTitle(
                lifecycleState: inviteeLifecycle,
                fallback: inviteeState?.titleCopy
            ),
            entrySummary: FamilyShareOwnerIdentityResolver.canonicalInviteeSummary(
                lifecycleState: inviteeLifecycle,
                fallback: inviteeState?.messageCopy
            ),
            sections: (projectionPayload != nil || inviteeState != nil) ? [section] : []
        )
    }
}
