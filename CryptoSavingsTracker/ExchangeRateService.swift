//
//  ExchangeRateService.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import Foundation

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
            print("Warning: Could not load API key from Config.plist")
            return "YOUR_COINGECKO_API_KEY"
        }
        return key
    }
    
    private init() {
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
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "vs_currencies", value: to.lowercased()),
            URLQueryItem(name: "symbols", value: from.lowercased()),
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
        
        // Parse response: { "btc": { "usd": 45000 } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
              let fromRates = json[from.lowercased()],
              let rate = fromRates[to.lowercased()] else {
            throw ExchangeRateError.rateNotAvailable
        }
        
        return rate
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
