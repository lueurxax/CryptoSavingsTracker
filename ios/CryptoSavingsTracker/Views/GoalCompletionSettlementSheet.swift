import SwiftUI

struct GoalCompletionSettlementSheet: View {
    @Bindable var coordinator: GoalCompletionFlowCoordinator
    let onApply: () -> Void
    let onCancel: () -> Void

    private let planner = GoalCompletionSettlementPlanner()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Confirm how mixed balances changed after this goal was funded. "
                            + "This choice is final."
                    )
                }

                Section("Needs your choice") {
                    ForEach(unresolvedItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(amountDescription(for: item))
                                .font(.headline)
                            Picker(
                                "Settlement",
                                selection: settlementBinding(for: item.id)
                            ) {
                                Text("Choose…")
                                    .tag(Optional<FinishedAllocationSettlement>.none)
                                Text("Balance already decreased")
                                    .tag(Optional(FinishedAllocationSettlement.balanceAlreadyDecreased))
                                Text("Keep as spent")
                                    .tag(Optional(FinishedAllocationSettlement.keepAsSpent))
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("settlementChoice-\(item.id.uuidString)")
                        }
                        .padding(.vertical, 4)
                    }
                }

                if automaticItems.isEmpty == false {
                    Section {
                        ForEach(automaticItems) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(amountDescription(for: item))
                                Spacer()
                                Text(settlementDescription(item.automaticSettlement))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text("Automatic")
                    } footer: {
                        Text("Manual and wallet-only balances are handled automatically.")
                    }
                }

                if releaseSummary.isEmpty == false {
                    Section("Released for new goals") {
                        ForEach(releaseSummary, id: \.currency) { amount in
                            LabeledContent(
                                amount.currency,
                                value: amount.amount.formatted(.number.precision(.fractionLength(0...8)))
                            )
                        }
                    }
                }
            }
            .navigationTitle("Finish Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply)
                        .disabled(coordinator.canApply == false || coordinator.phase == .applying)
                        .accessibilityIdentifier("applyGoalCompletionSettlement")
                }
            }
            .interactiveDismissDisabled(coordinator.phase == .applying)
        }
        .accessibilityIdentifier("goalCompletionSettlementSheet")
    }

    private var unresolvedItems: [GoalCompletionSettlementItem] {
        guard coordinator.plan?.origin == .newCompletion else { return [] }
        return coordinator.plan?.items.filter { $0.automaticSettlement == nil } ?? []
    }

    private var automaticItems: [GoalCompletionSettlementItem] {
        coordinator.plan?.items.filter { $0.automaticSettlement != nil } ?? []
    }

    private var releaseSummary: [GoalCompletionCurrencyAmount] {
        guard coordinator.canApply, let plan = coordinator.plan else { return [] }
        return (try? planner.releaseSummary(
            plan: plan,
            decisions: plan.unresolvedAllocationIDs.compactMap { allocationID in
                coordinator.decisions[allocationID].map {
                    GoalCompletionSettlementDecision(allocationID: allocationID, settlement: $0)
                }
            }
        )) ?? []
    }

    private func settlementBinding(
        for allocationID: UUID
    ) -> Binding<FinishedAllocationSettlement?> {
        Binding(
            get: { coordinator.decisions[allocationID] },
            set: { settlement in
                guard let settlement else { return }
                coordinator.choose(allocationID: allocationID, settlement: settlement)
            }
        )
    }

    private func amountDescription(for item: GoalCompletionSettlementItem) -> String {
        let amount = item.input.amount.formatted(.number.precision(.fractionLength(0...8)))
        return "\(amount) \(item.input.assetCurrency)"
    }

    private func settlementDescription(_ settlement: FinishedAllocationSettlement?) -> String {
        switch settlement {
        case .balanceAlreadyDecreased:
            return "Balance already decreased"
        case .keepAsSpent:
            return "Keep as spent"
        case nil:
            return ""
        }
    }
}
