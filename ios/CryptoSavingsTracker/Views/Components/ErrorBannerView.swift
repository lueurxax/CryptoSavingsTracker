import SwiftUI

/// Inline error banner — non-blocking, dismissible.
///
/// Use for recoverable errors where the user can still see existing content
/// below the banner. Shows error message + optional retry button.
struct ErrorBannerView: View {
    let error: UserFacingError
    let onRetry: (() async -> Void)?
    let onDismiss: (() -> Void)?

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .lineLimit(2)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundStyle(AccessibleColors.tertiaryText)
                }
            }

            Spacer()

            if error.isRetryable, let onRetry {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Retry") {
                        isRetrying = true
                        Task {
                            await onRetry()
                            isRetrying = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(AccessibleColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
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
        case .network: return AccessibleColors.warning
        case .apiKey: return AccessibleColors.error
        case .dataCorruption: return AccessibleColors.error
        case .unknown: return AccessibleColors.warning
        }
    }

    private var backgroundColor: Color {
        switch error.category {
        case .network: return AccessibleColors.warningBackground
        case .apiKey: return AccessibleColors.errorBackground
        case .dataCorruption: return AccessibleColors.errorBackground
        case .unknown: return AccessibleColors.warningBackground
        }
    }
}
