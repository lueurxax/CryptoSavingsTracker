import Foundation
import Combine

/// Protocol for ViewModels that expose error state, loading state, and retry capability.
///
/// All ViewModels that perform async operations should conform to this protocol
/// to ensure consistent error handling across the app.
@MainActor
protocol ErrorAwareViewModel: ObservableObject {
    /// The current view state (idle, loading, loaded, error, degraded).
    var viewState: ViewState { get set }

    /// When data was last successfully loaded. Nil if never loaded.
    var lastSuccessfulLoad: Date? { get }

    /// Retry the last failed operation.
    func retry() async
}

extension ErrorAwareViewModel {
    /// Whether the ViewModel is currently loading.
    var isViewLoading: Bool { viewState.isLoading }

    /// Whether the ViewModel has an error.
    var hasViewError: Bool { viewState.isError }

    /// The current error, if any.
    var currentViewError: UserFacingError? { viewState.errorValue }

    /// Set the view state to error, translating from AppError.
    func setError(_ error: Error) {
        viewState = .error(ErrorTranslator.translate(error))
    }

    /// Set the view state to degraded with a description.
    func setDegraded(_ message: String) {
        viewState = .degraded(message)
    }
}
