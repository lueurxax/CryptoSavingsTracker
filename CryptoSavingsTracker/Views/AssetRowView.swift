//
//  AssetRowView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 04/08/2025.
//

import SwiftUI
import SwiftData

struct AssetRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]
    
    let asset: Asset
    let goal: Goal? // Optional goal context to show allocation for specific goal
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    var onDelete: (() -> Void)? = nil
    
    @State private var isLoadingBalance = false
    @State private var onChainBalance: Double = 0
    @State private var balanceState: BalanceState = .loading
    @State private var lastBalanceUpdate: Date? = nil
    @State private var isLoadingTransactions = false
    @State private var onChainTransactions: [TatumTransaction] = []
    @State private var isRefreshing = false
    @State private var hoveredTransactionId: UUID? = nil
    @State private var showingAddTransaction = false
    @State private var showingAllocationView = false
    @State private var exchangeRates: [String: Double] = [:]
    
    private var safeAssetAddress: String? {
        guard let address = asset.address else { return nil }
        return address.isEmpty ? nil : address
    }
    
    private var safeAssetCurrency: String {
        asset.currency.isEmpty ? "Unknown" : asset.currency
    }
    
    private var safeAssetChainId: String? {
        guard let chainId = asset.chainId else { return nil }
        return chainId.isEmpty ? nil : chainId
    }
    
    private var hasOnChainAddress: Bool {
        safeAssetAddress != nil && safeAssetChainId != nil
    }
    
    private var assetTransactions: [Transaction] {
        allTransactions.filter { $0.asset.id == asset.id }
    }
    
    private var totalBalance: Double {
        onChainBalance + manualBalance
    }
    
    private var manualBalance: Double {
        assetTransactions.reduce(0) { $0 + $1.amount }
    }
    
    private var isSharedAsset: Bool {
        asset.allocations.count > 1
    }
    
    private var currentGoalAllocation: Double {
        // If we have a goal context, find the allocation for this specific goal
        if let goal = goal {
            return asset.allocations.first(where: { $0.goal?.id == goal.id })?.percentage ?? 0
        }
        // Otherwise, if only one allocation exists, use it
        if asset.allocations.count == 1 {
            return asset.allocations.first?.percentage ?? 1.0
        }
        return 1.0
    }
    
    private var allocatedBalance: Double {
        totalBalance * currentGoalAllocation
    }
    
    init(asset: Asset, goal: Goal? = nil, isExpanded: Bool, onToggleExpanded: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.asset = asset
        self.goal = goal
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        self.onDelete = onDelete
        let assetId = asset.id
        self._allTransactions = Query(filter: #Predicate<Transaction> { transaction in
            transaction.asset.id == assetId
        }, sort: \Transaction.date, order: .reverse)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Header
            Button(action: onToggleExpanded) {
                HStack(spacing: 12) {
                    // Currency and address info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(safeAssetCurrency)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if isSharedAsset {
                                Image(systemName: "chart.pie.fill")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                        }
                        
                        if let address = safeAssetAddress {
                            Text("\(String(address.prefix(8)))...\(String(address.suffix(6)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospaced()
                        }
                        
                        if isSharedAsset && goal != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.pie.fill")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("\(Int(currentGoalAllocation * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(allocatedBalance, specifier: "%.4f") \(safeAssetCurrency)")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Balance and refresh
                    HStack(spacing: 8) {
                        if hasOnChainAddress {
                            Button(action: {
                                Task {
                                    await refreshBalances()
                                }
                            }) {
                                Image(systemName: isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                    .foregroundColor(isRefreshing ? .gray : .blue)
                                    .imageScale(.medium)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isRefreshing)
                        }
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            if isLoadingBalance {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                // Show allocated amount if shared and in goal context
                                if isSharedAsset && goal != nil {
                                    Text("\(allocatedBalance, specifier: "%.6f") \(safeAssetCurrency)")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundColor(.purple)
                                    
                                    Text("of \(totalBalance, specifier: "%.4f") total")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(totalBalance, specifier: "%.6f") \(safeAssetCurrency)")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                    
                                    if hasOnChainAddress && manualBalance != 0 {
                                        HStack(spacing: 4) {
                                            Text("Chain: \(onChainBalance, specifier: "%.4f")")
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("Manual: \(manualBalance, specifier: "%.4f")")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Action Buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            showingAddTransaction = true
                        }) {
                            Label("Add Transaction", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            showingAllocationView = true
                        }) {
                            Label("Manage Allocations", systemImage: "chart.pie")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        
                        if hasOnChainAddress {
                            Button(action: {
                                Task {
                                    await fetchOnChainTransactions(
                                        address: safeAssetAddress!,
                                        chainId: safeAssetChainId!,
                                        forceRefresh: true
                                    )
                                }
                            }) {
                                Label("Update Transactions", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                        
                        Spacer()
                        
                        if let onDelete = onDelete {
                            Button(action: onDelete) {
                                Label("Delete Asset", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Divider()
                    
                    // Transactions List
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Transactions")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        if assetTransactions.isEmpty && onChainTransactions.isEmpty {
                            Text("No transactions yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                                .frame(maxWidth: .infinity)
                        } else {
                            // Manual Transactions
                            if !assetTransactions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(assetTransactions.prefix(5)) { transaction in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text("\(transaction.amount >= 0 ? "+" : "")\(transaction.amount, specifier: "%.6f")")
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(transaction.amount >= 0 ? .green : .red)
                                                    
                                                    Text("Manual")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.blue.opacity(0.1))
                                                        .foregroundColor(.blue)
                                                        .cornerRadius(4)
                                                }
                                                
                                                Text(transaction.date, format: .dateTime.day().month().year())
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                
                                                if let comment = transaction.comment, !comment.isEmpty {
                                                    Text(comment)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .italic()
                                                        .lineLimit(1)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                deleteTransaction(transaction)
                                            }) {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundColor(.red.opacity(0.7))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .onHover { hovering in
                                                hoveredTransactionId = hovering ? transaction.id : nil
                                            }
                                            .opacity(hoveredTransactionId == transaction.id ? 1 : 0.5)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.02))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            
                            // On-chain Transactions
                            if !onChainTransactions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("On-chain")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal)
                                        .padding(.top, 4)
                                    
                                    ForEach(onChainTransactions.prefix(3), id: \.hash) { tx in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    let amount = Double(tx.amount ?? "0") ?? 0
                                                    Text("\(amount >= 0 ? "+" : "")\(amount, specifier: "%.6f")")
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundColor(amount >= 0 ? .green : .red)
                                                    
                                                    Text("On-chain")
                                                        .font(.caption2)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.orange.opacity(0.1))
                                                        .foregroundColor(.orange)
                                                        .cornerRadius(4)
                                                }
                                                
                                                Text(tx.date, format: .dateTime.day().month().year())
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .background(Color.gray.opacity(0.02))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
        .task {
            await loadInitialData()
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(asset: asset)
        }
        .sheet(isPresented: $showingAllocationView) {
            AssetSharingView(asset: asset)
        }
    }
    
    private func loadInitialData() async {
        // Load balance
        if hasOnChainAddress {
            await fetchOnChainBalance(
                address: safeAssetAddress!,
                chainId: safeAssetChainId!,
                forceRefresh: false
            )
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        do {
            try modelContext.save()
        } catch {
            // Silent failure - transaction remains visible
        }
    }
    
    @MainActor
    private func refreshBalances() async {
        guard let address = safeAssetAddress, let chainId = safeAssetChainId else { return }
        
        isRefreshing = true
        await fetchOnChainBalance(address: address, chainId: chainId, forceRefresh: true)
        await fetchOnChainTransactions(address: address, chainId: chainId, forceRefresh: true)
        isRefreshing = false
    }
    
    private func fetchOnChainBalance(address: String, chainId: String, forceRefresh: Bool) async {
        isLoadingBalance = true
        
        let balanceService = BalanceService(
            client: TatumClient.shared,
            chainService: ChainService.shared
        )
        
        do {
            let balance = try await balanceService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: forceRefresh
            )
            
            await MainActor.run {
                onChainBalance = balance
                balanceState = .loaded(balance: balance, isCached: false, lastUpdated: Date())
                lastBalanceUpdate = Date()
                isLoadingBalance = false
            }
        } catch {
            await MainActor.run {
                // Silent failure - cached balance will be used
                balanceState = .error(
                    message: error.localizedDescription,
                    cachedBalance: onChainBalance > 0 ? onChainBalance : nil,
                    lastUpdated: lastBalanceUpdate
                )
                isLoadingBalance = false
            }
        }
    }
    
    private func fetchOnChainTransactions(address: String, chainId: String, forceRefresh: Bool) async {
        guard hasOnChainAddress else { return }
        
        isLoadingTransactions = true
        
        let transactionService = TransactionService(
            client: TatumClient.shared,
            chainService: ChainService.shared
        )
        
        do {
            let transactions = try await transactionService.fetchTransactionHistory(
                chainId: chainId,
                address: address,
                currency: asset.currency,
                limit: 10,
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                onChainTransactions = transactions
                isLoadingTransactions = false
            }
        } catch {
            await MainActor.run {
                // Silent failure - empty transaction list
                onChainTransactions = []
                isLoadingTransactions = false
            }
        }
    }
}