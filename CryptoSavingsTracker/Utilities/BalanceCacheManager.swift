//
//  BalanceCacheManager.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 06/08/2025.
//

import Foundation

// Cache entry for balance data
struct BalanceCacheEntry {
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
    
    private init() {}
    
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
}