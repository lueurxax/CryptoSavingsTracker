//
//  AssetRowView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData

struct AssetRowView: View {
    @Environment(\.modelContext) private var modelContext
    let asset: Asset
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    
    @Query private var allTransactions: [Transaction]
    @State private var showingAddTransaction = false
    
    private var assetTransactions: [Transaction] {
        allTransactions.filter { $0.asset.id == asset.id }.sorted(by: { $0.date > $1.date })
    }
    
    private var currentAmount: Double {
        assetTransactions.reduce(0) { $0 + $1.amount }
    }
    
    init(asset: Asset, isExpanded: Bool, onToggleExpanded: @escaping () -> Void) {
        self.asset = asset
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        let assetId = asset.id
        self._allTransactions = Query(filter: #Predicate<Transaction> { transaction in
            transaction.asset.id == assetId
        }, sort: \Transaction.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggleExpanded) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(asset.currency)
                                .font(.headline)
                            Spacer()
                            Text("\(currentAmount, specifier: "%.8f") \(asset.currency)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if assetTransactions.isEmpty {
                        Text("No transactions yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    } else {
                        ForEach(assetTransactions) { transaction in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(transaction.amount, specifier: "%.8f") \(asset.currency)")
                                        .font(.caption)
                                    Text(transaction.date, format: .dateTime.day().month().year())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.leading)
                        }
                        .animation(.default, value: assetTransactions.count)
                    }
                    
                    Button(action: {
                        showingAddTransaction = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Transaction")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.leading)
                }
            }
        }
#if os(macOS)
        .popover(isPresented: $showingAddTransaction) {
            AddTransactionView(asset: asset)
                .frame(minWidth: 350, minHeight: 250)
        }
#else
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(asset: asset)
        }
#endif
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    let asset = Asset(currency: "BTC", goal: goal)
    let transaction = Transaction(amount: 0.005, asset: asset)
    
    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    container.mainContext.insert(transaction)
    
    return List {
        AssetRowView(asset: asset, isExpanded: true) {
            // Toggle action
        }
    }
    .modelContainer(container)
}