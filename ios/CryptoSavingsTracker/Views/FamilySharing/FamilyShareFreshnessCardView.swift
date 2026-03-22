import SwiftUI

/// Detail-view Freshness card placed below the primary financial summary.
///
/// Shows primary freshness message and two provenance rows with disclosure
/// pattern for exact timestamps at accessibility Dynamic Type sizes.
struct FamilyShareFreshnessCardView: View {
    let label: FamilyShareFreshnessLabel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isLastSharedExpanded: Bool = false
    @State private var isRatesExpanded: Bool = false

    private var isAccessibilitySize: Bool {
        dynamicTypeSize >= .accessibility1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isAccessibilitySize ? 6 : 8) {
            // Card header
            Text("Freshness")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !isAccessibilitySize {
                Divider()
            }

            // Primary freshness message
            HStack(spacing: 6) {
                if let icon = tierIcon {
                    Image(systemName: icon)
                        .foregroundStyle(tierColor)
                }
                Text(label.primaryMessage)
                    .font(.subheadline)
                    .foregroundStyle(tierColor)
            }

            // Provenance rows
            if label.tier != .temporarilyUnavailable && label.tier != .removedOrNoLongerShared {
                provenanceSection
            }

            // Info affordance for stale+ tiers
            if shouldShowInfoAffordance {
                Divider()
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Why is this stale?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("sharedGoalDetailFreshnessCard")
        .accessibilityAddTraits(isAccessibilitySize ? .isButton : [])
        .accessibilityValue(Text(accessibilityExpansionValue))
        .accessibilityHint(Text(accessibilityExpansionHint))
        .accessibilityAction {
            handleCardAccessibilityToggle()
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            handleCardAccessibilityToggle()
        }
        .onAppear {
            isLastSharedExpanded = false
            isRatesExpanded = false
        }
    }

    // MARK: - Provenance

    @ViewBuilder
    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Last shared row
            provenanceRow(
                title: "Last shared",
                date: label.publishedAt,
                isExpanded: $isLastSharedExpanded,
                identifier: "sharedGoalDetailFreshnessLastSharedRow"
            )

            // Rates as of row (collapsed if same as publish time)
            if let rateDate = label.rateSnapshotAt, !isSameTimestamp(rateDate, label.publishedAt) {
                provenanceRow(
                    title: "Rates as of",
                    date: rateDate,
                    isExpanded: $isRatesExpanded,
                    identifier: "sharedGoalDetailFreshnessRatesRow"
                )
            } else {
                Text("Rates as of — (same as shared update)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("sharedGoalDetailFreshnessRatesSameAsShared")
            }
        }
    }

    @ViewBuilder
    private func provenanceRow(title: String, date: Date, isExpanded: Binding<Bool>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isAccessibilitySize {
                Button {
                    toggleExpansion(isExpanded)
                } label: {
                    provenanceRowContent(title: title, date: date, isExpanded: isExpanded.wrappedValue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(Text("\(title), \(relativeTime(date))"))
                .accessibilityHint(Text(isExpanded.wrappedValue ? "Collapse exact timestamp" : "Expand exact timestamp"))
                .accessibilityValue(Text(isExpanded.wrappedValue ? "Expanded" : "Collapsed"))
            } else {
                provenanceRowContent(title: title, date: date, isExpanded: isExpanded.wrappedValue)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(identifier)
            }

            if isAccessibilitySize && isExpanded.wrappedValue {
                Text(exactTimestamp(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("\(identifier)-timestamp")
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func provenanceRowContent(title: String, date: Date, isExpanded: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(provenancePrimaryText(for: date))
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)

            if isAccessibilitySize {
                Image(systemName: isExpanded ? "chevron.down" : chevronCollapsedIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var tierIcon: String? {
        switch label.tier {
        case .active: return nil
        case .recentlyStale: return "clock"
        case .stale: return "exclamationmark.triangle"
        case .materiallyOutdated: return "exclamationmark.triangle.fill"
        case .temporarilyUnavailable: return "wifi.slash"
        case .removedOrNoLongerShared: return "person.crop.circle.badge.minus"
        }
    }

    private var tierColor: Color {
        switch label.tier {
        case .active, .recentlyStale: return .secondary
        case .stale: return .orange
        case .materiallyOutdated, .temporarilyUnavailable: return .red
        case .removedOrNoLongerShared: return .secondary
        }
    }

    private var shouldShowInfoAffordance: Bool {
        switch label.tier {
        case .stale, .materiallyOutdated: return true
        default: return false
        }
    }

    private var accessibilityExpansionValue: String {
        guard isAccessibilitySize, label.tier != .temporarilyUnavailable, label.tier != .removedOrNoLongerShared else {
            return ""
        }
        return isLastSharedExpanded ? "Expanded" : "Collapsed"
    }

    private var accessibilityExpansionHint: String {
        guard isAccessibilitySize, label.tier != .temporarilyUnavailable, label.tier != .removedOrNoLongerShared else {
            return ""
        }
        return isLastSharedExpanded ? "Collapse exact timestamp" : "Expand exact timestamp"
    }

    private var chevronCollapsedIcon: String {
        layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func provenancePrimaryText(for date: Date) -> String {
        let relative = relativeTime(date)
        if isAccessibilitySize {
            return relative
        }
        return "\(relative) (\(exactTimestamp(date)))"
    }

    private func exactTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func isSameTimestamp(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    private func toggleExpansion(_ binding: Binding<Bool>) {
        guard isAccessibilitySize else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            binding.wrappedValue.toggle()
        }
    }

    private func handleCardAccessibilityToggle() {
        guard isAccessibilitySize, label.tier != .temporarilyUnavailable, label.tier != .removedOrNoLongerShared else {
            return
        }
        toggleExpansion($isLastSharedExpanded)
    }
}
