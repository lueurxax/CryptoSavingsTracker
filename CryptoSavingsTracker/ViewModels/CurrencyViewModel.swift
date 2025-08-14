//
//  CurrencyViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import SwiftUI
import Combine

@MainActor
class CurrencyViewModel: ObservableObject {
    // Crypto currencies (for assets)
    @Published var coins: [String] = []
    @Published var coinInfos: [CoinInfo] = []
    
    // Fiat currencies (for goals)
    @Published var supportedCurrencies: [String] = []
    
    @Published var isLoading = false
    
    private let coinGeckoService: CoinGeckoServiceProtocol
    
    init(coinGeckoService: CoinGeckoServiceProtocol) {
        self.coinGeckoService = coinGeckoService
        loadInitialData()
    }
    
    // Convenience initializer that uses DI container for backward compatibility
    convenience init() {
        self.init(coinGeckoService: DIContainer.shared.coinGeckoService)
    }
    
    private func loadInitialData() {
        // Load cached crypto data immediately
        coinInfos = coinGeckoService.coinInfos
        coins = coinGeckoService.coins
        
        // Load cached fiat currency data immediately
        supportedCurrencies = coinGeckoService.supportedCurrencies
        
        // Fetch fresh data if needed
        if coinInfos.isEmpty {
            Task {
                await fetchCoins()
            }
        }
        
        if supportedCurrencies.isEmpty {
            Task {
                await fetchSupportedCurrencies()
            }
        }
    }
    
    // MARK: - Crypto Coins (for assets)
    func fetchCoins() async {
        isLoading = true
        
        await coinGeckoService.fetchCoins()
        
        coinInfos = coinGeckoService.coinInfos
        coins = coinGeckoService.coins
        
        isLoading = false
    }
    
    // MARK: - Fiat Currencies (for goals)
    func fetchSupportedCurrencies() async {
        isLoading = true
        
        await coinGeckoService.fetchSupportedCurrencies()
        
        supportedCurrencies = coinGeckoService.supportedCurrencies
        
        isLoading = false
    }
}