//
//  ExchangeRateService.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import Foundation

// Import protocol definitions - this should be resolved by having them in the same module

class ExchangeRateService: ExchangeRateServiceProtocol {
    static let shared = ExchangeRateService()
    
    private var cachedRates: [String: [String: Double]] = [:]
    private let cacheExpiration: TimeInterval = 300
    private var lastFetchTime: [String: Date] = [:]
    private let apiKey: String
    
    private var isOffline = false
    
    // Map common crypto symbols to CoinGecko IDs.
    // Note: this is only used for the "base asset" side of CoinGecko queries (ids=...), not for vs_currencies.
    private static let cryptoIdMap: [String: String] = [
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

    private static func normalizedCurrencyCode(_ code: String) -> String {
        code.uppercased()
    }

    private static func coinGeckoId(forCryptoSymbol symbol: String) -> String {
        let upper = normalizedCurrencyCode(symbol)
        return cryptoIdMap[upper] ?? upper.lowercased()
    }
    
    private static func loadAPIKey() -> String {
        // Try to get API key from Keychain first
        if let keychainKey = KeychainManager.coinGeckoAPIKey {
            return keychainKey
        }
        
        // Fall back to Config.plist and migrate if found
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["CoinGeckoAPIKey"] as? String else {
            // API key not found in Config.plist - using placeholder
            return "YOUR_COINGECKO_API_KEY"
        }
        
        // Migrate to Keychain if we have a valid key
        if !key.isEmpty && key != "YOUR_COINGECKO_API_KEY" {
            try? KeychainManager.storeAPIKey(key, for: "coingecko")
            AppLog.info("Migrated CoinGecko API key to Keychain", category: .api)
        }
        
        return key
    }
    
    init() {
        apiKey = Self.loadAPIKey()
        loadCachedData()
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        let canonicalFrom = Self.normalizedCurrencyCode(from)
        let canonicalTo = Self.normalizedCurrencyCode(to)

        if canonicalFrom == canonicalTo {
            return 1.0
        }
        
        if let cachedRate = getCachedRate(from: canonicalFrom, to: canonicalTo) {
            return cachedRate
        }
        
        let rate = try await fetchRateFromAPI(from: canonicalFrom, to: canonicalTo)
        cacheRate(from: canonicalFrom, to: canonicalTo, rate: rate)
        
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
        // Check if we should throttle during startup
        if StartupThrottler.shared.shouldThrottleAPICall() {
            AppLog.info("Startup throttling in effect, delaying rate fetch for \(from)->\(to)", category: .exchangeRate)
            await StartupThrottler.shared.waitForStartup()
        }
        
        // Common fiat currencies that might need cross-conversion
        let fiatCurrencies = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY", "INR", "KRW"]
        let fromUppercase = from.uppercased()
        let toUppercase = to.uppercased()

        let fromIsFiat = fiatCurrencies.contains(fromUppercase)
        let toIsFiat = fiatCurrencies.contains(toUppercase)
        
        // Check if both are fiat currencies - if so, use cross-conversion through USDT
        if fromIsFiat && toIsFiat {
            return try await fetchCrossRate(from: from, to: to, through: "USDT")
        }

        // Crypto ↔ Fiat
        if !fromIsFiat && toIsFiat {
            return try await fetchDirectRate(from: from, to: to)
        }
        if fromIsFiat && !toIsFiat {
            // Fiat -> Crypto = 1 / (Crypto -> Fiat)
            let cryptoInFiat = try await fetchDirectRate(from: to, to: from)
            guard cryptoInFiat > 0 else { throw ExchangeRateError.rateNotAvailable }
            return 1.0 / cryptoInFiat
        }

        // Crypto ↔ Crypto (including stablecoins like USDT): compute via USD to avoid unsupported vs_currency codes.
        return try await fetchCryptoToCryptoRateViaUSD(from: from, to: to)
    }
    
    private func fetchDirectRate(from: String, to: String) async throws -> Double {
        let fromId = Self.coinGeckoId(forCryptoSymbol: from)
        
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        
        // Parse response: { "bitcoin": { "usd": 45000 } }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
           let fromRates = json[fromId],
           let rate = fromRates[to.lowercased()] {
            return rate
        }

        // Fallback: try coins/markets to handle cases where simple/price omits the pair
        if let marketsRate = try await fetchRateFromMarkets(id: fromId, to: to) {
            return marketsRate
        }
        
        AppLog.warning("Rate not available in response for \(fromId) to \(to). HTTP \(status). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
        throw ExchangeRateError.rateNotAvailable
    }

    private func fetchCryptoToCryptoRateViaUSD(from: String, to: String) async throws -> Double {
        let fromId = Self.coinGeckoId(forCryptoSymbol: from)
        let toId = Self.coinGeckoId(forCryptoSymbol: to)

        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "ids", value: "\(fromId),\(toId)")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "x-cg-demo-api-key": apiKey
        ]

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
            let fromUsd = json[fromId]?["usd"],
            let toUsd = json[toId]?["usd"],
            fromUsd > 0,
            toUsd > 0
        else {
            AppLog.warning("Crypto cross rate not available for \(from)->\(to) via USD. HTTP \(status). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
            throw ExchangeRateError.rateNotAvailable
        }

        return fromUsd / toUsd
    }

    // Some assets (or temporarily missing pairs) are available via /coins/markets even when /simple/price omits them.
    private func fetchRateFromMarkets(id: String, to: String) async throws -> Double? {
        guard !id.isEmpty else { return nil }

        let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: to.lowercased()),
            URLQueryItem(name: "ids", value: id),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "1"),
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        struct MarketRate: Decodable {
            let current_price: Double?
        }

        do {
            let markets = try JSONDecoder().decode([MarketRate].self, from: data)
            if let price = markets.first?.current_price, price > 0 {
                return price
            } else {
                AppLog.warning("Market rate missing/zero for \(id)->\(to). HTTP \(status). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
            }
        } catch {
            AppLog.warning("Failed to decode market rate for \(id)->\(to). HTTP \(status). Error: \(error.localizedDescription). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
        }

        return nil
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        
        // Parse response: { "tether": { "usd": 1.0, "eur": 0.85 } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
              let intermediaryRates = json[intermediaryId],
              let fromRate = intermediaryRates[from.lowercased()],
              let toRate = intermediaryRates[to.lowercased()],
              fromRate > 0 else {
            AppLog.warning("Cross rate not available for \(from)->\(to) via \(intermediary). HTTP \(status). Response: \(String(data: data, encoding: .utf8) ?? "nil")", category: .exchangeRate)
            throw ExchangeRateError.rateNotAvailable
        }
        
        // Calculate cross rate: from -> to = toRate / fromRate
        // This works because: 1 USDT = fromRate FROM, and 1 USDT = toRate TO
        // So: 1 FROM = 1/fromRate USDT = (toRate/fromRate) TO
        let crossRate = toRate / fromRate
        
        
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
    
    // MARK: - Fallback Rates
    private func getFallbackRate(from: String, to: String) -> Double? {
        // NEVER return fake rates - this is dangerous for financial calculations
        // Only return nil to indicate rate is unavailable
        return nil
    }
    
    // MARK: - Error Recovery Support
    func hasValidConfiguration() -> Bool {
        return apiKey != "YOUR_COINGECKO_API_KEY" && !apiKey.isEmpty
    }
    
    func setOfflineMode(_ offline: Bool) {
        isOffline = offline
        if offline {
            AppLog.info("Exchange rate service operating in offline mode", category: .api)
        }
    }
}

enum ExchangeRateError: LocalizedError {
    case rateNotAvailable
    case networkError
    case rateLimitExceeded
    case apiKeyMissing
    
    var errorDescription: String? {
        switch self {
        case .rateNotAvailable:
            return "Exchange rate temporarily unavailable. Please check your internet connection."
        case .networkError:
            return "Network error. Please try again later."
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please wait before trying again."
        case .apiKeyMissing:
            return "API key not configured. Please add your CoinGecko API key in settings."
        }
    }
}
