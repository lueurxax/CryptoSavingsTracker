//
//  FamilySharingComponents.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct FamilySharingCard<Content: View>: View {
    let title: String?
    let systemImage: String?
    let tint: Color
    let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String? = nil,
        systemImage: String? = nil,
        tint: Color = AccessibleColors.primaryInteractive,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(.secondarySystemBackground))
                        : VisualComponentTokens.dashboardCardPrimaryFill
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .stroke(VisualComponentTokens.dashboardCardStroke, lineWidth: 1)
        )
    }
}

struct FamilySharingBadge: View {
    let text: String
    let systemImage: String
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label {
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(reduceTransparency ? Color(.secondarySystemBackground) : tint.opacity(0.10))
        .foregroundStyle(tint)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}

struct FamilySharingStateBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(reduceTransparency ? Color(.secondarySystemBackground) : tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct FamilySharingSectionHeader: View {
    let title: String
    let subtitle: String?
    let tint: Color
    var showsAccentIndicator: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsAccentIndicator {
                    Rectangle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 42, height: 4)
                        .clipShape(Capsule())
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

enum FamilyShareIdentityDisplay {
    private static let blockedOwnerLabels: Set<String> = [
        "iphone",
        "this iphone",
        "ipad",
        "this ipad",
        "ipod",
        "this ipod",
        "unknown",
        "unknown device",
        "device"
    ]

    static func ownerDisplayName(for rawDisplayName: String) -> String {
        let normalized = rawDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()
        guard normalized.isEmpty == false else {
            return "family member"
        }
        if blockedOwnerLabels.contains(lowered) || lowered.contains("iphone") || lowered.contains("ipad") || lowered.contains("ipod") {
            return "family member"
        }
        return normalized
    }

    static func sharedByLine(for rawDisplayName: String) -> String {
        "Shared by \(ownerDisplayName(for: rawDisplayName))"
    }
}

struct FamilyShareMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(reduceTransparency ? Color(.secondarySystemBackground) : tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FamilySharingStatusChip: View {
    enum Mode {
        case full
        case iconOnly
    }

    let text: String
    let systemImage: String
    let tint: Color
    var mode: Mode = .full
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch mode {
            case .full:
                Label(text, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            case .iconOnly:
                Image(systemName: systemImage)
                    .accessibilityLabel(Text(text))
            }
        }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, mode == .full ? 10 : 8)
            .padding(.vertical, 6)
            .background(reduceTransparency ? Color(.secondarySystemBackground) : tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }
}
