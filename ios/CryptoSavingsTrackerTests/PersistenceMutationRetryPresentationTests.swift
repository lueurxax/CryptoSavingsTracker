import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceMutationRetryPresentationTests {
    private enum RetryAction: Equatable {
        case delete
    }

    @Test("A failed retry retains its action and re-presents after alert dismissal")
    func failedRetryRePresentsAndSuccessfulRetryClearsState() async {
        var state = PersistenceMutationRetryPresentationState<RetryAction>()

        let initialResult = state.perform(.delete) {
            throw NSError(
                domain: "PersistenceMutationRetryPresentationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Initial failure"]
            )
        }

        #expect(initialResult == false)
        #expect(state.isPresented)
        #expect(state.action == .delete)
        #expect(state.errorMessage == "Initial failure")

        state.presentationDismissed()
        #expect(state.isPresented == false)
        #expect(state.action == .delete)
        #expect(state.errorMessage == "Initial failure")

        let failedRetryResult = await state.retryAfterDismissal { action in
            #expect(action == .delete)
            throw NSError(
                domain: "PersistenceMutationRetryPresentationTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Retry failure"]
            )
        }

        #expect(failedRetryResult == false)
        #expect(state.isPresented)
        #expect(state.action == .delete)
        #expect(state.errorMessage == "Retry failure")

        let successfulRetryResult = await state.retryAfterDismissal { action in
            #expect(action == .delete)
        }

        #expect(successfulRetryResult)
        #expect(state.isPresented == false)
        #expect(state.action == nil)
        #expect(state.errorMessage == nil)
    }

    @Test("Cancel is the only dismissal path that clears a retry action")
    func cancelClearsRetainedAction() {
        var state = PersistenceMutationRetryPresentationState<RetryAction>()
        _ = state.perform(.delete) {
            throw NSError(domain: "PersistenceMutationRetryPresentationTests", code: 3)
        }

        state.presentationDismissed()
        #expect(state.action == .delete)

        state.cancel()
        #expect(state.isPresented == false)
        #expect(state.action == nil)
        #expect(state.errorMessage == nil)
    }
}
