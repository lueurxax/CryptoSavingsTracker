import CryptoKit
import Foundation

/// Semantic state used to decide whether a Family projection is safe to deduplicate.
///
/// Publication/version timestamps are intentionally excluded because they describe
/// transport, not invitee-visible content. The rate timestamp remains included
/// because it is part of the invitee's freshness state.
struct FamilyShareContentHashInput: Sendable {
    let namespaceID: FamilyShareNamespaceID
    let ownerDisplayName: String
    let freshnessStateRawValue: String
    let lifecycleStateRawValue: String
    let summaryTitle: String
    let summaryCopy: String
    let participantCount: Int
    let pendingParticipantCount: Int
    let revokedParticipantCount: Int
    let goals: [FamilyShareProjectedGoalPayload]
    let ownerSections: [FamilyShareOwnerSectionPayload]
    let participants: [FamilyShareParticipantSnapshot]
    let rateSnapshotTimestamp: Date?
}

/// Produces a deterministic SHA-256 content hash over every semantic field
/// visible on the invitee projection and participant surface.
struct FamilyShareContentHasher: Sendable {
    nonisolated init() {}

    nonisolated func hash(_ input: FamilyShareContentHashInput) -> String {
        var components: [String] = []

        append("root.namespace.ownerID", input.namespaceID.ownerID, to: &components)
        append("root.namespace.shareID", input.namespaceID.shareID, to: &components)
        append("root.ownerDisplayName", input.ownerDisplayName, to: &components)
        append("root.freshness", input.freshnessStateRawValue, to: &components)
        append("root.lifecycle", input.lifecycleStateRawValue, to: &components)
        append("root.summaryTitle", input.summaryTitle, to: &components)
        append("root.summaryCopy", input.summaryCopy, to: &components)
        append("root.participantCount", input.participantCount, to: &components)
        append("root.pendingParticipantCount", input.pendingParticipantCount, to: &components)
        append("root.revokedParticipantCount", input.revokedParticipantCount, to: &components)
        append("root.rateSnapshotTimestamp", input.rateSnapshotTimestamp, to: &components)

        for goal in input.goals.sorted(by: canonicalGoalOrder) {
            append("goal.id", goal.id, to: &components)
            append("goal.namespace.ownerID", goal.namespaceID.ownerID, to: &components)
            append("goal.namespace.shareID", goal.namespaceID.shareID, to: &components)
            append("goal.ownerID", goal.ownerID, to: &components)
            append("goal.ownerDisplayName", goal.ownerDisplayName, to: &components)
            append("goal.goalID", goal.goalID, to: &components)
            append("goal.name", goal.goalName, to: &components)
            append("goal.emoji", goal.goalEmoji, to: &components)
            append("goal.currency", goal.currency, to: &components)
            append("goal.targetAmount", goal.targetAmount, to: &components)
            append("goal.currentAmount", goal.currentAmount, to: &components)
            append("goal.progressRatio", goal.progressRatio, to: &components)
            append("goal.deadline", goal.deadline, to: &components)
            append("goal.status", goal.goalStatusRawValue, to: &components)
            append("goal.forecastState", goal.forecastStateRawValue, to: &components)
            append("goal.freshness", goal.freshnessStateRawValue, to: &components)
            append("goal.lastUpdatedAt", goal.lastUpdatedAt, to: &components)
            append("goal.summaryCopy", goal.summaryCopy, to: &components)
            append("goal.sortIndex", goal.sortIndex, to: &components)
        }

        for section in input.ownerSections.sorted(by: canonicalOwnerSectionOrder) {
            append("section.id", section.id, to: &components)
            append("section.namespace.ownerID", section.namespaceID.ownerID, to: &components)
            append("section.namespace.shareID", section.namespaceID.shareID, to: &components)
            append("section.ownerID", section.ownerID, to: &components)
            append("section.ownerDisplayName", section.ownerDisplayName, to: &components)
            append("section.goalCount", section.goalCount, to: &components)
            append("section.freshness", section.freshnessStateRawValue, to: &components)
            append("section.sortIndex", section.sortIndex, to: &components)
            append("section.inlineChipCopy", section.inlineChipCopy, to: &components)
        }

        for participant in input.participants.sorted(by: canonicalParticipantOrder) {
            append("participant.id", participant.id, to: &components)
            append("participant.displayName", participant.displayName, to: &components)
            append("participant.emailOrAlias", participant.emailOrAlias, to: &components)
            append("participant.state", participant.state.rawValue, to: &components)
            append("participant.lastUpdatedAt", participant.lastUpdatedAt, to: &components)
            append("participant.isCurrentUser", participant.isCurrentUser, to: &components)
        }

        let digest = SHA256.hash(data: Data(components.joined().utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func canonicalGoalOrder(
        _ lhs: FamilyShareProjectedGoalPayload,
        _ rhs: FamilyShareProjectedGoalPayload
    ) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.goalID < rhs.goalID
    }

    private nonisolated func canonicalOwnerSectionOrder(
        _ lhs: FamilyShareOwnerSectionPayload,
        _ rhs: FamilyShareOwnerSectionPayload
    ) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.sortIndex < rhs.sortIndex
    }

    private nonisolated func canonicalParticipantOrder(
        _ lhs: FamilyShareParticipantSnapshot,
        _ rhs: FamilyShareParticipantSnapshot
    ) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.state.rawValue < rhs.state.rawValue
    }

    private nonisolated func append(
        _ key: String,
        _ value: String,
        to components: inout [String]
    ) {
        components.append(lengthPrefixed(key))
        components.append("s")
        components.append(lengthPrefixed(value))
    }

    private nonisolated func append(
        _ key: String,
        _ value: String?,
        to components: inout [String]
    ) {
        guard let value else {
            components.append(lengthPrefixed(key))
            components.append("n")
            return
        }
        append(key, value, to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Decimal,
        to components: inout [String]
    ) {
        append(key, NSDecimalNumber(decimal: value).stringValue, to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Double,
        to components: inout [String]
    ) {
        append(key, String(value.bitPattern), to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Int,
        to components: inout [String]
    ) {
        append(key, String(value), to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Bool,
        to components: inout [String]
    ) {
        append(key, value ? "1" : "0", to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Date,
        to components: inout [String]
    ) {
        append(key, value.timeIntervalSinceReferenceDate, to: &components)
    }

    private nonisolated func append(
        _ key: String,
        _ value: Date?,
        to components: inout [String]
    ) {
        guard let value else {
            append(key, Optional<String>.none, to: &components)
            return
        }
        append(key, value, to: &components)
    }

    private nonisolated func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}
