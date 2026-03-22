import SwiftUI

/// Shows data freshness — when content was last updated.
///
/// Use alongside content that may be stale (cached data, offline mode).
/// Optionally shows a refresh spinner.
struct FreshnessIndicatorView: View {
    let lastUpdated: Date?
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Updating...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let lastUpdated {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Updated \(relativeTime(lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
