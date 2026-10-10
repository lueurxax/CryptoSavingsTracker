import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareRateDriftEvaluatorTests: XCTestCase {
    private actor DirtyReasonRecorder {
        private var reasons: [FamilyShareProjectionDirtyReason] = []

        func append(_ reason: FamilyShareProjectionDirtyReason) {
            reasons.append(reason)
        }

        func first() -> FamilyShareProjectionDirtyReason? {
            reasons.first
        }

        func isEmpty() -> Bool {
            reasons.isEmpty
        }
    }

    private final class TestRateRefreshSource: FamilyShareRateRefreshSource, @unchecked Sendable {
        private var continuation: AsyncStream<RateRefreshEvent>.Continuation?
        let ratesDidRefresh: AsyncStream<RateRefreshEvent>

        init() {
            var continuation: AsyncStream<RateRefreshEvent>.Continuation?
            self.ratesDidRefresh = AsyncStream { streamContinuation in
                continuation = streamContinuation
            }
            self.continuation = continuation
        }

        func emit(_ event: RateRefreshEvent) {
            continuation?.yield(event)
        }
    }

    private func flushAsyncWork(iterations: Int = 20) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    func testMaterialDriftEmitsDirtyEvent() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )

        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 1_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: Decimal(string: "0.05")!)
            ]
        )

        let recorder = DirtyReasonRecorder()
        let dirtyEventReceived = expectation(description: "material rate drift recorded")
        await evaluator.start(goalInputs: [input], lastPublished: [goalID: 100], handler: { reason in
            Task {
                await recorder.append(reason)
                dirtyEventReceived.fulfill()
            }
        })

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD").canonicalKey: 10_000]
            )
        )
        await fulfillment(of: [dirtyEventReceived], timeout: 1)
        await evaluator.teardown()

        guard case .rateDrift(let goalIDs)? = await recorder.first() else {
            return XCTFail("Expected a rate-drift dirty event")
        }
        XCTAssertEqual(goalIDs, [goalID])
    }

    func testBelowThresholdDriftDoesNotEmitDirtyEvent() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )

        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 1_000,
            allocations: [
                AllocationInput(assetCurrency: "USD", allocatedAmount: 400)
            ]
        )

        let recorder = DirtyReasonRecorder()
        await evaluator.start(goalInputs: [input], lastPublished: [goalID: 400], handler: { reason in
            Task { await recorder.append(reason) }
        })

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "USD", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [:]
            )
        )
        await flushAsyncWork()
        await evaluator.teardown()

        let isEmpty = await recorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    func testIncompleteRateSnapshotDoesNotEmitFalseDrift() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 1_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1)
            ]
        )
        let recorder = DirtyReasonRecorder()
        await evaluator.start(goalInputs: [input], lastPublished: [goalID: 400], handler: { reason in
            Task { await recorder.append(reason) }
        })

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "ETH", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "ETH", to: "USD").canonicalKey: 2_000]
            )
        )
        await flushAsyncWork()

        let isEmpty = await recorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    func testPartialRefreshMergesWithPreviouslyObservedRatesBeforeEvaluatingDrift() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 10_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1),
                AllocationInput(assetCurrency: "ETH", allocatedAmount: 1)
            ]
        )
        let recorder = DirtyReasonRecorder()
        let dirtyEventExpectation = expectation(
            description: "Cumulative rate snapshot emits material drift"
        )
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 12_000],
            handler: { reason in
                Task {
                    await recorder.append(reason)
                    dirtyEventExpectation.fulfill()
                }
            }
        )

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "ETH", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "ETH", to: "USD").canonicalKey: 2_000]
            )
        )
        await flushAsyncWork()
        let isEmptyAfterPartialSnapshot = await recorder.isEmpty()
        XCTAssertTrue(isEmptyAfterPartialSnapshot)

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD").canonicalKey: 11_000]
            )
        )
        await fulfillment(of: [dirtyEventExpectation], timeout: 1)

        guard case .rateDrift(let goalIDs)? = await recorder.first() else {
            return XCTFail("Expected cumulative rates to produce a material drift event")
        }
        XCTAssertEqual(goalIDs, [goalID])
    }

    func testProjectionSnapshotSeedsRatesForLaterPartialRefresh() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 10_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1),
                AllocationInput(assetCurrency: "ETH", allocatedAmount: 1)
            ]
        )
        let recorder = DirtyReasonRecorder()
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 12_000],
            handler: { reason in
                Task { await recorder.append(reason) }
            }
        )
        await evaluator.updateTrackedGoals(
            [input],
            lastPublished: [goalID: 12_000],
            rateSnapshot: RateSnapshot(
                rates: [
                    CurrencyPair(from: "BTC", to: "USD").canonicalKey: 10_000,
                    CurrencyPair(from: "ETH", to: "USD").canonicalKey: 2_000
                ],
                timestamp: Date()
            )
        )

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD").canonicalKey: 11_000]
            )
        )
        for _ in 0..<50 {
            if await recorder.first() != nil {
                break
            }
            await flushAsyncWork(iterations: 2)
        }

        guard case .rateDrift(let goalIDs)? = await recorder.first() else {
            return XCTFail("Expected the seeded projection rates to complete the partial refresh")
        }
        XCTAssertEqual(goalIDs, [goalID])
    }

    func testMergedUsdMaterialityRatePreventsFalseDriftOnPartialEvent() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "EUR",
            targetAmount: 100,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1)
            ]
        )
        let recorder = DirtyReasonRecorder()
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 100],
            handler: { reason in
                Task { await recorder.append(reason) }
            }
        )

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "USD", to: "EUR").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "USD", to: "EUR").canonicalKey: 2]
            )
        )
        await flushAsyncWork()
        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "EUR").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "EUR").canonicalKey: 106]
            )
        )
        await flushAsyncWork()

        let isEmpty = await recorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    func testRemovingAllTrackedGoalsClearsRatesBeforeRetracking() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 10_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1),
                AllocationInput(assetCurrency: "ETH", allocatedAmount: 1)
            ]
        )
        let recorder = DirtyReasonRecorder()
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 12_000],
            initialRateSnapshot: RateSnapshot(
                rates: [
                    CurrencyPair(from: "BTC", to: "USD").canonicalKey: 10_000,
                    CurrencyPair(from: "ETH", to: "USD").canonicalKey: 2_000
                ],
                timestamp: Date()
            ),
            handler: { reason in
                Task { await recorder.append(reason) }
            }
        )
        await evaluator.updateTrackedGoals([], lastPublished: [:])
        await evaluator.updateTrackedGoals([input], lastPublished: [goalID: 12_000])

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD").canonicalKey: 11_000]
            )
        )
        await flushAsyncWork()

        let isEmpty = await recorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    func testTeardownClearsRatesBeforeRestart() async {
        let source = TestRateRefreshSource()
        let goalID = UUID()
        let evaluator = FamilyShareRateDriftEvaluator(
            rateRefreshSource: source,
            rollout: .shared
        )
        let input = GoalProgressInput(
            goalID: goalID,
            currency: "USD",
            targetAmount: 10_000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: 1),
                AllocationInput(assetCurrency: "ETH", allocatedAmount: 1)
            ]
        )
        let firstRecorder = DirtyReasonRecorder()
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 12_000],
            initialRateSnapshot: RateSnapshot(
                rates: [
                    CurrencyPair(from: "BTC", to: "USD").canonicalKey: 10_000,
                    CurrencyPair(from: "ETH", to: "USD").canonicalKey: 2_000
                ],
                timestamp: Date()
            ),
            handler: { reason in
                Task { await firstRecorder.append(reason) }
            }
        )
        await evaluator.teardown()

        let restartRecorder = DirtyReasonRecorder()
        await evaluator.start(
            goalInputs: [input],
            lastPublished: [goalID: 12_000],
            handler: { reason in
                Task { await restartRecorder.append(reason) }
            }
        )
        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD").canonicalKey],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD").canonicalKey: 11_000]
            )
        )
        await flushAsyncWork()

        let isEmpty = await restartRecorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }
}
