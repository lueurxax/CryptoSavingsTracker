import Foundation
import SwiftUI

struct FinishedGoalFundingPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let assetCurrency: String
        let amount: Double
        let settlementTitle: String
        let bestKnownBalance: Double?
        let balanceEvidenceTitle: String?
    }

    let completedAt: Date
    let rows: [Row]

    static func make(snapshot: GoalCompletionSnapshot) -> Self {
        Self(
            completedAt: snapshot.goalCompletedAt,
            rows: snapshot.entries.map { entry in
                Row(
                    id: entry.allocationID,
                    assetCurrency: entry.assetCurrency,
                    amount: entry.amount,
                    settlementTitle: entry.settlement == .keepAsSpent
                        ? "Reserved as spent"
                        : "Balance already decreased",
                    bestKnownBalance: entry.bestKnownBalance,
                    balanceEvidenceTitle: entry.bestKnownBalance == nil
                        ? nil
                        : entry.balanceTiming == .completionTime
                            ? "Best-known balance at completion"
                            : "Best-known balance at review"
                )
            }
        )
    }
}

enum FinishedGoalFundingContent: Equatable {
    case pendingReview
    case snapshot(FinishedGoalFundingPresentation)

    static func make(snapshot: GoalCompletionSnapshot?) -> Self {
        guard let snapshot else {
            return .pendingReview
        }
        return .snapshot(FinishedGoalFundingPresentation.make(snapshot: snapshot))
    }
}

struct FinishedGoalFundingSection: View {
    let content: FinishedGoalFundingContent

    var body: some View {
        switch content {
        case .pendingReview:
            Section("Finished Funding") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Funding history pending review")
                        .font(.headline)
                    Text("Review the relevant asset allocation to confirm how this finished goal was funded.")
                        .font(.subheadline)
                        .foregroundStyle(AccessibleColors.secondaryText)
                }
                .padding(.vertical, 4)
            }
        case .snapshot(let presentation):
            Section("Finished Funding") {
                HStack {
                    Text("Completed")
                    Spacer()
                    Text(presentation.completedAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(AccessibleColors.secondaryText)
                }

                ForEach(presentation.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(row.amount) \(row.assetCurrency)")
                                .font(.body.monospacedDigit())
                            Spacer()
                            Text(row.settlementTitle)
                                .font(.subheadline)
                                .foregroundStyle(AccessibleColors.secondaryText)
                        }

                        if let bestKnownBalance = row.bestKnownBalance,
                           let balanceEvidenceTitle = row.balanceEvidenceTitle {
                            Text("\(balanceEvidenceTitle): \(bestKnownBalance) \(row.assetCurrency)")
                                .font(.footnote)
                                .foregroundStyle(AccessibleColors.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
