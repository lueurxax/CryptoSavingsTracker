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
class CoinGeckoService: CoinGeckoServiceProtocol {
    static let shared = CoinGeckoService()
    
    // Crypto currencies (for assets)
    private(set) var coins: [String] = []
    private(set) var coinInfos: [CoinInfo] = []
    
    // Fiat currencies (for goals)
    private(set) var supportedCurrencies: [String] = []
    
    // Cache freshness flags
    private(set) var coinCacheStale: Bool = true
    private(set) var currencyCacheStale: Bool = true
    private let cacheTTL: TimeInterval = 6 * 60 * 60 // refresh coin list at least every 6 hours
    
    private let apiKey: String
    private let cache = NSCache<NSString, NSArray>()
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "CoinGeckoService")
    private var isOffline = false

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
        do {
            // Prefer markets endpoint so we can drop entries with missing prices
            if let marketURL = URL(string: "https://api.coingecko.com/api/v3/coins/markets") {
                var components = URLComponents(url: marketURL, resolvingAgainstBaseURL: true)!
                components.queryItems = [
                    URLQueryItem(name: "vs_currency", value: "usd"),
                    URLQueryItem(name: "order", value: "market_cap_desc"),
                    URLQueryItem(name: "per_page", value: "250"),
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "sparkline", value: "false")
                ]

                var request = URLRequest(url: components.url!)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                request.allHTTPHeaderFields = [
                    "accept": "application/json",
                    "x-cg-demo-api-key": apiKey
                ]

                CoinGeckoService.log.debug("Start fetching coins (markets) from CoinGecko")
                let (data, _) = try await URLSession.shared.data(for: request)

                struct MarketCoin: Decodable {
                    let id: String
                    let symbol: String
                    let name: String
                    let current_price: Double?
                }

                let markets = try JSONDecoder().decode([MarketCoin].self, from: data)
                let filtered = markets.filter { $0.current_price != nil }
                let coinInfoList = filtered.map { CoinInfo(id: $0.id, symbol: $0.symbol.uppercased(), name: $0.name) }

                if !coinInfoList.isEmpty {
                    CoinGeckoService.log.info("Refreshed coin list from markets endpoint at \(Date()). usable=\(coinInfoList.count), raw=\(markets.count)")
                    self.coinInfos = coinInfoList.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
                    self.coins = coinInfoList.map { $0.symbol.uppercased() }.sorted { $0.lowercased() < $1.lowercased() }
                    self.cacheCoinInfos(coinInfoList, hasPrices: true)
                    self.coinCacheStale = false
                    CoinGeckoService.log.debug("Coins loaded: \(self.coins.count)")
                    return
                } else {
                    CoinGeckoService.log.warning("Markets endpoint returned no coins with prices; falling back to coins/list")
                }
            }

            // Fallback: original coins/list
            guard let listURL = URL(string: "https://api.coingecko.com/api/v3/coins/list") else { return }
            var listRequest = URLRequest(url: listURL)
            listRequest.httpMethod = "GET"
            listRequest.timeoutInterval = 10
            listRequest.allHTTPHeaderFields = [
                "accept": "application/json",
                "x-cg-demo-api-key": apiKey
            ]

            CoinGeckoService.log.debug("Start fetching coins (list) from CoinGecko")
            let (listData, _) = try await URLSession.shared.data(for: listRequest)
            let rawList = try JSONDecoder().decode([CoinInfo].self, from: listData)
            self.coinInfos = rawList.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
            self.coins = rawList.map { $0.symbol.uppercased() }.sorted { $0.lowercased() < $1.lowercased() }
            self.cacheCoinInfos(rawList, hasPrices: false)
            self.coinCacheStale = false
            CoinGeckoService.log.info("Refreshed coin list from coins/list at \(Date()). count=\(self.coins.count)")
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
            self.currencyCacheStale = false
            CoinGeckoService.log.debug("Supported currencies loaded: \(self.supportedCurrencies.count)")
        } catch {
            // Currency fetching failed - using empty list
            CoinGeckoService.log.error("Failed to fetch supported currencies: \(error)")
        }
    }
    
    // MARK: - Caching Methods
    private func cacheCoinInfos(_ coinInfos: [CoinInfo], hasPrices: Bool) {
        if let data = try? JSONEncoder().encode(coinInfos) {
            UserDefaults.standard.set(data, forKey: "cached_coin_infos")
            UserDefaults.standard.set(Date(), forKey: "coins_cache_date")
            UserDefaults.standard.set(hasPrices, forKey: "coins_cache_has_prices")
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
            coinCacheStale = true
            return
        }
        
        self.coinInfos = cachedCoinInfos.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
        self.coins = cachedCoinInfos.map { $0.symbol.uppercased() }.sorted { $0.lowercased() < $1.lowercased() }

        let hasPrices = UserDefaults.standard.bool(forKey: "coins_cache_has_prices")
        if let cacheDate = UserDefaults.standard.object(forKey: "coins_cache_date") as? Date {
            // Mark stale if older than the TTL or if cache was created before we started filtering by current_price
            coinCacheStale = Date().timeIntervalSince(cacheDate) >= cacheTTL || !hasPrices
            CoinGeckoService.log
                .info(
                    "Loaded cached coins: \(self.coins.count) (stale=\(self.coinCacheStale), cachedAt=\(cacheDate), hasPrices=\(hasPrices))"
                )
        } else {
            coinCacheStale = true
            CoinGeckoService.log.info("No cached coins found; will refresh.")
        }
    }
    
    private func loadCachedCurrencies() {
        guard let data = UserDefaults.standard.data(forKey: "cached_supported_currencies"),
              let cachedCurrencies = try? JSONDecoder().decode([String].self, from: data) else {
            currencyCacheStale = true
            return
        }
        
        self.supportedCurrencies = cachedCurrencies.map { $0.uppercased() }.sorted()

        if let cacheDate = UserDefaults.standard.object(forKey: "currencies_cache_date") as? Date {
            currencyCacheStale = Date().timeIntervalSince(cacheDate) >= 24 * 60 * 60
        } else {
            currencyCacheStale = true
        }
    }
    
    // MARK: - Error Recovery Support
    func hasValidConfiguration() -> Bool {
        return apiKey != "YOUR_COINGECKO_API_KEY" && !apiKey.isEmpty
    }
    
    func setOfflineMode(_ offline: Bool) {
        isOffline = offline
        if offline {
            CoinGeckoService.log.info("CoinGecko service operating in offline mode")
        }
    }
}
