//
//  AssetViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class AssetViewModel: ObservableObject {
    @Published var onChainBalance: Double = 0
    @Published var manualBalance: Double = 0
    @Published var totalBalance: Double = 0
    @Published var isLoadingBalance: Bool = false
    @Published var balanceError: String?
    @Published var onChainTransactions: [TatumTransaction] = []
    @Published var isLoadingTransactions: Bool = false
    @Published var lastBalanceUpdate: Date?
    @Published var balanceState: BalanceState = .loading
    @Published var isCachedData: Bool = false
    
    private let asset: Asset
    private let tatumService: TatumServiceProtocol
    private let modelContext: ModelContext?
    
    init(asset: Asset, tatumService: TatumServiceProtocol, modelContext: ModelContext? = nil) {
        self.asset = asset
        self.tatumService = tatumService
        self.modelContext = modelContext
        self.manualBalance = asset.manualBalance
        self.totalBalance = asset.manualBalance
    }
    
    func refreshBalances(forceRefresh: Bool = false) async {
        isLoadingBalance = true
        balanceError = nil
        balanceState = .loading
        
        // Update manual balance
        manualBalance = asset.manualBalance
        
        // Fetch on-chain balance if configured
        if let address = asset.address, let chainId = asset.chainId, !address.isEmpty {
            let (balance, isFromCache, updateTime) = await fetchOnChainBalanceWithState(
                address: address,
                chainId: chainId,
                forceRefresh: forceRefresh
            )
            onChainBalance = balance
            isCachedData = isFromCache
            lastBalanceUpdate = updateTime
            
            // Update balance state based on result
            if let error = balanceError {
                // We have an error, but might have cached data
                balanceState = .error(
                    message: error,
                    cachedBalance: balance > 0 ? balance : nil,
                    lastUpdated: updateTime
                )
            } else {
                // Successfully loaded (either fresh or cached)
                balanceState = .loaded(
                    balance: balance,
                    isCached: isFromCache,
                    lastUpdated: updateTime ?? Date()
                )
            }
        } else {
            // No on-chain configuration, just use manual balance
            balanceState = .loaded(
                balance: manualBalance,
                isCached: false,
                lastUpdated: Date()
            )
        }
        
        totalBalance = manualBalance + onChainBalance
        isLoadingBalance = false
    }
    
    func fetchTransactions(forceRefresh: Bool = false) async {
        guard let address = asset.address, 
              let chainId = asset.chainId, 
              !address.isEmpty else { return }
        
        isLoadingTransactions = true
        
        do {
            onChainTransactions = try await tatumService.fetchTransactionHistory(
                chainId: chainId,
                address: address,
                currency: asset.currency,
                limit: 20,
                forceRefresh: forceRefresh
            )
        } catch {
            onChainTransactions = []
        }
        
        isLoadingTransactions = false
    }
    
    private func fetchOnChainBalance(address: String, chainId: String, forceRefresh: Bool) async -> Double {
        do {
            AppLog.debug("Fetching on-chain balance for \(asset.currency) on \(chainId)", category: .balanceService)
            let balance = try await tatumService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: forceRefresh
            )
            AppLog.info("Successfully fetched on-chain balance: \(balance) \(asset.currency)", category: .balanceService)
            return balance
        } catch {
            AppLog.error("On-chain balance fetch error: \(error)", category: .balanceService)
            balanceError = error.localizedDescription
            return 0
        }
    }
    
    private func fetchOnChainBalanceWithState(address: String, chainId: String, forceRefresh: Bool) async -> (balance: Double, isFromCache: Bool, updateTime: Date?) {
        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: asset.currency)
        let lastUpdate = BalanceCacheManager.shared.getLastBalanceUpdate(for: cacheKey)
        
        do {
            AppLog.debug("Fetching on-chain balance for \(asset.currency) on \(chainId)", category: .balanceService)
            let balance = try await tatumService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: forceRefresh
            )
            AppLog.info("Successfully fetched on-chain balance: \(balance) \(asset.currency)", category: .balanceService)
            
            // Check if this is cached data by comparing update times
            let newUpdate = BalanceCacheManager.shared.getLastBalanceUpdate(for: cacheKey)
            let isFromCache = newUpdate == lastUpdate && !forceRefresh
            
            return (balance, isFromCache, newUpdate ?? Date())
        } catch {
            AppLog.warning("On-chain balance fetch error: \(error)", category: .balanceService)
            balanceError = error.localizedDescription
            
            // Try to get cached balance as fallback
            if let cachedBalance = BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) {
                AppLog.info("Using cached balance: \(cachedBalance) \(asset.currency)", category: .cache)
                return (cachedBalance, true, lastUpdate)
            }
            
            // No cached data available
            return (0, false, nil)
        }
    }
    
    // Static method for one-off calculations without creating a ViewModel
    static func getCurrentAmount(for asset: Asset) async -> Double {
        var total = asset.manualBalance
        
        if let address = asset.address, let chainId = asset.chainId, !address.isEmpty {
            do {
                let onChainBalance = try await DIContainer.shared.tatumService.fetchBalance(
                    chainId: chainId,
                    address: address,
                    symbol: asset.currency,
                    forceRefresh: false
                )
                total += onChainBalance
            } catch {
                // Silent fail, use manual balance only
            }
        }
        
        return total
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        if let index = asset.transactions.firstIndex(where: { $0.id == transaction.id }) {
            asset.transactions.remove(at: index)
        }
        if let modelContext = modelContext {
            ContributionBridge.removeLinkedContributions(for: transaction, in: modelContext)
        }
        modelContext?.delete(transaction)
        
        do {
            try modelContext?.save()
            // Update balances after deletion
            Task {
                await refreshBalances()
            }
        } catch {
            AppLog.error("Failed to delete transaction: \(error)", category: .transactionHistory)
        }
    }
}
