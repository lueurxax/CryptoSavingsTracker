import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareContentHasherTests: XCTestCase {

    let hasher = FamilyShareContentHasher()

    // MARK: - Determinism

    func testHash_isDeterministic() {
        let goalID = UUID()
        let hash1 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: Date(timeIntervalSince1970: 1000),
            ownerDisplayName: "Alice",
            participantIDs: ["p1", "p2"]
        )
        let hash2 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: Date(timeIntervalSince1970: 1000),
            ownerDisplayName: "Alice",
            participantIDs: ["p1", "p2"]
        )
        XCTAssertEqual(hash1, hash2)
    }

    // MARK: - Sensitivity

    func testHash_changesWhenGoalAmountChanges() {
        let goalID = UUID()
        let hash1 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: []
        )
        let hash2 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 200, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: []
        )
        XCTAssertNotEqual(hash1, hash2)
    }

    func testHash_changesWhenOwnerNameChanges() {
        let goalID = UUID()
        let hash1 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: []
        )
        let hash2 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Bob",
            participantIDs: []
        )
        XCTAssertNotEqual(hash1, hash2)
    }

    func testHash_changesWhenParticipantsChange() {
        let goalID = UUID()
        let hash1 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: ["p1"]
        )
        let hash2 = hasher.hash(
            goalData: [(goalID: goalID, currentAmount: 100, targetAmount: 1000)],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: ["p1", "p2"]
        )
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Order Independence

    func testHash_insensitiveToGoalOrder() {
        let goal1 = UUID()
        let goal2 = UUID()
        let hash1 = hasher.hash(
            goalData: [
                (goalID: goal1, currentAmount: 100, targetAmount: 1000),
                (goalID: goal2, currentAmount: 200, targetAmount: 2000)
            ],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: []
        )
        let hash2 = hasher.hash(
            goalData: [
                (goalID: goal2, currentAmount: 200, targetAmount: 2000),
                (goalID: goal1, currentAmount: 100, targetAmount: 1000)
            ],
            rateSnapshotTimestamp: nil,
            ownerDisplayName: "Alice",
            participantIDs: []
        )
        XCTAssertEqual(hash1, hash2)
    }
}
