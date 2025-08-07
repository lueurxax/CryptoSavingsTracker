//
//  CoinGeckoService.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import Foundation
import os

struct CoinInfo: Codable, Identifiable {
    let id: String
    let symbol: String
    let name: String
}

// Service layer should not be UI-aware
class CoinGeckoService {
    static let shared = CoinGeckoService()
    
    // Crypto currencies (for assets)
    private(set) var coins: [String] = []
    private(set) var coinInfos: [CoinInfo] = []
    
    // Fiat currencies (for goals)
    private(set) var supportedCurrencies: [String] = []
    
    private let apiKey: String
    private let cache = NSCache<NSString, NSArray>()
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "CoinGeckoService")

    init() {
        apiKey = Self.loadAPIKey()
        loadCachedCoins()
        loadCachedCurrencies()
    }
    
    private static func loadAPIKey() -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["CoinGeckoAPIKey"] as? String else {

            log.error("Warning: Could not load API key from Config.plist")
            return "YOUR_COINGECKO_API_KEY"
        }
        return key
    }
    
    // MARK: - Crypto Coins (for assets)
    func fetchCoins() async {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/list") else {
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
            CoinGeckoService.log.debug("Start fetching coins from CoinGecko")
            let (data, _) = try await URLSession.shared.data(for: request)
            let coinInfoList = try JSONDecoder().decode([CoinInfo].self, from: data)
            CoinGeckoService.log.debug("Fetched \(coinInfoList.count) coins from CoinGecko")

            self.coinInfos = coinInfoList.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
            self.coins = coinInfoList.map { $0.symbol.uppercased() }.sorted { $0.lowercased() < $1.lowercased() }
            self.cacheCoinInfos(coinInfoList)
            CoinGeckoService.log.debug("Coins loaded: \(self.coins.count)")
        } catch {
            // Coin fetching failed - using empty list
            CoinGeckoService.log.error("Failed to fetch coins: \(error)")
        }
    }
    
    // MARK: - Fiat Currencies (for goals)
    func fetchSupportedCurrencies() async {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/supported_vs_currencies") else {
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
            CoinGeckoService.log.debug("Start fetching supported currencies from CoinGecko")
            let (data, _) = try await URLSession.shared.data(for: request)
            let currencies = try JSONDecoder().decode([String].self, from: data)
            CoinGeckoService.log.debug("Fetched \(currencies.count) supported currencies from CoinGecko")

            self.supportedCurrencies = currencies.map { $0.uppercased() }.sorted()
            self.cacheSupportedCurrencies(currencies)
            CoinGeckoService.log.debug("Supported currencies loaded: \(self.supportedCurrencies.count)")
        } catch {
            // Currency fetching failed - using empty list
            CoinGeckoService.log.error("Failed to fetch supported currencies: \(error)")
        }
    }
    
    // MARK: - Caching Methods
    private func cacheCoinInfos(_ coinInfos: [CoinInfo]) {
        if let data = try? JSONEncoder().encode(coinInfos) {
            UserDefaults.standard.set(data, forKey: "cached_coin_infos")
            UserDefaults.standard.set(Date(), forKey: "coins_cache_date")
        }
    }
    
    private func cacheSupportedCurrencies(_ currencies: [String]) {
        if let data = try? JSONEncoder().encode(currencies) {
            UserDefaults.standard.set(data, forKey: "cached_supported_currencies")
            UserDefaults.standard.set(Date(), forKey: "currencies_cache_date")
        }
    }
    
    private func loadCachedCoins() {
        guard let data = UserDefaults.standard.data(forKey: "cached_coin_infos"),
              let cachedCoinInfos = try? JSONDecoder().decode([CoinInfo].self, from: data) else {
            return
        }
        
        // Use cached data if it's less than 24 hours old
        if let cacheDate = UserDefaults.standard.object(forKey: "coins_cache_date") as? Date,
           Date().timeIntervalSince(cacheDate) < 24 * 60 * 60 {
            self.coinInfos = cachedCoinInfos.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
            self.coins = cachedCoinInfos.map { $0.symbol.uppercased() }.sorted { $0.lowercased() < $1.lowercased() }
        }
    }
    
    private func loadCachedCurrencies() {
        guard let data = UserDefaults.standard.data(forKey: "cached_supported_currencies"),
              let cachedCurrencies = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        
        // Use cached data if it's less than 24 hours old
        if let cacheDate = UserDefaults.standard.object(forKey: "currencies_cache_date") as? Date,
           Date().timeIntervalSince(cacheDate) < 24 * 60 * 60 {
            self.supportedCurrencies = cachedCurrencies.map { $0.uppercased() }.sorted()
        }
    }
    
    
}
