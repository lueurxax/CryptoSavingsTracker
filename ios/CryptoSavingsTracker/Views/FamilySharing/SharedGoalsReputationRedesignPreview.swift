//
//  SharedGoalsReputationRedesignPreview.swift
//  CryptoSavingsTracker
//
//  Preview/evidence gallery for the redesigned invitee-side shared goals contract.
//

import SwiftUI

private struct SharedGoalsReputationRedesignEvidenceView: View {
    let sections: [RedesignEvidenceSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared with You")
                        .font(.largeTitle.bold())
                    Text("Goals are grouped by owner and stay read-only.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(section.ownerName)
                                .font(.headline)
                            if section.isReadOnly {
                                Text("Read-only")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            Spacer(minLength: 0)
                        }

                        if let banner = section.banner {
                            evidenceBanner(banner)
                        }

                        VStack(spacing: 12) {
                            ForEach(section.rows) { row in
                                evidenceRow(row)
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func evidenceBanner(_ banner: RedesignEvidenceBanner) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.systemImage)
                .foregroundStyle(banner.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.headline)
                Text(banner.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(banner.tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func evidenceRow(_ row: RedesignEvidenceRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(row.tint.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(row.emoji)
                        .font(.title3)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let lifecycleTitle = row.lifecycleTitle {
                        Text(lifecycleTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.tint)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(row.ownerLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: row.progress)
                    .tint(row.tint)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(row.currentAmount)
                        Spacer(minLength: 8)
                        Text("of")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(row.targetAmount)
                    }
                    .font(.subheadline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.currentAmount)
                        Text("of \(row.targetAmount)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RedesignEvidenceSection: Identifiable {
    let id = UUID()
    let ownerName: String
    let isReadOnly: Bool
    let banner: RedesignEvidenceBanner?
    let rows: [RedesignEvidenceRow]
}

private struct RedesignEvidenceBanner {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
}

private struct RedesignEvidenceRow: Identifiable {
    let id = UUID()
    let title: String
    let ownerLabel: String
    let lifecycleTitle: String?
    let emoji: String
    let currentAmount: String
    let targetAmount: String
    let progress: Double
    let tint: Color
}

private extension Array where Element == RedesignEvidenceSection {
    static var demo: Self {
        [
            RedesignEvidenceSection(
                ownerName: "Alex",
                isReadOnly: true,
                banner: nil,
                rows: [
                    RedesignEvidenceRow(
                        title: "Piano for daughter",
                        ownerLabel: "Shared by Alex · Read-only",
                        lifecycleTitle: nil,
                        emoji: "🎹",
                        currentAmount: "EUR 0",
                        targetAmount: "EUR 500",
                        progress: 0.0,
                        tint: AccessibleColors.success
                    ),
                    RedesignEvidenceRow(
                        title: "Afina's birthday",
                        ownerLabel: "Shared by Alex · Read-only",
                        lifecycleTitle: "Achieved",
                        emoji: "🎁",
                        currentAmount: "EUR 1000",
                        targetAmount: "EUR 1000",
                        progress: 1.0,
                        tint: AccessibleColors.success
                    ),
                    RedesignEvidenceRow(
                        title: "Robot vacuum",
                        ownerLabel: "Shared by Alex · Read-only",
                        lifecycleTitle: "Expired",
                        emoji: "🤖",
                        currentAmount: "EUR 0",
                        targetAmount: "EUR 900",
                        progress: 0.0,
                        tint: AccessibleColors.warning
                    )
                ]
            ),
            RedesignEvidenceSection(
                ownerName: "Family member",
                isReadOnly: true,
                banner: RedesignEvidenceBanner(
                    title: "Out of date",
                    subtitle: "The shared cache may be out of date.",
                    systemImage: "exclamationmark.circle.fill",
                    tint: AccessibleColors.warning
                ),
                rows: [
                    RedesignEvidenceRow(
                        title: "Mattress",
                        ownerLabel: "Shared by family member · Read-only",
                        lifecycleTitle: nil,
                        emoji: "🛏️",
                        currentAmount: "EUR 0",
                        targetAmount: "EUR 1200",
                        progress: 0.0,
                        tint: AccessibleColors.secondaryInteractive
                    )
                ]
            ),
            RedesignEvidenceSection(
                ownerName: "Jordan",
                isReadOnly: true,
                banner: nil,
                rows: [
                    RedesignEvidenceRow(
                        title: "Vacation Fund",
                        ownerLabel: "Shared by Jordan · Read-only",
                        lifecycleTitle: nil,
                        emoji: "🌴",
                        currentAmount: "EUR 1840",
                        targetAmount: "EUR 3200",
                        progress: 0.575,
                        tint: AccessibleColors.primaryInteractive
                    )
                ]
            )
        ]
    }

    static var longCopyDemo: Self {
        [
            RedesignEvidenceSection(
                ownerName: "Alexandra Petrova-Santoro Household",
                isReadOnly: true,
                banner: nil,
                rows: [
                    RedesignEvidenceRow(
                        title: "Emergency reserve for Afina's first international piano competition travel season",
                        ownerLabel: "Shared by Alexandra Petrova-Santoro Household · Read-only",
                        lifecycleTitle: nil,
                        emoji: "🎼",
                        currentAmount: "EUR 1840",
                        targetAmount: "EUR 4200",
                        progress: 0.438,
                        tint: AccessibleColors.primaryInteractive
                    )
                ]
            ),
            RedesignEvidenceSection(
                ownerName: "Family member 1",
                isReadOnly: true,
                banner: RedesignEvidenceBanner(
                    title: "Out of date",
                    subtitle: "The shared cache may be out of date.",
                    systemImage: "exclamationmark.circle.fill",
                    tint: AccessibleColors.warning
                ),
                rows: [
                    RedesignEvidenceRow(
                        title: "Replacement sofa for the guest room renovation",
                        ownerLabel: "Shared by family member · Read-only",
                        lifecycleTitle: "Expired",
                        emoji: "🛋️",
                        currentAmount: "EUR 250",
                        targetAmount: "EUR 1500",
                        progress: 0.166,
                        tint: AccessibleColors.warning
                    )
                ]
            )
        ]
    }
}

#Preview("Invitee Redesign") {
    SharedGoalsReputationRedesignEvidenceView(sections: .demo)
}

#Preview("Invitee Redesign 320pt") {
    SharedGoalsReputationRedesignEvidenceView(sections: .demo)
        .frame(width: 320)
}

#Preview("Invitee Redesign AX") {
    SharedGoalsReputationRedesignEvidenceView(sections: .demo)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Invitee Redesign Long Copy 320pt") {
    SharedGoalsReputationRedesignEvidenceView(sections: .longCopyDemo)
        .frame(width: 320)
}

#Preview("Invitee Redesign Long Copy AX") {
    SharedGoalsReputationRedesignEvidenceView(sections: .longCopyDemo)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
