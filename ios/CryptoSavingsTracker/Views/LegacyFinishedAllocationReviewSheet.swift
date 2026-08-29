import SwiftUI

struct LegacyFinishedAllocationReviewSheet: View {
    @Bindable var coordinator: LegacyFinishedAllocationReviewCoordinator
    let goalsByID: [UUID: Goal]
    let onApply: () -> Void
    let onLater: () -> Void

    private let planner = GoalCompletionSettlementPlanner()

    static func settlementChoiceAccessibilityIdentifier(
        goalID: UUID,
        allocationID: UUID
    ) -> String {
        "legacySettlementChoice-\(goalID.uuidString)-\(allocationID.uuidString)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Review every allocation for each finished goal. Nothing changes until all "
                            + "choices are applied together, and the result is final."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = coordinator.errorMessage {
                    Section("Couldn’t Apply Review") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(sortedPlans, id: \.goalID) { plan in
                    Section {
                        Text(goalsByID[plan.goalID]?.name ?? "Finished goal")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(currencyGroups(for: plan)) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.currency)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)

                                ForEach(group.items) { item in
                                    settlementRow(goalID: plan.goalID, item: item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Finished goal")
                    }
                }

                if releaseSummary.isEmpty == false {
                    Section("Available after review") {
                        ForEach(releaseSummary, id: \.currency) { amount in
                            LabeledContent(
                                amount.currency,
                                value: amount.amount.formatted(
                                    .number.precision(.fractionLength(0...8))
                                )
                            )
                        }
                    }
                }
            }
            .navigationTitle("Review Finished Allocations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later", action: onLater)
                        .disabled(coordinator.isApplying)
                        .accessibilityIdentifier("laterLegacyFinishedAllocationReview")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Review", action: onApply)
                        .disabled(coordinator.canApply == false)
                        .accessibilityIdentifier("applyLegacyFinishedAllocationReview")
                }
            }
            .interactiveDismissDisabled(coordinator.isApplying)
        }
        .accessibilityIdentifier("legacyFinishedAllocationReviewSheet")
    }

    private var sortedPlans: [GoalCompletionSettlementPlan] {
        coordinator.plansByGoalID.values.sorted { lhs, rhs in
            let lhsName = goalsByID[lhs.goalID]?.name ?? ""
            let rhsName = goalsByID[rhs.goalID]?.name ?? ""
            if lhsName != rhsName {
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            return lhs.goalID.uuidString < rhs.goalID.uuidString
        }
    }

    @ViewBuilder
    private func settlementRow(
        goalID: UUID,
        item: GoalCompletionSettlementItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.input.amount.formatted(.number.precision(.fractionLength(0...8))))
                .font(.headline)
                .monospacedDigit()

            Text(accountingModeDescription(item.input.accountingMode))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recommendation = item.recommendedSettlement {
                Text("Recommended: \(settlementDescription(recommendation))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(
                "Settlement",
                selection: settlementBinding(goalID: goalID, allocationID: item.id)
            ) {
                Text("Choose…")
                    .tag(Optional<FinishedAllocationSettlement>.none)
                Text("Balance already decreased")
                    .tag(Optional(FinishedAllocationSettlement.balanceAlreadyDecreased))
                Text("Keep as spent")
                    .tag(Optional(FinishedAllocationSettlement.keepAsSpent))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(
                Self.settlementChoiceAccessibilityIdentifier(
                    goalID: goalID,
                    allocationID: item.id
                )
            )
        }
        .padding(.vertical, 4)
    }

    private var releaseSummary: [GoalCompletionCurrencyAmount] {
        guard coordinator.canApply else { return [] }
        var totals: [String: Double] = [:]

        for plan in sortedPlans {
            let decisions = plan.items.compactMap { item in
                coordinator.decisions[
                    LegacyFinishedAllocationDecisionKey(
                        goalID: plan.goalID,
                        allocationID: item.id
                    )
                ].map {
                    GoalCompletionSettlementDecision(allocationID: item.id, settlement: $0)
                }
            }
            guard let summary = try? planner.releaseSummary(plan: plan, decisions: decisions) else {
                return []
            }
            for amount in summary {
                totals[amount.currency, default: 0] += amount.amount
            }
        }

        return totals.keys.sorted().map {
            GoalCompletionCurrencyAmount(currency: $0, amount: totals[$0] ?? 0)
        }
    }

    private func currencyGroups(for plan: GoalCompletionSettlementPlan) -> [CurrencyGroup] {
        let grouped = Dictionary(grouping: plan.items, by: \.input.assetCurrency)
        return grouped.keys.sorted().map {
            CurrencyGroup(currency: $0, items: grouped[$0] ?? [])
        }
    }

    private func settlementBinding(
        goalID: UUID,
        allocationID: UUID
    ) -> Binding<FinishedAllocationSettlement?> {
        let key = LegacyFinishedAllocationDecisionKey(
            goalID: goalID,
            allocationID: allocationID
        )
        return Binding(
            get: { coordinator.decisions[key] },
            set: { settlement in
                guard let settlement else { return }
                coordinator.choose(
                    goalID: goalID,
                    allocationID: allocationID,
                    settlement: settlement
                )
            }
        )
    }

    private func accountingModeDescription(_ mode: AssetBalanceAccountingMode) -> String {
        switch mode {
        case .manual:
            return "Manual balance"
        case .onChain:
            return "Wallet balance"
        case .mixed:
            return "Mixed balance"
        }
    }

    private func settlementDescription(_ settlement: FinishedAllocationSettlement) -> String {
        switch settlement {
        case .balanceAlreadyDecreased:
            return "Balance already decreased"
        case .keepAsSpent:
            return "Keep as spent"
        }
    }

    private struct CurrencyGroup: Identifiable {
        let currency: String
        let items: [GoalCompletionSettlementItem]

        var id: String { currency }
    }
}
