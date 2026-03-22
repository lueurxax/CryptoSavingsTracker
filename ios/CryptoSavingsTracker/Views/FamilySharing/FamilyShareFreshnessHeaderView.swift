import SwiftUI

/// Per-namespace freshness header for the shared-goals list.
///
/// Displays the primary freshness message, optional secondary note,
/// appropriate tier icon/color, and recovery action.
struct FamilyShareFreshnessHeaderView: View {
    let label: FamilyShareFreshnessLabel
    let namespaceName: String
    let onRetry: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(namespaceName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("sharedGoalsFreshnessNamespaceTitle")

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let icon = tierIcon {
                            Image(systemName: icon)
                                .foregroundStyle(tierColor)
                                .font(.caption)
                        }

                        Text(label.primaryMessage)
                            .font(.subheadline)
                            .foregroundStyle(tierColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sharedGoalsFreshnessPrimaryMessage")
                    }

                    if let secondaryMessage = label.secondaryMessage {
                        Text(secondaryMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sharedGoalsFreshnessSecondaryMessage")
                    }
                }

                Spacer(minLength: 8)

                actionView
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.voiceOverMessage)
        .accessibilityIdentifier("sharedGoalsFreshnessHeader")
        .contentTransition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: label.tier)
    }

    @ViewBuilder
    private var actionView: some View {
        if let actionLabel = recoveryActionLabel {
            if label.substate == .checking {
                ProgressView()
                    .controlSize(.small)
            } else if label.substate == .cooldown {
                Button(actionLabel) { onRetry?() }
                    .font(.caption)
                    .disabled(true)
                    .foregroundStyle(.secondary)
            } else {
                Button(actionLabel) { onRetry?() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Tier Visuals

    private var tierIcon: String? {
        // Suppress icons for active/recentlyStale in multi-namespace compactness
        switch label.tier {
        case .active:
            return nil
        case .recentlyStale:
            return "clock"
        case .stale:
            return "exclamationmark.triangle"
        case .materiallyOutdated:
            return "exclamationmark.triangle.fill"
        case .temporarilyUnavailable:
            return "wifi.slash"
        case .removedOrNoLongerShared:
            return "person.crop.circle.badge.minus"
        }
    }

    private var tierColor: Color {
        switch label.tier {
        case .active:
            return .secondary
        case .recentlyStale:
            return .secondary
        case .stale:
            return .orange
        case .materiallyOutdated:
            return .red
        case .temporarilyUnavailable:
            return .red
        case .removedOrNoLongerShared:
            return .secondary
        }
    }

    private var recoveryActionLabel: String? {
        switch label.substate {
        case .checking:
            return nil  // Show spinner instead
        case .refreshFailed:
            return "Try Again"
        case .cooldown:
            return "Try Again"
        case .checkedNoNewData:
            return nil  // No retry meaningful
        default:
            break
        }

        switch label.tier {
        case .stale, .materiallyOutdated:
            return "Retry Refresh"
        case .temporarilyUnavailable:
            return "Retry"
        case .removedOrNoLongerShared:
            return "Remove"
        default:
            return nil
        }
    }
}
