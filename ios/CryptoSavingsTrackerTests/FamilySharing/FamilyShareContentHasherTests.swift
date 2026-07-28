import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareContentHasherTests: XCTestCase {
    private let hasher = FamilyShareContentHasher()
    private let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
    private let goalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let deadline = Date(timeIntervalSince1970: 2_000)
    private let lastUpdatedAt = Date(timeIntervalSince1970: 1_500)

    func testHashIsDeterministicAndIndependentOfCollectionOrder() {
        let firstGoal = makeGoal()
        let secondGoal = makeGoal(
            goalID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            goalName: "Second goal",
            sortIndex: 1
        )
        let firstParticipant = makeParticipant(id: "p1", displayName: "Alex")
        let secondParticipant = makeParticipant(id: "p2", displayName: "Sam")

        let first = makeInput(
            goals: [firstGoal, secondGoal],
            participants: [firstParticipant, secondParticipant]
        )
        let reordered = makeInput(
            goals: [secondGoal, firstGoal],
            participants: [secondParticipant, firstParticipant]
        )

        XCTAssertEqual(hasher.hash(first), hasher.hash(reordered))
    }

    func testHashChangesForEveryInviteeVisibleGoalFieldUsedByDedup() {
        let baseline = hasher.hash(makeInput())
        let variations = [
            makeGoal(id: "different-record"),
            makeGoal(namespaceID: FamilyShareNamespaceID(ownerID: "other-owner", shareID: "other-share")),
            makeGoal(ownerID: "other-owner"),
            makeGoal(ownerDisplayName: "Other Owner"),
            makeGoal(goalID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
            makeGoal(goalName: "Renamed goal"),
            makeGoal(goalEmoji: "🚀"),
            makeGoal(currency: "EUR"),
            makeGoal(targetAmount: 2_000),
            makeGoal(currentAmount: 200),
            makeGoal(progressRatio: 0.2),
            makeGoal(deadline: deadline.addingTimeInterval(86_400)),
            makeGoal(goalStatusRawValue: "On Track"),
            makeGoal(forecastStateRawValue: "ahead"),
            makeGoal(freshnessStateRawValue: FamilyShareLifecycleState.stale.rawValue),
            makeGoal(lastUpdatedAt: lastUpdatedAt.addingTimeInterval(60)),
            makeGoal(summaryCopy: "Updated summary"),
            makeGoal(sortIndex: 2)
        ]

        for variation in variations {
            XCTAssertNotEqual(
                baseline,
                hasher.hash(makeInput(goals: [variation])),
                "A visible goal-field change must not be content-hash deduplicated."
            )
        }
    }

    func testHashChangesWhenParticipantLifecycleOrRootCountsChange() {
        let participant = makeParticipant(id: "p1", displayName: "Alex", state: .active)
        let baseline = hasher.hash(
            makeInput(
                participants: [participant],
                participantCount: 1,
                pendingParticipantCount: 0,
                revokedParticipantCount: 0
            )
        )

        let pendingParticipant = makeParticipant(id: "p1", displayName: "Alex", state: .pending)
        XCTAssertNotEqual(
            baseline,
            hasher.hash(
                makeInput(
                    participants: [pendingParticipant],
                    participantCount: 1,
                    pendingParticipantCount: 0,
                    revokedParticipantCount: 0
                )
            ),
            "A participant state change with the same ID must not be deduplicated."
        )
        XCTAssertNotEqual(
            baseline,
            hasher.hash(
                makeInput(
                    participants: [participant],
                    participantCount: 1,
                    pendingParticipantCount: 1,
                    revokedParticipantCount: 0
                )
            ),
            "Published participant counts are invitee-visible state."
        )
    }

    func testHashChangesWhenInviteeVisibleRootOrOwnerSectionStateChanges() {
        let baseline = hasher.hash(makeInput())

        XCTAssertNotEqual(
            baseline,
            hasher.hash(makeInput(summaryCopy: "Updated root summary"))
        )
        XCTAssertNotEqual(
            baseline,
            hasher.hash(
                makeInput(
                    ownerSections: [
                        makeOwnerSection(inlineChipCopy: "Updated owner label")
                    ]
                )
            )
        )
    }

    private func makeInput(
        goals: [FamilyShareProjectedGoalPayload]? = nil,
        ownerSections: [FamilyShareOwnerSectionPayload]? = nil,
        participants: [FamilyShareParticipantSnapshot] = [],
        participantCount: Int = 0,
        pendingParticipantCount: Int = 0,
        revokedParticipantCount: Int = 0,
        summaryCopy: String = "Read-only shared goals."
    ) -> FamilyShareContentHashInput {
        FamilyShareContentHashInput(
            namespaceID: namespaceID,
            ownerDisplayName: "Test Owner",
            freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
            lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
            summaryTitle: "Shared with You",
            summaryCopy: summaryCopy,
            participantCount: participantCount,
            pendingParticipantCount: pendingParticipantCount,
            revokedParticipantCount: revokedParticipantCount,
            goals: goals ?? [makeGoal()],
            ownerSections: ownerSections ?? [makeOwnerSection()],
            participants: participants,
            rateSnapshotTimestamp: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeGoal(
        id: String? = nil,
        namespaceID: FamilyShareNamespaceID? = nil,
        ownerID: String = "owner",
        ownerDisplayName: String = "Test Owner",
        goalID: UUID? = nil,
        goalName: String = "Goal",
        goalEmoji: String? = "🎯",
        currency: String = "USD",
        targetAmount: Decimal = 1_000,
        currentAmount: Decimal = 100,
        progressRatio: Double = 0.1,
        deadline: Date? = nil,
        goalStatusRawValue: String = "Just Started",
        forecastStateRawValue: String? = nil,
        freshnessStateRawValue: String = FamilyShareLifecycleState.active.rawValue,
        lastUpdatedAt: Date? = nil,
        summaryCopy: String = "USD 100 of USD 1,000",
        sortIndex: Int = 0
    ) -> FamilyShareProjectedGoalPayload {
        let resolvedNamespaceID = namespaceID ?? self.namespaceID
        let resolvedGoalID = goalID ?? self.goalID
        return FamilyShareProjectedGoalPayload(
            id: id ?? "\(resolvedNamespaceID.namespaceKey)|\(resolvedGoalID.uuidString)",
            namespaceID: resolvedNamespaceID,
            ownerID: ownerID,
            ownerDisplayName: ownerDisplayName,
            goalID: resolvedGoalID.uuidString,
            goalName: goalName,
            goalEmoji: goalEmoji,
            currency: currency,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            progressRatio: progressRatio,
            deadline: deadline ?? self.deadline,
            goalStatusRawValue: goalStatusRawValue,
            forecastStateRawValue: forecastStateRawValue,
            freshnessStateRawValue: freshnessStateRawValue,
            lastUpdatedAt: lastUpdatedAt ?? self.lastUpdatedAt,
            summaryCopy: summaryCopy,
            sortIndex: sortIndex
        )
    }

    private func makeOwnerSection(
        inlineChipCopy: String = "Test Owner"
    ) -> FamilyShareOwnerSectionPayload {
        FamilyShareOwnerSectionPayload(
            id: "\(namespaceID.namespaceKey)|test-owner|0",
            namespaceID: namespaceID,
            ownerID: namespaceID.ownerID,
            ownerDisplayName: "Test Owner",
            goalCount: 1,
            freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
            sortIndex: 0,
            inlineChipCopy: inlineChipCopy
        )
    }

    private func makeParticipant(
        id: String,
        displayName: String,
        state: FamilyShareParticipantLifecycleState = .active
    ) -> FamilyShareParticipantSnapshot {
        FamilyShareParticipantSnapshot(
            id: id,
            displayName: displayName,
            emailOrAlias: "\(id)@example.com",
            state: state,
            lastUpdatedAt: Date(timeIntervalSince1970: 900),
            isCurrentUser: false
        )
    }
}
