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
class AssetViewModel: ObservableObject, ErrorAwareViewModel {
    @Published var onChainBalance: Double = 0
    @Published var manualBalance: Double = 0
    @Published var totalBalance: Double = 0
    @Published var isLoadingBalance: Bool = false
    @Published var balanceError: String?
    @Published var onChainTransactions: [TatumTransaction] = []
    @Published var isLoadingTransactions: Bool = false
    @Published var transactionError: String?
    @Published var lastBalanceUpdate: Date?
    @Published var balanceState: BalanceState = .loading
    @Published var isCachedData: Bool = false
    @Published var viewState: ViewState = .idle
    var lastSuccessfulLoad: Date?
    
    private let asset: Asset
    private let tatumService: TatumServiceProtocol
    private let modelContext: ModelContext?

    private var hasOnChainConfiguration: Bool {
        guard let address = asset.address, let chainId = asset.chainId else { return false }
        return !address.isEmpty && !chainId.isEmpty
    }

    private var hasRetainedOnChainValue: Bool {
        switch balanceState {
        case .loading:
            return lastBalanceUpdate != nil || lastSuccessfulLoad != nil || isCachedData
        case .loaded:
            return true
        case .error(_, let cachedBalance, let lastUpdated):
            return cachedBalance != nil || lastUpdated != nil
        }
    }

    var publicCryptoTrackingStatus: BalanceState.CryptoTrackingStatus? {
        guard hasOnChainConfiguration else { return nil }
        return balanceState.publicCryptoTrackingStatus(
            isRefreshing: isLoadingBalance,
            hasRetainedValue: hasRetainedOnChainValue
        )
    }

    var publicTrackingStatusDetail: String? {
        guard hasOnChainConfiguration else { return nil }
        return balanceState.publicTrackingStatusDetail(
            isRefreshing: isLoadingBalance,
            hasRetainedValue: hasRetainedOnChainValue
        )
    }
    
    init(asset: Asset, tatumService: TatumServiceProtocol, modelContext: ModelContext? = nil) {
        self.asset = asset
        self.tatumService = tatumService
        self.modelContext = modelContext
        self.manualBalance = asset.manualBalance
        self.totalBalance = asset.manualBalance
    }
    
    func retry() async {
        await refreshBalances(forceRefresh: true)
    }

    func refreshBalances(forceRefresh: Bool = false) async {
        isLoadingBalance = true
        balanceError = nil
        balanceState = .loading
        viewState = .loading
        
        // Update manual balance
        manualBalance = asset.manualBalance
        
        // Fetch on-chain balance if configured
        if let address = asset.address, let chainId = asset.chainId, !address.isEmpty {
            let result = await fetchOnChainBalanceWithState(
                address: address,
                chainId: chainId,
                forceRefresh: forceRefresh
            )
            onChainBalance = result.balance
            isCachedData = result.isFromCache
            lastBalanceUpdate = result.updateTime
            
            // Update balance state based on result
            if let error = balanceError {
                // Expired cache may explain the degraded state, but it is not
                // promoted into the operational on-chain or total balances.
                balanceState = .error(
                    message: error,
                    cachedBalance: result.fallbackBalance,
                    lastUpdated: result.updateTime
                )
            } else {
                // Successfully loaded (either fresh or cached)
                balanceState = .loaded(
                    balance: result.balance,
                    isCached: result.isFromCache,
                    lastUpdated: result.updateTime ?? Date()
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
        lastSuccessfulLoad = Date()
        if balanceError != nil {
            viewState = .degraded("Some balance data may be stale")
        } else {
            viewState = .loaded
        }
    }
    
    func fetchTransactions(forceRefresh: Bool = false) async {
        guard let address = asset.address, 
              let chainId = asset.chainId, 
              !address.isEmpty else { return }
        
        isLoadingTransactions = true
        transactionError = nil
        
        do {
            let batch = try await tatumService.fetchTransactionHistoryBatch(
                chainId: chainId,
                address: address,
                currency: asset.currency,
                limit: 20,
                forceRefresh: forceRefresh
            )

            guard let modelContext else {
                throw OnChainTransactionImportError.persistenceUnavailable
            }
            switch try batch.commitIfCurrent({
                let importer = OnChainTransactionImportService(
                    modelContext: modelContext
                )
                let importResult = try importer.upsertWithResult(
                    transactions: batch.transactions,
                    for: asset
                )
                tatumService.commitImportedTransactionHistory(
                    importResult.acceptedTransactions,
                    chainId: chainId,
                    address: address,
                    currency: asset.currency
                )
                return importResult
            }) {
            case .committed(let importResult):
                onChainTransactions = importResult.acceptedTransactions
            case .superseded:
                break
            }
        } catch {
            transactionError = error.localizedDescription
            viewState = .degraded("Transaction history may be stale")
        }
        
        isLoadingTransactions = false
    }

    func retryTransactions() async {
        await fetchTransactions(forceRefresh: true)
    }
    
    private func fetchOnChainBalance(address: String, chainId: String, forceRefresh: Bool) async -> Double {
        do {
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
    
    private func fetchOnChainBalanceWithState(
        address: String,
        chainId: String,
        forceRefresh: Bool
    ) async -> (
        balance: Double,
        isFromCache: Bool,
        updateTime: Date?,
        fallbackBalance: Double?
    ) {
        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: asset.currency)
        let lastUpdate = BalanceCacheManager.shared.getLastBalanceUpdate(for: cacheKey)
        
        do {
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
            
            return (balance, isFromCache, newUpdate ?? Date(), nil)
        } catch {
            AppLog.warning("On-chain balance fetch error: \(error)", category: .balanceService)
            balanceError = error.localizedDescription
            
            let fallbackBalance = BalanceCacheManager.shared.getFallbackBalance(
                for: cacheKey
            )
            if let fallbackBalance {
                AppLog.info(
                    "Retaining expired balance for degraded presentation: \(fallbackBalance) \(asset.currency)",
                    category: .cache
                )
            }
            return (0, false, lastUpdate, fallbackBalance)
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
    
}
