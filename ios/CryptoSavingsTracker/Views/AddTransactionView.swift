//
//  AddTransactionView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
import OSLog
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
    @State private var saveError: String?

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
                        } footer: {
                            Text("Enter the amount you're depositing and optionally add a comment for reference.")
                        }
                        .padding(.horizontal, 4)
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
                        } footer: {
                            Text("Enter the amount you're depositing and optionally add a comment for reference.")
                        }
                        .padding(.horizontal, 4)
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
        .alert("Transaction Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }
    
    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }
    
    private static let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "AddTransactionView")

    private func saveTransaction() async {
        guard let depositAmount = Double(amount) else { return }

        Self.logger.debug("Saving transaction: amount=\(depositAmount) asset=\(asset.currency)")

        do {
            _ = try DIContainer.shared.makeTransactionMutationService(modelContext: modelContext).createTransaction(
                for: asset,
                amount: depositAmount,
                comment: comment.isEmpty ? nil : comment,
                autoAllocateGoalId: autoAllocateGoalId
            )
            Self.logger.debug("Transaction saved for asset \(asset.currency)")
            dismiss()
        } catch {
            Self.logger.error("Failed to save transaction: \(error)")
            saveError = error.localizedDescription
        }
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
