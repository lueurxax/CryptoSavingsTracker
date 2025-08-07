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
    
    private let asset: Asset
    private let tatumService: TatumService
    private let modelContext: ModelContext?
    
    init(asset: Asset, tatumService: TatumService, modelContext: ModelContext? = nil) {
        self.asset = asset
        self.tatumService = tatumService
        self.modelContext = modelContext
        self.manualBalance = asset.manualBalance
        self.totalBalance = asset.manualBalance
    }
    
    func refreshBalances(forceRefresh: Bool = false) async {
        isLoadingBalance = true
        balanceError = nil
        
        // Update manual balance
        manualBalance = asset.manualBalance
        
        // Fetch on-chain balance if configured
        if let address = asset.address, let chainId = asset.chainId, !address.isEmpty {
            onChainBalance = await fetchOnChainBalance(
                address: address,
                chainId: chainId,
                forceRefresh: forceRefresh
            )
            lastBalanceUpdate = Date()
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
            print("🔄 Fetching on-chain balance for \(asset.currency) on \(chainId)")
            let balance = try await tatumService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: forceRefresh
            )
            print("✅ Successfully fetched on-chain balance: \(balance) \(asset.currency)")
            return balance
        } catch {
            print("❌ On-chain balance fetch error: \(error)")
            balanceError = error.localizedDescription
            return 0
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
        modelContext?.delete(transaction)
        
        do {
            try modelContext?.save()
            // Update balances after deletion
            Task {
                await refreshBalances()
            }
        } catch {
            print("Failed to delete transaction: \(error)")
        }
    }
}