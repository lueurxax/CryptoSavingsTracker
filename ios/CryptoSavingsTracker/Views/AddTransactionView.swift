//
//  AddTransactionView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let asset: Asset
    let autoAllocateGoalId: UUID?

    @State private var amount = ""
    @State private var comment = ""
    @State private var accessErrorMessage: String?
    @State private var saveErrorMessage: String?

    init(asset: Asset, prefillAmount: Double? = nil, autoAllocateGoalId: UUID? = nil) {
        self.asset = asset
        self.autoAllocateGoalId = autoAllocateGoalId
        if let prefillAmount {
            _amount = State(initialValue: Self.formatAmount(prefillAmount))
        }
    }

    var body: some View {
        Group {
            if let accessErrorMessage {
                NavigationStack {
                    ContentUnavailableView(
                        "Read-Only Shared Goal",
                        systemImage: "hand.raised.fill",
                        description: Text(accessErrorMessage)
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                dismiss()
                            }
                        }
                    }
                }
            } else {
#if os(macOS)
                VStack(spacing: 0) {
                    Text("New Transaction")
                        .font(.title2)
                        .padding()

                    Form {
                        Section(header: Text("Transaction Details")) {
                            HStack {
                                Text("Asset:")
                                Spacer()
                                Text(asset.currency)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)

                            TextField("Deposit Amount", text: $amount)
                                .padding(.vertical, 4)

                            TextField("Comment (optional)", text: $comment)
                                .padding(.vertical, 4)
                        }
                        .padding(.horizontal, 4)

                        Section {
                            Text("Enter the amount you're depositing and optionally add a comment for reference.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 4)

                        if let saveErrorMessage {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.accessibleStreak)
                                    Text(saveErrorMessage)
                                        .font(.footnote)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button("Dismiss") { self.saveErrorMessage = nil }
                                        .font(.caption)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .padding(10)
                                .background(AccessibleColors.streakBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.top, 8)

                    Divider()

                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button("Save") {
                            Task { await saveTransaction() }
                        }
                        .disabled(!isValidInput)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding()
                }
                .frame(minWidth: 350, minHeight: 250)
#else
                NavigationStack {
                    Form {
                        Section(header: Text("Transaction Details")) {
                            HStack {
                                Text("Asset:")
                                Spacer()
                                Text(asset.currency)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)

                            TextField("Deposit Amount", text: $amount)
                                .accessibilityIdentifier("transactionAmountField")
                                .keyboardType(.decimalPad)
                                .padding(.vertical, 4)

                            TextField("Comment (optional)", text: $comment)
                                .accessibilityIdentifier("transactionCommentField")
                                .padding(.vertical, 4)
                        }
                        .padding(.horizontal, 4)

                        Section {
                            Text("Enter the amount you're depositing and optionally add a comment for reference.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 4)

                        if let saveErrorMessage {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.accessibleStreak)
                                    Text(saveErrorMessage)
                                        .font(.footnote)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button("Dismiss") { self.saveErrorMessage = nil }
                                        .font(.caption)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .padding(10)
                                .background(AccessibleColors.streakBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.top, 8)
                    .navigationTitle("New Transaction")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") {
                                Task { await saveTransaction() }
                            }
                            .disabled(!isValidInput)
                            .accessibilityIdentifier("saveTransactionButton")
                        }
                    }
                }
#endif
            }
        }
        .onAppear {
            validateWritableContext()
        }
    }

    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }

    private func saveTransaction() async {
        guard let depositAmount = Double(amount) else { return }
        await MainActor.run { saveErrorMessage = nil }

        do {
            _ = try DIContainer.shared.makeTransactionMutationService(modelContext: modelContext).createTransaction(
                for: asset,
                amount: depositAmount,
                comment: comment.isEmpty ? nil : comment,
                autoAllocateGoalId: autoAllocateGoalId
            )
        } catch {
            await MainActor.run {
                saveErrorMessage = error.localizedDescription
            }
            return
        }

        await MainActor.run {
            amount = ""
            comment = ""
        }

        Task {
            // Schedule reminders for all goals this asset is allocated to
            for allocation in (asset.allocations ?? []) {
                if let goal = allocation.goal {
                    await NotificationManager.shared.scheduleReminders(for: goal)
                }
            }
        }
        dismiss()
    }

    private func validateWritableContext() {
        do {
            try DIContainer.shared.familyShareAccessGuard.assertOwnerWritable(asset: asset)
        } catch {
            accessErrorMessage = error.localizedDescription
        }
    }

    private static func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
