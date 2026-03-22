import SwiftUI

/// Full-screen error state — blocking, requires action.
///
/// Use when no content can be displayed and the user must take action
/// (retry, change settings, etc.) to proceed.
struct ErrorStateView: View {
    let error: UserFacingError
    let onRetry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: iconName)
                .foregroundStyle(iconColor)
        } description: {
            VStack(spacing: 8) {
                Text(error.message)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            if error.isRetryable, let onRetry {
                if isRetrying {
                    ProgressView("Retrying...")
                        .controlSize(.small)
                } else {
                    Button("Try Again") {
                        isRetrying = true
                        Task {
                            await onRetry()
                            isRetrying = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var iconName: String {
        switch error.category {
        case .network: return "wifi.slash"
        case .apiKey: return "key.slash"
        case .dataCorruption: return "exclamationmark.triangle.fill"
        case .unknown: return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch error.category {
        case .network: return .orange
        case .apiKey, .dataCorruption: return .red
        case .unknown: return .orange
        }
    }
}
