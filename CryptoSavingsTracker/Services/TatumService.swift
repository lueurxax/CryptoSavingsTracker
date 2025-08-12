    //
    //  TatumService.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 05/08/2025.
    //

import Foundation
import Combine
import os

// MARK: - Facade Service (Backward Compatibility)
// This service now acts as a facade, delegating to the smaller specialized services

final class TatumService {
    static let shared = TatumService()
    
    // Delegate to specialized services
    private let chainService = ChainService.shared
    private let balanceService = BalanceService.shared
    private let transactionService = TransactionService.shared
    
    // Expose chain data for backward compatibility
    @Published var supportedChains: [TatumChain] = []
    
    init() {
        // Mirror chain data from ChainService
        supportedChains = chainService.supportedChains
        
        // Keep in sync with chain service
        chainService.$supportedChains.sink { [weak self] chains in
            self?.supportedChains = chains
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Chain Methods (Delegate to ChainService)
    func predictChain(for symbol: String) -> TatumChain? {
        return chainService.predictChain(for: symbol)
    }
    
    // MARK: - Balance Methods (Delegate to BalanceService)
    func fetchBalance(chainId: String, address: String, symbol: String, forceRefresh: Bool = false) async throws -> Double {
        return try await balanceService.fetchBalance(chainId: chainId, address: address, symbol: symbol, forceRefresh: forceRefresh)
    }
    
    // MARK: - Transaction Methods (Delegate to TransactionService)
    func fetchTransactionHistory(chainId: String, address: String, currency: String? = nil, limit: Int = 50, forceRefresh: Bool = false) async throws -> [TatumTransaction] {
        return try await transactionService.fetchTransactionHistory(chainId: chainId, address: address, currency: currency, limit: limit, forceRefresh: forceRefresh)
    }
    
    // MARK: - Error Recovery Support
    func hasValidConfiguration() -> Bool {
        // Check if TatumClient has a valid API key
        return TatumClient.shared.hasValidAPIKey()
    }
    
    func setOfflineMode(_ offline: Bool) {
        // Propagate offline mode to underlying services
        TatumClient.shared.setOfflineMode(offline)
    }
}
