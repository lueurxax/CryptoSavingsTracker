//
//  ContributionEntryView.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Allows users to record contributions toward goals during execution tracking
//

import SwiftUI
import SwiftData

struct ContributionEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: Goal
    let executionRecord: MonthlyExecutionRecord
    let plannedAmount: Double
    let alreadyContributed: Double

    @State private var amount = ""
    @State private var comment = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private var contributionService: ContributionService {
        DIContainer.shared.makeContributionService(modelContext: modelContext)
    }

    private var remainingAmount: Double {
        max(0, plannedAmount - alreadyContributed)
    }

    private var isValidInput: Bool {
        guard let amountValue = Double(amount), amountValue > 0 else {
            return false
        }
        return true
    }

    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            Text("Add Contribution")
                .font(.title2)
                .padding()

            Form {
                Section(header: Text("Contribution Details")) {
                    HStack {
                        Text("Goal:")
                        Spacer()
                        Text(goal.name)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Planned for this month:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: plannedAmount, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Already contributed:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: alreadyContributed, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Remaining:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: remainingAmount, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(remainingAmount > 0 ? .orange : .green)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 4)

                    Divider()

                    TextField("Contribution Amount", text: $amount)
                        .padding(.vertical, 4)

                    TextField("Comment (optional)", text: $comment)
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 4)

                Section(footer: Text("Enter the amount you're contributing toward this goal. This will be tracked as part of the monthly execution record.")) {
                    EmptyView()
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)

            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveContribution()
                }
                .disabled(!isValidInput)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 350)
#else
        NavigationView {
            Form {
                Section(header: Text("Contribution Details")) {
                    HStack {
                        Text("Goal:")
                        Spacer()
                        Text(goal.name)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Planned for this month:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: plannedAmount, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Already contributed:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: alreadyContributed, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Remaining:")
                        Spacer()
                        Text(CurrencyFormatter.format(amount: remainingAmount, currency: goal.currency, maximumFractionDigits: 2))
                            .foregroundColor(remainingAmount > 0 ? .orange : .green)
                            .fontWeight(.medium)
                    }
                }

                Section(header: Text("Enter Contribution")) {
                    TextField("Contribution Amount", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Comment (optional)", text: $comment)
                }

                Section(footer: Text("Enter the amount you're contributing toward this goal. This will be tracked as part of the monthly execution record.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Add Contribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContribution()
                    }
                    .disabled(!isValidInput)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
#endif
    }

    // MARK: - Actions

    private func saveContribution() {
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            showError = true
            return
        }

        do {
            // Find the asset for this goal (use first allocated asset, or ask user to select if multiple)
            guard let firstAllocation = goal.allocations.first,
                  let asset = firstAllocation.asset else {
                errorMessage = "This goal has no allocated assets. Please allocate an asset to this goal first."
                showError = true
                return
            }

            // Record the contribution
            // For execution tracking, assetAmount = amount (1:1 ratio since user enters goal currency)
            let contribution = try contributionService.recordDeposit(
                amount: amountValue,
                assetAmount: amountValue, // Simplified - assumes 1:1 ratio
                to: goal,
                from: asset,
                exchangeRate: 1.0, // Simplified for now
                exchangeRateProvider: "Execution Tracking",
                notes: comment.isEmpty ? nil : comment
            )

            // Link to execution record
            try contributionService.linkToExecutionRecord(contribution, recordId: executionRecord.id)
            contribution.monthLabel = executionRecord.monthLabel

            // Notify observers
            NotificationCenter.default.post(
                name: .goalUpdated,
                object: goal
            )

            dismiss()
        } catch {
            errorMessage = "Failed to save contribution: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Preview
// Preview temporarily removed due to build issues
// Will be added back after testing
