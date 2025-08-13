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
    
    // Persistent storage keys
    private let balanceCacheKey = "com.cryptosavings.balance.cache"
    
    private init() {
        loadPersistedCache()
    }
    
    // MARK: - Balance Cache
    
    func getCachedBalance(for key: String) -> Double? {
        cacheQueue.sync {
            guard let entry = balanceCache[key], !entry.isExpired else {
                return nil
            }
            return entry.balance
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
        }
    }
    
    private func persistCache() {
        if let encoded = try? JSONEncoder().encode(self.balanceCache) {
            UserDefaults.standard.set(encoded, forKey: self.balanceCacheKey)
            UserDefaults.standard.synchronize() // Force immediate save
        }
    }
}

