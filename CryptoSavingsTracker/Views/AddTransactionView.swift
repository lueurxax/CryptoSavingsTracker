//
//  AddTransactionView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData

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
                    saveTransaction()
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
                        .keyboardType(.decimalPad)
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
                        saveTransaction()
                    }
                    .disabled(!isValidInput)
                }
            }
        }
#endif
    }
    
    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }
    
    private func saveTransaction() {
        guard let depositAmount = Double(amount) else { return }
        
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
        
        Task {
            await NotificationManager.shared.scheduleReminders(for: asset.goal)
        }
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    let asset = Asset(currency: "BTC", goal: goal)
    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    
    return AddTransactionView(asset: asset)
        .modelContainer(container)
}