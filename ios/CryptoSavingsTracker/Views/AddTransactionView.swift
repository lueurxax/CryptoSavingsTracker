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
    
    @State private var amount = ""
    @State private var comment = ""
    
    var body: some View {
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
                
                Section(footer: Text("Enter the amount you're depositing and optionally add a comment for reference.")) {
                    EmptyView()
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
        NavigationView {
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
                
                Section(footer: Text("Enter the amount you're depositing and optionally add a comment for reference.")) {
                    EmptyView()
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
    
    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }
    
    private func saveTransaction() async {
        guard let depositAmount = Double(amount) else { return }

        let epsilon = 0.0000001
        let preBalance = asset.currentAmount
        let preIsFullyAllocated = asset.isFullyAllocated
        let preWasDedicatedToSingleGoal = asset.allocations.count == 1
        let singleAllocation = asset.allocations.first

        print("💾 Saving new transaction:")
        print("   Amount: \(depositAmount)")
        print("   Asset: \(asset.currency)")
        print("   Comment: \(comment.isEmpty ? "none" : comment)")
        print("   Asset ID: \(asset.id)")
        print("   Current transaction count for asset: \(asset.transactions.count)")
        
        let newTransaction = Transaction(amount: depositAmount, asset: asset, comment: comment.isEmpty ? nil : comment)

        // Explicitly establish the relationship on both sides
        asset.transactions.append(newTransaction)

        modelContext.insert(newTransaction)

        // Auto-allocation rule: if the asset was fully allocated to exactly one goal,
        // keep it fully allocated after the deposit by increasing its allocation target.
        if preIsFullyAllocated, preWasDedicatedToSingleGoal, let allocation = singleAllocation, let goal = allocation.goal {
            let newTarget = max(0, preBalance + depositAmount)
            if abs(newTarget - allocation.amountValue) > epsilon {
                allocation.updateAmount(newTarget)
                modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newTarget, timestamp: newTransaction.date))
            }
        }

        do {
            // SwiftData will automatically trigger UI updates through @Query
            try modelContext.save()
            print("✅ Transaction saved successfully")
            print("   New transaction count for asset: \(asset.transactions.count)")

        } catch {
            print("❌ Failed to save transaction: \(error)")
            // Show user-friendly error message
            // TODO: Add error state display to UI
        }

        // Trigger refresh of goal totals/progress and monthly planning/execution views.
        NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalIds": asset.allocations.compactMap { $0.goal?.id }
            ]
        )
        
        Task {
            // Schedule reminders for all goals this asset is allocated to
            for allocation in asset.allocations {
                if let goal = allocation.goal {
                    await NotificationManager.shared.scheduleReminders(for: goal)
                }
            }
        }
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    let asset = Asset(currency: "BTC")
    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    
    return AddTransactionView(asset: asset)
        .modelContainer(container)
}
