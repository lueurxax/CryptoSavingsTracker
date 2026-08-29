import Foundation

enum AssetBalanceAccountingMode: String, Codable, Sendable, CaseIterable {
    case manual
    case onChain
    case mixed
}

enum FinishedAllocationSettlement: String, Codable, Sendable, CaseIterable {
    case keepAsSpent
    case balanceAlreadyDecreased
}

enum GoalCompletionBalanceTiming: String, Codable, Sendable {
    case completionTime
    case reviewTime
}

struct GoalCompletionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let allocationID: UUID
        let assetID: UUID
        let assetCurrency: String
        let amount: Double
        let accountingMode: AssetBalanceAccountingMode
        let settlement: FinishedAllocationSettlement
        let bestKnownBalance: Double?
        let balanceCapturedAt: Date?
        let balanceTiming: GoalCompletionBalanceTiming

        var id: UUID { allocationID }
    }

    let id: UUID
    let schemaVersion: Int
    let goalID: UUID
    let goalName: String
    let goalCurrency: String
    let goalTargetAmount: Double
    let goalCompletedAt: Date
    let snapshotCreatedAt: Date
    let entries: [Entry]
}

enum GoalCompletionSnapshotCodecError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

enum GoalCompletionSnapshotCodec {
    static func encode(_ snapshot: GoalCompletionSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> GoalCompletionSnapshot {
        let snapshot = try JSONDecoder().decode(GoalCompletionSnapshot.self, from: data)
        guard snapshot.schemaVersion == GoalCompletionSnapshot.currentSchemaVersion else {
            throw GoalCompletionSnapshotCodecError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }
}
