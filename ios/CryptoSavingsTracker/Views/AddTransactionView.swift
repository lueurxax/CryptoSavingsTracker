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
    private let transactionServiceFactory: @MainActor (ModelContext) -> TransactionMutationServiceProtocol
    
    @State private var amount = ""
    @State private var comment = ""
    @State private var transactionDate = Date()
    @State private var accessErrorMessage: String?
    @State private var saveError: UserFacingError?

    init(
        asset: Asset,
        prefillAmount: Double? = nil,
        autoAllocateGoalId: UUID? = nil,
        transactionServiceFactory: @escaping @MainActor (ModelContext) -> TransactionMutationServiceProtocol = {
            DIContainer.shared.makeTransactionMutationService(modelContext: $0)
        }
    ) {
        self.asset = asset
        self.autoAllocateGoalId = autoAllocateGoalId
        self.transactionServiceFactory = transactionServiceFactory
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
                        Section {
                            HStack {
                                Text("Asset:")
                                Spacer()
                                Text(asset.currency)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                                    .accessibilityIdentifier("transactionAssetCurrencyLabel")
                            }
                            .padding(.vertical, 4)

                            TextField("Deposit Amount", text: $amount)
                                .padding(.vertical, 4)

                            TextField("Comment (optional)", text: $comment)
                                .padding(.vertical, 4)

                            DatePicker(
                                "Date",
                                selection: $transactionDate,
                                displayedComponents: [.date]
                            )
                            .padding(.vertical, 4)
                        } header: {
                            Text("Transaction Details")
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
                        Section {
                            HStack {
                                Text("Asset:")
                                Spacer()
                                Text(asset.currency)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                                    .accessibilityIdentifier("transactionAssetCurrencyLabel")
                            }
                            .padding(.vertical, 4)

                            TextField("Deposit Amount", text: $amount)
                                .accessibilityIdentifier("transactionAmountField")
                                .keyboardType(.decimalPad)
                                .padding(.vertical, 4)

                            TextField("Comment (optional)", text: $comment)
                                .accessibilityIdentifier("transactionCommentField")
                                .padding(.vertical, 4)

                            DatePicker(
                                "Date",
                                selection: $transactionDate,
                                displayedComponents: [.date]
                            )
                            .accessibilityIdentifier("transactionDatePicker")
                            .padding(.vertical, 4)
                        } header: {
                            Text("Transaction Details")
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
        .alert(
            "Transaction Not Saved",
            isPresented: Binding(
                get: { saveError != nil },
                set: { isPresented in
                    if !isPresented {
                        saveError = nil
                    }
                }
            ),
            presenting: saveError
        ) { _ in
            Button("Retry") {
                Task { await saveTransaction() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text([
                error.message,
                error.recoverySuggestion
            ].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }
    
    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }
    
    private func saveTransaction() async {
        let result = AddTransactionSaveCoordinator.save(
            asset: asset,
            amountText: amount,
            date: transactionDate,
            comment: comment,
            autoAllocateGoalId: autoAllocateGoalId,
            service: transactionServiceFactory(modelContext)
        )

        if let error = result.error {
            saveError = error
            return
        }

        if result.shouldDismiss {
            saveError = nil
            dismiss()
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

@MainActor
enum AddTransactionSaveCoordinator {
    struct SaveResult: Equatable {
        let shouldDismiss: Bool
        let error: UserFacingError?
    }

    static func save(
        asset: Asset,
        amountText: String,
        date: Date,
        comment: String,
        autoAllocateGoalId: UUID?,
        service: TransactionMutationServiceProtocol
    ) -> SaveResult {
        guard let depositAmount = Double(amountText), depositAmount > 0 else {
            return SaveResult(shouldDismiss: false, error: nil)
        }

        #if DEBUG
        if UITestFlags.consumeSimulatedTransactionSaveFailureIfNeeded() {
            return SaveResult(
                shouldDismiss: false,
                error: UserFacingError(
                    title: "Transaction Not Saved",
                    message: "Your transaction could not be saved.",
                    recoverySuggestion: "Check that the goal is still writable, then retry.",
                    isRetryable: true,
                    category: .dataCorruption
                )
            )
        }
        #endif

        do {
            _ = try service.createTransaction(
                for: asset,
                amount: depositAmount,
                date: date,
                comment: comment.isEmpty ? nil : comment,
                autoAllocateGoalId: autoAllocateGoalId
            )
            return SaveResult(shouldDismiss: true, error: nil)
        } catch {
            return SaveResult(
                shouldDismiss: false,
                error: UserFacingError(
                    title: "Transaction Not Saved",
                    message: "Your transaction could not be saved.",
                    recoverySuggestion: "Check that the goal is still writable, then retry.",
                    isRetryable: true,
                    category: .dataCorruption
                )
            )
        }
    }
}
