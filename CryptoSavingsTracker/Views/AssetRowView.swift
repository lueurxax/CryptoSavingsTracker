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
    @State private var onChainBalance: Double = 0.0
    @State private var isLoadingBalance = false
    @State private var balanceError: String?
    @State private var onChainTransactions: [TatumTransaction] = []
    @State private var isLoadingTransactions = false
    @State private var lastBalanceUpdate: Date?
    @State private var isRefreshing = false
    @State private var hoveredTransactionId: UUID?
    @State private var exchangeRates: [String: Double] = [:] // Currency to USD rates
    @State private var goalCurrency: String = ""
    
    // Exchange rate service
    private let exchangeRateService = ExchangeRateService.shared
    
    private var assetTransactions: [Transaction] {
        return allTransactions.filter { $0.asset.id == asset.id }.sorted(by: { $0.date > $1.date })
    }
    
    private var shouldShowOnChainTransactions: Bool {
        return safeAssetAddress != nil && safeAssetChainId != nil && !onChainTransactions.isEmpty
    }
    
    private var manualBalance: Double {
        return assetTransactions.reduce(0) { $0 + $1.amount }
    }
    
    private var totalBalance: Double {
        return onChainBalance + manualBalance
    }
    
    private var hasOnChainAddress: Bool {
        return safeAssetAddress != nil && safeAssetChainId != nil && !safeAssetAddress!.isEmpty
    }
    
        // Safe access properties to prevent crashes when asset is deleted
    private var safeAssetCurrency: String {
        return asset.currency
    }
    
    private var safeAssetAddress: String? {
        return asset.address
    }
    
    private var safeAssetChainId: String? {
        return asset.chainId
    }
    
    // Calculate USD equivalent for transaction
    private func usdValue(for transaction: Transaction) -> String? {
        guard let rate = exchangeRates[safeAssetCurrency.uppercased()] else { return nil }
        let usdAmount = transaction.amount * rate
        return String(format: "~$%.2f", abs(usdAmount))
    }
    
    // Calculate impact on goal progress
    private func goalImpact(for transaction: Transaction) -> String? {
        guard !goalCurrency.isEmpty else { return nil }
        
        let goalTotal = asset.goal.targetAmount
        let impactPercent = abs(transaction.amount) / goalTotal * 100
        
        if impactPercent >= 0.1 { // Only show if impact is >= 0.1%
            let direction = transaction.amount >= 0 ? "+" : "-"
            return "\(direction)\(String(format: "%.1f", impactPercent))% of goal"
        }
        return nil
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(safeAssetCurrency)
                                    .font(.headline)
                                
                                if let address = safeAssetAddress, !address.isEmpty {
                                    Text("\(String(address.prefix(8)))...\(String(address.suffix(6)))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .monospaced()
                                }
                                
                                if let chainId = safeAssetChainId, let chain = TatumService.shared.supportedChains.first(where: { $0.id == chainId }) {
                                    Text(chain.name)
                                        .font(.caption2)
                                        .foregroundColor(.accessiblePrimary)
                                }
                            }
                            
                            if let address = safeAssetAddress, !address.isEmpty {
                                Text("On-chain")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AccessibleColors.primaryInteractiveBackground)
                                    .foregroundColor(.accessiblePrimary)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    if hasOnChainAddress {
                                        Button(action: {
                                            Task {
                                                await refreshBalances()
                                            }
                                        }) {
                                            Image(systemName: isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                                .foregroundColor(isRefreshing ? .gray : .blue)
                                                .imageScale(.small)
                                                .frame(minWidth: 44, minHeight: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .disabled(isRefreshing)
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    
                                    if isLoadingBalance && hasOnChainAddress {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    } else {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            // Total balance
                                            Text("\(totalBalance, specifier: "%.8f") \(safeAssetCurrency)")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            
                                            // Breakdown if we have both types
                                            if hasOnChainAddress || manualBalance > 0 {
                                                HStack(spacing: 4) {
                                                    if hasOnChainAddress {
                                                        Text("Chain: \(onChainBalance, specifier: "%.4f")")
                                                            .font(.caption2)
                                                            .foregroundColor(.accessiblePrimary)
                                                    }
                                                    if manualBalance > 0 {
                                                        Text("Manual: \(manualBalance, specifier: "%.4f")")
                                                            .font(.caption2)
                                                            .foregroundColor(.accessibleStreak)
                                                    }
                                                }
                                            }
                                            
                                            // Last updated
                                            if let lastUpdate = lastBalanceUpdate {
                                                Text("Updated: \(lastUpdate, format: .relative(presentation: .numeric))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                        // On-chain transactions section
                    if shouldShowOnChainTransactions {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("On-Chain History")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.accessiblePrimary)
                                if isLoadingTransactions {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }
                                Spacer()
                            }
                            .padding(.leading)
                            
                            ForEach(onChainTransactions.prefix(10)) { transaction in
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(transaction.nativeValue > 0 ? "+\(transaction.nativeValue, specifier: "%.8f")" : "0.00000000")
                                                .font(.caption)
                                                .foregroundColor(transaction.nativeValue > 0 ? .green : .secondary)
                                            Text(safeAssetCurrency)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("(On-chain)")
                                                .font(.caption2)
                                                .foregroundColor(.accessiblePrimary)
                                        }
                                        Text(transaction.date, format: .dateTime.day().month().year())
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.leading)
                            }
                        }
                    }
                    
                        // Manual transactions section
                    if !assetTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Manual Entries")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                            
                            ForEach(assetTransactions) { transaction in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("\(transaction.amount, specifier: "%.8f")")
                                                .font(.caption)
                                                .foregroundColor(transaction.amount >= 0 ? .green : .red)
                                            Text(safeAssetCurrency)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("(Manual)")
                                                .font(.caption2)
                                                .foregroundColor(.accessibleStreak)
                                        }
                                        
                                        HStack(spacing: 8) {
                                            Text(transaction.date, format: .dateTime.day().month().year())
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            // USD value
                                            if let usdVal = usdValue(for: transaction) {
                                                Text(usdVal)
                                                    .font(.caption2)
                                                    .foregroundColor(.accessiblePrimary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.accessiblePrimaryBackground)
                                                    .cornerRadius(4)
                                            }
                                            
                                            // Goal impact
                                            if let impact = goalImpact(for: transaction) {
                                                Text(impact)
                                                    .font(.caption2)
                                                    .foregroundColor(.accessibleSecondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.gray.opacity(0.1))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        
                                        if let comment = transaction.comment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }
                                    Spacer()
                                    
                                    Button(action: {
                                        deleteTransaction(transaction)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(hoveredTransactionId == transaction.id ? .red : .secondary)
                                            .font(.system(size: 14))
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("Delete transaction")
                                    .accessibilityHint("Permanently removes this \(transaction.amount, specifier: "%.8f") \(safeAssetCurrency) transaction")
                                    .onHover { hovering in
                                        hoveredTransactionId = hovering ? transaction.id : nil
                                    }
                                }
                                .padding(8)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                            }
                        }
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
                        .animation(.default, value: assetTransactions.count)
                    }
                    
                        // No transactions message
                    if assetTransactions.isEmpty && !shouldShowOnChainTransactions {
                        VStack(spacing: 8) {
                            EmptyStateView(
                                icon: "arrow.left.arrow.right.circle",
                                title: "No Transactions",
                                description: "Add transactions to track your \(asset.currency) activity"
                            )
                        }
                        .padding(.horizontal)
                        .frame(height: 120)
                    }
                    
                    Button(action: {
                        showingAddTransaction = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Transaction")
                        }
                        .font(.caption)
                        .foregroundColor(.accessiblePrimary)
                    }
                    .padding(.leading)
                }
            }
        }
        .task {
            // Load goal currency
            goalCurrency = asset.goal.currency
            
            // Load exchange rates for USD conversion
            await loadExchangeRates()
            
            // Only fetch if we don't have cached data
            if let address = safeAssetAddress, let chainId = safeAssetChainId, !address.isEmpty {
                // Use cache-aware fetch (won't make API call if cached)
                await fetchOnChainBalance(address: address, chainId: chainId, forceRefresh: false)
                await fetchOnChainTransactions(address: address, chainId: chainId, forceRefresh: false)
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
    
    @MainActor
    private func refreshBalances() async {
        guard let address = safeAssetAddress, let chainId = safeAssetChainId, !address.isEmpty else { return }
        
        isRefreshing = true
        await fetchOnChainBalance(address: address, chainId: chainId, forceRefresh: true)
        await fetchOnChainTransactions(address: address, chainId: chainId, forceRefresh: true)
        isRefreshing = false
    }
    
    @MainActor
    private func fetchOnChainBalance(address: String, chainId: String, forceRefresh: Bool = false) async {
        isLoadingBalance = true
        balanceError = nil
        
        do {
            let balance = try await TatumService.shared.fetchBalance(
                chainId: chainId, 
                address: address, 
                symbol: asset.currency,
                forceRefresh: forceRefresh
            )
            onChainBalance = balance
            lastBalanceUpdate = Date()
        } catch {
            balanceError = error.localizedDescription
            onChainBalance = 0.0
        }
        
        isLoadingBalance = false
    }
    
    @MainActor
    private func fetchOnChainTransactions(address: String, chainId: String, forceRefresh: Bool = false) async {
        isLoadingTransactions = true
        
        do {
            // Fetching on-chain transactions
            let transactions = try await TatumService.shared.fetchTransactionHistory(
                chainId: chainId,
                address: address,
                limit: 20,
                forceRefresh: forceRefresh
            )
            onChainTransactions = transactions
        } catch {
            // Transaction fetch failed
            if let tatumError = error as? TatumError {
                switch tatumError {
                case .notFound:
                    // No transactions found for this address and chain
                    break
                default:
                    // Unhandled Tatum error occurred
                    break
                }
            }
            onChainTransactions = []
        }
        
        isLoadingTransactions = false
    }
    
    // Load exchange rates for USD conversion
    private func loadExchangeRates() async {
        do {
            // Only load if we don't have the rate cached
            if exchangeRates[safeAssetCurrency.uppercased()] == nil {
                let rate = try await exchangeRateService.fetchRate(
                    from: safeAssetCurrency,
                    to: "USD"
                )
                exchangeRates[safeAssetCurrency.uppercased()] = rate
            }
        } catch {
            print("Failed to load exchange rate for \(safeAssetCurrency): \(error)")
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation(.default) {
            print("🗑️ Deleting transaction: \(transaction.amount) \(safeAssetCurrency)")
            print("   Transaction ID: \(transaction.id)")
            print("   Comment: \(transaction.comment ?? "none")")
            
            // Remove from asset's transactions array
            if let index = asset.transactions.firstIndex(where: { $0.id == transaction.id }) {
                asset.transactions.remove(at: index)
            }
            
            // Delete from model context
            modelContext.delete(transaction)
            
            // Save the context
            do {
                try modelContext.save()
                print("✅ Transaction deleted successfully")
                print("   Remaining transaction count: \(asset.transactions.count)")
                
                // SwiftData will automatically update the UI through @Query
                
            } catch {
                print("❌ Failed to delete transaction: \(error)")
            }
        }
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
