//
//  BalanceCacheManager.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 06/08/2025.
//

import Foundation

// Cache entry for balance data
struct BalanceCacheEntry: Codable {
    let balance: Double
    let timestamp: Date
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// Cache entry for transactions
struct TransactionsCacheEntry {
    let transactions: [TatumTransaction]
    let timestamp: Date
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// Singleton cache manager
final class BalanceCacheManager {
    static let shared = BalanceCacheManager()
    
    private var balanceCache: [String: BalanceCacheEntry] = [:]
    private var transactionsCache: [String: TransactionsCacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.cryptosavings.cache", attributes: .concurrent)
    
    // Cache duration in seconds (30 minutes default for balances - increased to reduce API calls)
    private let balanceCacheDuration: TimeInterval = 30 * 60
    
    // Cache duration for transactions (2 hours - transactions change less frequently)
    private let transactionsCacheDuration: TimeInterval = 2 * 60 * 60
    
    // Minimum time between API calls for the same resource (120 seconds - increased to prevent rate limits)
    private let minimumRefreshInterval: TimeInterval = 120
    
    // Track request timestamps to prevent rapid requests
    private var lastRequestTimes: [String: Date] = [:]
    
    // Persistent storage keys
    private let balanceCacheKey = "com.cryptosavings.balance.cache"
    private let lastRequestTimesKey = "com.cryptosavings.balance.lastRequests"
    
    private init() {
        loadPersistedCache()
    }
    
    // MARK: - Balance Cache
    
    func getCachedBalance(for key: String) -> Double? {
        cacheQueue.sync {
            // Return cached balance even if expired if we're rate limited
            if let entry = balanceCache[key] {
                // Check if we're too soon after last request attempt
                if let lastRequest = lastRequestTimes[key],
                   Date().timeIntervalSince(lastRequest) < minimumRefreshInterval {
                    // Return cached value regardless of expiry to avoid rate limits
                    return entry.balance
                }
                
                // Normal cache expiry check
                if !entry.isExpired {
                    return entry.balance
                }
            }
            return nil
        }
    }
    
    // Get cached balance without expiry check (for fallback scenarios)
    func getFallbackBalance(for key: String) -> Double? {
        cacheQueue.sync {
            return balanceCache[key]?.balance
        }
    }
    
    func cacheBalance(_ balance: Double, for key: String) {
        cacheQueue.async(flags: .barrier) {
            let entry = BalanceCacheEntry(
                balance: balance,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(self.balanceCacheDuration)
            )
            self.balanceCache[key] = entry
            print("[BalanceCache] Cached balance \(balance) for key: \(key)")
            self.persistCache()
            print("[BalanceCache] Persisted \(self.balanceCache.count) entries to disk")
        }
    }
    
    func canRefreshBalance(for key: String) -> Bool {
        cacheQueue.sync {
            // Check last request time first to prevent rapid requests
            if let lastRequest = lastRequestTimes[key] {
                let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
                if timeSinceLastRequest < minimumRefreshInterval {
                    return false
                }
            }
            
            // Then check cache entry
            guard let entry = balanceCache[key] else { return true }
            let timeSinceLastUpdate = Date().timeIntervalSince(entry.timestamp)
            return timeSinceLastUpdate >= minimumRefreshInterval
        }
    }
    
    // Mark that a request was attempted (for rate limiting)
    func markRequestAttempt(for key: String) {
        cacheQueue.async(flags: .barrier) {
            self.lastRequestTimes[key] = Date()
            self.persistCache()
        }
    }
    
    func getLastBalanceUpdate(for key: String) -> Date? {
        cacheQueue.sync {
            return balanceCache[key]?.timestamp
        }
    }
    
    // MARK: - Transactions Cache
    
    func getCachedTransactions(for key: String) -> [TatumTransaction]? {
        cacheQueue.sync {
            guard let entry = transactionsCache[key], !entry.isExpired else {
                return nil
            }
            return entry.transactions
        }
    }
    
    func getAnyTransactions(for key: String) -> [TatumTransaction]? {
        cacheQueue.sync {
            return transactionsCache[key]?.transactions
        }
    }
    
    func cacheTransactions(_ transactions: [TatumTransaction], for key: String) {
        cacheQueue.async(flags: .barrier) {
            let entry = TransactionsCacheEntry(
                transactions: transactions,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(self.transactionsCacheDuration)
            )
            self.transactionsCache[key] = entry
        }
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.balanceCache.removeAll()
            self.transactionsCache.removeAll()
        }
    }
    
    func clearExpiredEntries() {
        cacheQueue.async(flags: .barrier) {
            self.balanceCache = self.balanceCache.filter { !$0.value.isExpired }
            self.transactionsCache = self.transactionsCache.filter { !$0.value.isExpired }
        }
    }
    
    // Generate cache key for balance
    static func balanceCacheKey(chainId: String, address: String, symbol: String) -> String {
        return "balance_\(chainId)_\(address)_\(symbol)".lowercased()
    }
    
    // Generate cache key for transactions
    static func transactionsCacheKey(chainId: String, address: String, currency: String? = nil) -> String {
        if let currency = currency {
            return "transactions_\(chainId)_\(address)_\(currency)".lowercased()
        } else {
            return "transactions_\(chainId)_\(address)".lowercased()
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedCache() {
        cacheQueue.async(flags: .barrier) {
            // Load balance cache
            if let data = UserDefaults.standard.data(forKey: self.balanceCacheKey),
               let decodedCache = try? JSONDecoder().decode([String: BalanceCacheEntry].self, from: data) {
                // Only load non-expired entries or entries less than 24 hours old
                let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
                self.balanceCache = decodedCache.filter { entry in
                    // Keep if not expired OR if it was cached within last 24 hours
                    !entry.value.isExpired || entry.value.timestamp > oneDayAgo
                }
                print("[BalanceCache] Loaded \(self.balanceCache.count) cached balances from disk")
            } else {
                print("[BalanceCache] No persisted cache found on disk")
            }
            
            // Load last request times
            if let data = UserDefaults.standard.data(forKey: self.lastRequestTimesKey),
               let decodedTimes = try? JSONDecoder().decode([String: Date].self, from: data) {
                // Only keep recent request times (within last hour)
                let oneHourAgo = Date().addingTimeInterval(-3600)
                self.lastRequestTimes = decodedTimes.filter { $0.value > oneHourAgo }
            }
        }
    }
    
    private func persistCache() {
        // Already called from within a barrier block, so directly save
        // Save balance cache
        if let encoded = try? JSONEncoder().encode(self.balanceCache) {
            UserDefaults.standard.set(encoded, forKey: self.balanceCacheKey)
            UserDefaults.standard.synchronize() // Force immediate save
        }
        
        // Save last request times
        if let encoded = try? JSONEncoder().encode(self.lastRequestTimes) {
            UserDefaults.standard.set(encoded, forKey: self.lastRequestTimesKey)
            UserDefaults.standard.synchronize() // Force immediate save
        }
    }
}