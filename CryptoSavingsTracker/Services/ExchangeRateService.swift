//
//  ExchangeRateService.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import Foundation

// Import protocol definitions - this should be resolved by having them in the same module

class ExchangeRateService {
    static let shared = ExchangeRateService()
    
    private var cachedRates: [String: [String: Double]] = [:]
    private let cacheExpiration: TimeInterval = 300
    private var lastFetchTime: [String: Date] = [:]
    private let apiKey: String
    
    private static func loadAPIKey() -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["CoinGeckoAPIKey"] as? String else {
            // API key not found in Config.plist - using placeholder
            return "YOUR_COINGECKO_API_KEY"
        }
        return key
    }
    
    init() {
        apiKey = Self.loadAPIKey()
        loadCachedData()
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        if from == to {
            return 1.0
        }
        
        if let cachedRate = getCachedRate(from: from, to: to) {
            return cachedRate
        }
        
        let rate = try await fetchRateFromAPI(from: from, to: to)
        cacheRate(from: from, to: to, rate: rate)
        
        return rate
    }
    
    private func getCachedRate(from: String, to: String) -> Double? {
        let cacheKey = "\(from)-\(to)"
        
        if let lastFetch = lastFetchTime[cacheKey],
           Date().timeIntervalSince(lastFetch) < cacheExpiration,
           let rate = cachedRates[from]?[to] {
            return rate
        }
        
        return nil
    }
    
    private func cacheRate(from: String, to: String, rate: Double) {
        let cacheKey = "\(from)-\(to)"
        
        if cachedRates[from] == nil {
            cachedRates[from] = [:]
        }
        cachedRates[from]?[to] = rate
        lastFetchTime[cacheKey] = Date()
        
        saveCachedData()
    }
    
    private func fetchRateFromAPI(from: String, to: String) async throws -> Double {
        // Common fiat currencies that might need cross-conversion
        let fiatCurrencies = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY", "INR", "KRW"]
        let fromUppercase = from.uppercased()
        let toUppercase = to.uppercased()
        
        // Check if both are fiat currencies - if so, use cross-conversion through USDT
        if fiatCurrencies.contains(fromUppercase) && fiatCurrencies.contains(toUppercase) {
            AppLog.debug("Both \(from) and \(to) are fiat currencies, using USDT cross-conversion", category: .exchangeRate)
            return try await fetchCrossRate(from: from, to: to, through: "USDT")
        }
        
        // Try direct conversion first
        do {
            return try await fetchDirectRate(from: from, to: to)
        } catch {
            // If direct conversion fails, try cross-conversion through USDT
            AppLog.debug("Direct conversion failed for \(from) to \(to), trying USDT cross-conversion", category: .exchangeRate)
            return try await fetchCrossRate(from: from, to: to, through: "USDT")
        }
    }
    
    private func fetchDirectRate(from: String, to: String) async throws -> Double {
        // Map common crypto symbols to CoinGecko IDs
        let cryptoIdMap: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "USDT": "tether",
            "BNB": "binancecoin",
            "SOL": "solana",
            "USDC": "usd-coin",
            "XRP": "ripple",
            "ADA": "cardano",
            "DOGE": "dogecoin",
            "TRX": "tron",
            "AVAX": "avalanche-2",
            "DOT": "polkadot",
            "MATIC": "matic-network",
            "LINK": "chainlink",
            "SHIB": "shiba-inu",
            "LTC": "litecoin",
            "BCH": "bitcoin-cash",
            "ALGO": "algorand",
            "XLM": "stellar",
            "UNI": "uniswap"
        ]
        
        // Determine if 'from' is a crypto that needs ID mapping
        let fromId = cryptoIdMap[from.uppercased()] ?? from.lowercased()
        
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "vs_currencies", value: to.lowercased()),
            URLQueryItem(name: "ids", value: fromId),
        ]
        components.queryItems = components.queryItems.map { $0 + queryItems } ?? queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "x-cg-demo-api-key": apiKey
        ]

        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse response: { "bitcoin": { "usd": 45000 } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
              let fromRates = json[fromId],
              let rate = fromRates[to.lowercased()] else {
            AppLog.warning("Rate not available in response for \(fromId) to \(to). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
            throw ExchangeRateError.rateNotAvailable
        }
        
        return rate
    }
    
    private func fetchCrossRate(from: String, to: String, through intermediary: String) async throws -> Double {
        // Get both rates: from -> intermediary and intermediary -> to
        // Then calculate: from -> to = (1 / (intermediary -> from)) * (intermediary -> to)
        
        let intermediaryLower = intermediary.lowercased()
        
        // Fetch both currencies' rates against the intermediary
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        
        // For USDT, we need to use "tether" as the ID
        let intermediaryId = intermediary == "USDT" ? "tether" : intermediaryLower
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "ids", value: intermediaryId),
            URLQueryItem(name: "vs_currencies", value: "\(from.lowercased()),\(to.lowercased())")
        ]
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "x-cg-demo-api-key": apiKey
        ]

        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse response: { "tether": { "usd": 1.0, "eur": 0.85 } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
              let intermediaryRates = json[intermediaryId],
              let fromRate = intermediaryRates[from.lowercased()],
              let toRate = intermediaryRates[to.lowercased()],
              fromRate > 0 else {
            throw ExchangeRateError.rateNotAvailable
        }
        
        // Calculate cross rate: from -> to = toRate / fromRate
        // This works because: 1 USDT = fromRate FROM, and 1 USDT = toRate TO
        // So: 1 FROM = 1/fromRate USDT = (toRate/fromRate) TO
        let crossRate = toRate / fromRate
        
        AppLog.debug("Cross-conversion: 1 \(intermediary) = \(fromRate) \(from), 1 \(intermediary) = \(toRate) \(to), therefore 1 \(from) = \(crossRate) \(to)", category: .exchangeRate)
        
        return crossRate
    }
    
    private func saveCachedData() {
        if let ratesData = try? JSONEncoder().encode(cachedRates) {
            UserDefaults.standard.set(ratesData, forKey: "cached_exchange_rates")
        }
        
        if let timesData = try? JSONEncoder().encode(lastFetchTime) {
            UserDefaults.standard.set(timesData, forKey: "cached_fetch_times")
        }
    }
    
    private func loadCachedData() {
        if let ratesData = UserDefaults.standard.data(forKey: "cached_exchange_rates"),
           let rates = try? JSONDecoder().decode([String: [String: Double]].self, from: ratesData) {
            cachedRates = rates
        }
        
        if let timesData = UserDefaults.standard.data(forKey: "cached_fetch_times"),
           let times = try? JSONDecoder().decode([String: Date].self, from: timesData) {
            lastFetchTime = times
        }
    }
}

enum ExchangeRateError: Error {
    case rateNotAvailable
    case networkError
}