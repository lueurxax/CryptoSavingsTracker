//
//  FamilySharingModels.swift
//  CryptoSavingsTracker
//
//  Self-contained models for read-only family sharing UI.
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
        case .active: return "Shared by family"
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
        "Shared by \(ownerName)"
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
            contributionSummary: "Current progress reflects the latest shared projection.",
            currentMonthSummary: goal.status
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
                            currentMonthSummary: "On track for this month"
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
                            currentMonthSummary: "Retry refresh to confirm latest total"
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
