//
//  BudgetSummaryCard.swift
//  CryptoSavingsTracker
//
//  Budget summary and entry cards for monthly planning.
//

import SwiftUI

struct BudgetEntryCard: View {
    let onSetBudget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plan by Budget")
                    .font(.headline)
                Text("Set a monthly amount and we'll calculate optimal contributions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onSetBudget) {
                Text("Set Budget")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BudgetSummaryCard: View {
    let budgetAmount: Double
    let budgetCurrency: String
    let feasibility: FeasibilityResult
    let isApplied: Bool
    let currentFocusGoal: String?
    let currentFocusDeadline: Date?
    let onEdit: () -> Void

    private var formattedBudget: String {
        CurrencyFormatter.format(amount: budgetAmount, currency: budgetCurrency, maximumFractionDigits: 2)
    }

    private var statusColor: Color {
        switch feasibility.statusLevel {
        case .achievable: return .green
        case .atRisk: return .orange
        case .critical: return .red
        }
    }

    private func formatFocusDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Budget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedBudget)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Image(systemName: feasibility.statusLevel.iconName)
                    .foregroundColor(statusColor)
                Text(feasibility.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let focus = currentFocusGoal {
                if let deadline = currentFocusDeadline {
                    Text("Next: \(focus) (until \(formatFocusDate(deadline)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Next: \(focus)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !feasibility.isFeasible {
                Text("Minimum required: \(feasibility.formattedMinimum)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isApplied {
                Text("Budget is set but not applied to this month yet.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
