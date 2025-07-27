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
                }
                .padding(.horizontal, 4)
                
                Section(footer: Text("Enter the amount you're depositing for this asset.")) {
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
                }
                .padding(.horizontal, 4)
                
                Section(footer: Text("Enter the amount you're depositing for this asset.")) {
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
        
        let newTransaction = Transaction(amount: depositAmount, asset: asset)
        modelContext.insert(newTransaction)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save transaction: \(error)")
        }
        
        NotificationManager.shared.scheduleNotifications(for: asset.goal)
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