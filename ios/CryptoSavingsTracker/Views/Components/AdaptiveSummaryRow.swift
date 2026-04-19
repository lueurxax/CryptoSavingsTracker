import SwiftUI

struct AdaptiveSummaryRow: View {
    static let minimumHorizontalSpacing: CGFloat = 12
    static let compactWidth: CGFloat = 320
    static let compactLabelFraction: CGFloat = 0.5

    let label: String
    let value: String
    var valueLineLimit: Int?
    var valueTruncationMode: Text.TruncationMode = .tail

    private var compactLabelLimit: CGFloat {
        Self.compactWidth * Self.compactLabelFraction
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalRow
            verticalRow
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var horizontalRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.minimumHorizontalSpacing) {
            Text(label)
                .foregroundStyle(AccessibleColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: compactLabelLimit, alignment: .leading)

            Spacer(minLength: Self.minimumHorizontalSpacing)

            valueText
                .multilineTextAlignment(.trailing)
        }
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .foregroundStyle(AccessibleColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            valueText
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(AccessibleColors.secondaryText)
            .lineLimit(valueLineLimit)
            .truncationMode(valueTruncationMode)
            .fixedSize(horizontal: false, vertical: true)
    }
}
