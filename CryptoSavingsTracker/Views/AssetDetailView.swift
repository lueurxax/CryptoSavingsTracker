//
//  AssetDetailView.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftUI
import SwiftData

struct AssetDetailView: View {
    let asset: Asset
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @State private var currentBalance: Double = 0
    @State private var isLoadingBalance = false
    @State private var balanceError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                // Balance Section
                balanceSection
                
                // Asset Information
                assetInfoSection
                
                // Recent Transactions
                recentTransactionsSection
                
                // Actions
                actionButtons
            }
            .padding()
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadBalance()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(asset.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(asset.currency)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            if let address = asset.address {
                Text(address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Balance")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if isLoadingBalance {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = balanceError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.6f", currentBalance))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text(asset.currency)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asset Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                InfoRow(label: "Type", value: asset.isOnChain ? "On-Chain" : "Manual")
                InfoRow(label: "Currency", value: asset.currency)
                
                if asset.isOnChain {
                    if let chainId = asset.chainId {
                        InfoRow(label: "Chain", value: chainId)
                    }
                    if let address = asset.address {
                        InfoRow(label: "Address", value: address, truncate: true)
                    }
                } else {
                    InfoRow(label: "Manual Balance", value: String(format: "%.6f", asset.manualBalance))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                
                Spacer()
                
                Button("View All") {
                    coordinator.showTransactionHistory(for: asset)
                }
                .font(.caption)
            }
            
            if asset.transactions.isEmpty {
                Text("No transactions yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(asset.transactions.prefix(3)) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(String(format: "%.6f %@", transaction.amount, asset.currency))
                                    .font(.callout)
                                    .foregroundColor(transaction.amount >= 0 ? .green : .red)
                                
                                Text(transaction.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let comment = transaction.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if transaction != asset.transactions.prefix(3).last {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                coordinator.goalCoordinator.showAddTransaction(to: asset)
            }) {
                Label("Add Transaction", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                coordinator.goalCoordinator.showEditAsset(asset)
            }) {
                Label("Edit Asset", systemImage: "pencil.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func loadBalance() async {
        guard asset.isOnChain,
              let chainId = asset.chainId,
              let address = asset.address else {
            currentBalance = asset.manualBalance
            return
        }
        
        isLoadingBalance = true
        balanceError = nil
        
        do {
            let balance = try await TatumService.shared.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency
            )
            
            await MainActor.run {
                currentBalance = balance
                isLoadingBalance = false
            }
        } catch {
            await MainActor.run {
                balanceError = error.localizedDescription
                currentBalance = asset.manualBalance
                isLoadingBalance = false
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var truncate: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .lineLimit(1)
                .truncationMode(truncate ? .middle : .tail)
                .font(.callout)
        }
    }
}