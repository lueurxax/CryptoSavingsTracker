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
        assetTransactions
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var isSharedAsset: Bool {
        asset.allocations.count > 1
    }

    /// Allocation amount for this goal (in asset currency).
    private var goalAllocationAmount: Double {
        guard let goal = goal,
              let allocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) else {
            // If no goal context, default to full balance
            return totalBalance
        }
        return allocation.amountValue
    }

    private var goalAllocationPercentage: Double {
        guard totalBalance > 0 else { return 0 }
        return goalAllocationAmount / totalBalance
    }

    private var allocatedBalance: Double {
        if goal != nil {
            return min(goalAllocationAmount, totalBalance)
        }
        return totalBalance
    }

    private var unallocatedAmountForAllocationUI: Double {
        // Prefer the freshest balance we have in this view (on-chain fetch), but fall back to cached model value.
        let bestKnownBalance = max(asset.currentAmount, totalBalance)
        return max(0, bestKnownBalance - asset.totalAllocatedAmount)
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
                        
                        if goal != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.pie.fill")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("\(Int(goalAllocationPercentage * 100))%")
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
                                // Show allocated amount when in a goal context
                                if goal != nil {
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
                // Make the entire card hit-testable (background + padding), not just the visible text.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("assetRow-\(safeAssetCurrency)")
            // Prevent identifier duplication across child nodes in XCTest snapshots.
            .accessibilityElement(children: .combine)
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
            
            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Action Buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Add Transaction Button
                            Button(action: {
                                showingAddTransaction = true
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    Text("Add")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                                .frame(width: 60, height: 50)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .accessibilityIdentifier("addTransactionButton")
                            .buttonStyle(PlainButtonStyle())
                            
                            // Manage Allocations Button
                            Button(action: {
                                showingAllocationView = true
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "chart.pie.fill")
                                        .font(.title3)
                                        .foregroundColor(.purple)
                                    Text("Share")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                                .frame(width: 60, height: 50)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .accessibilityIdentifier("shareAssetButton")
                            .buttonStyle(PlainButtonStyle())

                            if let goal, unallocatedAmountForAllocationUI > 0.0000001 {
                                Button(action: {
                                    allocateAllUnallocated(to: goal)
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.down.right.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.mint)
                                        Text("All")
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(width: 60, height: 50)
                                    .background(Color.mint.opacity(0.12))
                                    .cornerRadius(10)
                                }
                                .accessibilityIdentifier("allocateAllUnallocatedButton")
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if hasOnChainAddress {
                                // Update Transactions Button
                                Button(action: {
                                    Task {
                                        await fetchOnChainTransactions(
                                            address: safeAssetAddress!,
                                            chainId: safeAssetChainId!,
                                            forceRefresh: true
                                        )
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.title3)
                                            .foregroundColor(.orange)
                                        Text("Refresh")
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(width: 60, height: 50)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Spacer()
                            
                            if let onDelete = onDelete {
                                // Delete Button
                                Button(action: onDelete) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "trash.fill")
                                            .font(.title3)
                                            .foregroundColor(.red)
                                        Text("Delete")
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(width: 60, height: 50)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
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
            AssetSharingView(asset: asset, currentGoalId: goal?.id)
        }
    }

    private func allocateAllUnallocated(to goal: Goal) {
        let remaining = unallocatedAmountForAllocationUI
        guard remaining > 0.0000001 else { return }

        let newAmount: Double
        if let existing = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            newAmount = existing.amountValue + remaining
            existing.updateAmount(newAmount)
        } else {
            let allocation = AssetAllocation(asset: asset, goal: goal, amount: remaining)
            modelContext.insert(allocation)
            if !asset.allocations.contains(where: { $0.id == allocation.id }) {
                asset.allocations.append(allocation)
            }
            if !goal.allocations.contains(where: { $0.id == allocation.id }) {
                goal.allocations.append(allocation)
            }
            newAmount = remaining
        }

        modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newAmount, timestamp: Date()))
        try? modelContext.save()

        NotificationCenter.default.post(name: .goalUpdated, object: nil, userInfo: ["assetId": asset.id])
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalIds": asset.allocations.compactMap { $0.goal?.id }
            ]
        )
    }
    
    private func loadInitialData() async {
        // Load balance
        if hasOnChainAddress {
            await fetchOnChainBalance(
                address: safeAssetAddress!,
                chainId: safeAssetChainId!,
                forceRefresh: false
            )
            // Also load recent on-chain transactions so history is available on open
            await fetchOnChainTransactions(
                address: safeAssetAddress!,
                chainId: safeAssetChainId!,
                forceRefresh: false
            )
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
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
        
        let balanceService = DIContainer.shared.balanceService
        
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
        
        let transactionService = DIContainer.shared.transactionService
        
        do {
            let transactions = try await transactionService.fetchTransactionHistory(
                chainId: chainId,
                address: address,
                currency: asset.currency,
                limit: 10,
                forceRefresh: forceRefresh
            )

            // Persist into SwiftData so execution tracking can use timestamps without live bridging.
            let insertedCount = await MainActor.run { () -> Int in
                let importer = OnChainTransactionImportService(modelContext: modelContext)
                return (try? importer.upsert(transactions: transactions, for: asset)) ?? 0
            }
            if insertedCount > 0 {
                NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
                NotificationCenter.default.post(
                    name: .monthlyPlanningAssetUpdated,
                    object: asset,
                    userInfo: [
                        "assetId": asset.id,
                        "goalIds": asset.allocations.compactMap { $0.goal?.id }
                    ]
                )
            }

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
