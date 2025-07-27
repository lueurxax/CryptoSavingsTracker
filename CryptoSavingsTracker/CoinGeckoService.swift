//
//  CoinGeckoService.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import Foundation
import Combine
import os

struct CoinInfo: Codable, Identifiable {
    let id: String
    let symbol: String
    let name: String
}

@MainActor
class CoinGeckoService: ObservableObject {
    static let shared = CoinGeckoService()
    
    @Published var coins: [String] = []
    @Published var isLoading = false
    
    private let apiKey = "CG-Dq3qkeTzqjYtbG5LDKJVTibv"
    private let cache = NSCache<NSString, NSArray>()
    private let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "CoinGeckoService")

    private init() {
        loadCachedCoins()
    }
    
    func fetchCoins() async {
        await MainActor.run {
            isLoading = true
        }
        
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/supported_vs_currencies") else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "x-cg-demo-api-key": apiKey
        ]
        
        do {
            log.debug("Start fetching coins from CoinGecko")
            let (data, _) = try await URLSession.shared.data(for: request)
            let coinList = try JSONDecoder().decode([String].self, from: data)
            log.debug("Fetched \(coinList.count) coins from CoinGecko")

            await MainActor.run {
                self.coins = coinList.sorted { $0.lowercased() < $1.lowercased() }
                self.isLoading = false
                self.cacheCoins(coinList)
                log.debug("Coins loaded: \(self.coins.count)")
            }
        } catch {
            print("Failed to fetch coins: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func cacheCoins(_ coins: [String]) {
        if let data = try? JSONEncoder().encode(coins) {
            UserDefaults.standard.set(data, forKey: "cached_coins")
            UserDefaults.standard.set(Date(), forKey: "coins_cache_date")
        }
    }
    
    private func loadCachedCoins() {
        guard let data = UserDefaults.standard.data(forKey: "cached_coins"),
              let cachedCoins = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        
        // Use cached data if it's less than 24 hours old
        if let cacheDate = UserDefaults.standard.object(forKey: "coins_cache_date") as? Date,
           Date().timeIntervalSince(cacheDate) < 24 * 60 * 60 {
            self.coins = cachedCoins.sorted { $0.lowercased() < $1.lowercased() }
        }
    }
    
    
}
