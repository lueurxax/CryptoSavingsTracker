//
//  AddAssetView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData

struct AddAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coinService = CoinGeckoService.shared
    
    let goal: Goal
    
    @State private var currency = ""
    @State private var showingCurrencyPicker = false
    
    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 0) {
                Text("New Asset")
                    .font(.title2)
                    .padding()
                
                Form {
                    Section(header: Text("Asset Details")) {
                        HStack {
                            Text("Currency:")
                            Spacer()
                            Button {
                                showingCurrencyPicker = true
                            } label: {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 4)
                    
                    Section(footer: Text("This asset will be tracked against the goal's target of \(goal.targetAmount, specifier: "%.2f") \(goal.currency).")) {
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
                        saveAsset()
                    }
                    .disabled(!isValidInput)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
#else
            NavigationView {
                Form {
                    Section(header: Text("Asset Details")) {
                        HStack {
                            Text("Currency:")
                            Spacer()
                            Button {
                                showingCurrencyPicker = true
                            } label: {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 4)
                    
                    Section(footer: Text("This asset will be tracked against the goal's target of \(goal.targetAmount, specifier: "%.2f") \(goal.currency).")) {
                        EmptyView()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 8)
                .navigationTitle("New Asset")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveAsset()
                        }
                        .disabled(!isValidInput)
                    }
                }
            }
#endif
        }
        .task {
            if coinService.coins.isEmpty {
                await coinService.fetchCoins()
            }
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(selectedCurrency: $currency)
        }
    }
    
    private var isValidInput: Bool {
        !currency.isEmpty
    }
    
    private func saveAsset() {
        let newAsset = Asset(currency: currency.uppercased(), goal: goal)
        modelContext.insert(newAsset)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save asset: \(error)")
        }
        
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    container.mainContext.insert(goal)
    
    return AddAssetView(goal: goal)
        .modelContainer(container)
}