import SwiftUI

private struct SharedGoalsFreshnessPreviewGallery: View {
    private let now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FamilyShareFreshnessHeaderView(
                    label: FamilyShareFreshnessLabel(
                        publishedAt: now.addingTimeInterval(-8 * 60),
                        rateSnapshotAt: now.addingTimeInterval(-8 * 60),
                        namespaceKey: "preview-active"
                    ),
                    namespaceName: "Alice's Goals",
                    onRetry: nil
                )

                FamilyShareFreshnessHeaderView(
                    label: FamilyShareFreshnessLabel(
                        publishedAt: now.addingTimeInterval(-20 * 60),
                        rateSnapshotAt: now.addingTimeInterval(-7 * 3600),
                        namespaceKey: "preview-stale-rate"
                    ),
                    namespaceName: "Long Household Owner Name",
                    onRetry: nil
                )

                FamilyShareFreshnessHeaderView(
                    label: FamilyShareFreshnessLabel(
                        publishedAt: now.addingTimeInterval(-9 * 3600),
                        rateSnapshotAt: now.addingTimeInterval(-9 * 3600),
                        substate: .checkedNoNewData,
                        lastChecked: now,
                        namespaceKey: "preview-no-new-data"
                    ),
                    namespaceName: "Family member 1",
                    onRetry: nil
                )

                FamilyShareFreshnessCardView(
                    label: FamilyShareFreshnessLabel(
                        publishedAt: now.addingTimeInterval(-27 * 3600),
                        rateSnapshotAt: now.addingTimeInterval(-27 * 3600),
                        namespaceKey: "preview-detail"
                    )
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Shared Goals Freshness") {
    SharedGoalsFreshnessPreviewGallery()
}

#Preview("Shared Goals Freshness AX") {
    SharedGoalsFreshnessPreviewGallery()
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
