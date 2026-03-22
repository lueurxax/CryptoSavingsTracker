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
        await evaluator.start(goalInputs: [input], lastPublished: [goalID: 100], handler: { reason in
            Task {
                await recorder.append(reason)
            }
        })

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "BTC", to: "USD")],
                rateSnapshotTimestamp: Date(),
                rates: [CurrencyPair(from: "BTC", to: "USD"): 10_000]
            )
        )
        await flushAsyncWork()

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
            Task {
                await recorder.append(reason)
            }
        })

        source.emit(
            RateRefreshEvent(
                refreshedPairs: [CurrencyPair(from: "USD", to: "USD")],
                rateSnapshotTimestamp: Date(),
                rates: [:]
            )
        )
        await flushAsyncWork()

        let isEmpty = await recorder.isEmpty()
        XCTAssertTrue(isEmpty)
    }
}
