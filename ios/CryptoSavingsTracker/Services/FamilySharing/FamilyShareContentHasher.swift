import Foundation
import CryptoKit

/// Produces deterministic SHA-256 content hashes for shared projection payloads.
///
/// The hash covers ALL invitee-visible state, including:
/// - Goal data (IDs, currentAmount, targetAmount, allocation structure)
/// - Rate snapshot timestamp
/// - Root metadata (owner display name, participant list, participant count)
///
/// `.participantChange` dirty events produce a different hash because root
/// metadata is included — these publishes are never incorrectly deduplicated.
struct FamilyShareContentHasher: Sendable {
    nonisolated init() {}

    /// Compute a deterministic content hash from canonical projection data.
    ///
    /// All fields are sorted before hashing to ensure determinism regardless of
    /// iteration order.
    ///
    /// - Parameters:
    ///   - goalData: Per-goal amounts and targets, keyed by goal ID.
    ///   - rateSnapshotTimestamp: When the rates used for computation were fetched.
    ///   - ownerDisplayName: The owner's display name visible to invitees.
    ///   - participantIDs: Sorted participant identifiers.
    /// - Returns: Hex-encoded SHA-256 digest string.
    nonisolated func hash(
        goalData: [(goalID: UUID, currentAmount: Decimal, targetAmount: Decimal)],
        rateSnapshotTimestamp: Date?,
        ownerDisplayName: String?,
        participantIDs: [String]
    ) -> String {
        var components: [String] = []

        // Goal data — sorted by goalID for determinism
        let sortedGoals = goalData.sorted { $0.goalID.uuidString < $1.goalID.uuidString }
        for goal in sortedGoals {
            components.append("g:\(goal.goalID.uuidString):\(goal.currentAmount):\(goal.targetAmount)")
        }

        // Rate snapshot timestamp
        if let rateTimestamp = rateSnapshotTimestamp {
            components.append("r:\(rateTimestamp.timeIntervalSince1970)")
        }

        // Owner display name
        if let name = ownerDisplayName {
            components.append("o:\(name)")
        }

        // Participant IDs — sorted for determinism
        let sortedParticipants = participantIDs.sorted()
        for pid in sortedParticipants {
            components.append("p:\(pid)")
        }

        // Participant count (redundant with list but protects against empty-list edge cases)
        components.append("pc:\(participantIDs.count)")

        let canonical = components.joined(separator: "|")
        let data = Data(canonical.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
