import SwiftUI

/// Tri-state container that switches between loading, content, and error states.
///
/// Usage:
/// ```swift
/// AsyncContentView(state: viewModel.viewState) {
///     // Content when loaded
///     GoalListContent(goals: viewModel.goals)
/// } loading: {
///     ProgressView("Loading goals...")
/// } error: { error in
///     ErrorStateView(error: error, onRetry: { await viewModel.retry() })
/// }
/// ```
struct AsyncContentView<Content: View, Loading: View, ErrorContent: View>: View {
    let state: ViewState
    @ViewBuilder let content: () -> Content
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let error: (UserFacingError) -> ErrorContent

    var body: some View {
        switch state {
        case .idle:
            content()
        case .loading:
            loading()
        case .loaded:
            content()
        case .error(let userError):
            error(userError)
        case .degraded(let message):
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.08))

                content()
            }
        }
    }
}

/// Convenience initializer with default loading view.
extension AsyncContentView where Loading == ProgressView<EmptyView, EmptyView> {
    init(
        state: ViewState,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder error: @escaping (UserFacingError) -> ErrorContent
    ) {
        self.state = state
        self.content = content
        self.loading = { ProgressView() }
        self.error = error
    }
}
