//
//  BalanceCacheManager.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 06/08/2025.
//

import Foundation
import os

// Cache entry for balance data
struct BalanceCacheEntry: Codable {
    let balance: Double
    let timestamp: Date
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Immutable, non-network evidence for the currently authoritative balance-cache entry.
/// Exact bit patterns make financial drift checks sensitive to both value and freshness changes.
struct BalanceCacheSnapshotEvidence: Equatable, Sendable {
    let cacheKey: String
    let balance: UInt64
    let timestamp: UInt64
    let expiresAt: UInt64

    init(cacheKey: String, entry: BalanceCacheEntry) {
        self.cacheKey = cacheKey
        balance = entry.balance.bitPattern
        timestamp = entry.timestamp.timeIntervalSinceReferenceDate.bitPattern
        expiresAt = entry.expiresAt.timeIntervalSinceReferenceDate.bitPattern
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
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "BalanceCacheManager")
    static let shared = BalanceCacheManager()
    
    private var balanceCache: [String: BalanceCacheEntry] = [:]
    private var transactionsCache: [String: TransactionsCacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.cryptosavings.cache", attributes: .concurrent)
    private let persistenceQueue = DispatchQueue(label: "com.cryptosavings.cache.persistence", qos: .utility)
    
    // Cache duration in seconds (30 minutes default for balances - increased to reduce API calls)
    private let balanceCacheDuration: TimeInterval = 30 * 60
    
    // Cache duration for transactions (2 hours - transactions change less frequently)
    private let transactionsCacheDuration: TimeInterval = 2 * 60 * 60
    
    // Versioned storage prevents balances normalized with obsolete API semantics
    // from surviving an app upgrade and bypassing the corrected parser.
    private let balanceCacheStorageKey = "com.cryptosavings.balance.cache.v5"
    private let obsoleteBalanceCacheStorageKeys = [
        "com.cryptosavings.balance.cache",
        "com.cryptosavings.balance.cache.v2",
        "com.cryptosavings.balance.cache.v3",
        "com.cryptosavings.balance.cache.v4"
    ]
    
    private init() {
        for key in obsoleteBalanceCacheStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

    /// Reads the same unexpired cache state used by operational balance calculations.
    /// This method is synchronous and never refreshes the provider.
    func balanceSnapshotEvidence(for key: String) -> BalanceCacheSnapshotEvidence? {
        cacheQueue.sync {
            guard let entry = balanceCache[key], !entry.isExpired else {
                return nil
            }
            return BalanceCacheSnapshotEvidence(cacheKey: key, entry: entry)
        }
    }
    
    // Get cached balance without expiry check (for fallback scenarios)
    func getFallbackBalance(for key: String) -> Double? {
        cacheQueue.sync {
            return balanceCache[key]?.balance
        }
    }
    
    func cacheBalance(
        _ balance: Double,
        for key: String,
        timestamp: Date = Date(),
        expiresAt: Date? = nil
    ) {
        // Update in-memory cache synchronously so operational readers can use
        // the newly authoritative value immediately after a successful refresh.
        let entry = BalanceCacheEntry(
            balance: balance,
            timestamp: timestamp,
            expiresAt: expiresAt ?? timestamp.addingTimeInterval(self.balanceCacheDuration)
        )
        var balanceSnapshot: [String: BalanceCacheEntry] = [:]
        cacheQueue.sync(flags: .barrier) {
            self.balanceCache[key] = entry
            balanceSnapshot = self.balanceCache
        }
        Self.log.info("Cached balance \(balance, privacy: .public) for key: \(key, privacy: .public)")

        // Persist on a separate queue. Keeping disk I/O off `cacheQueue` prevents UI reads
        // from waiting behind UserDefaults serialization.
        persistenceQueue.async {
            self.persistCache(balanceSnapshot)
            Self.log.info("Persisted \(balanceSnapshot.count, privacy: .public) entries to disk")
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
        cacheQueue.sync(flags: .barrier) {
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
        let normalizedAddress = OnChainIdentifierPolicy.normalizedAddress(
            address,
            forChainIdentifier: chainId
        )
        return [
            "balance_v5",
            chainId.lowercased(),
            normalizedAddress,
            symbol.lowercased()
        ].joined(separator: "_")
    }
    
    // Generate cache key for transactions
    static func transactionsCacheKey(chainId: String, address: String, currency: String? = nil) -> String {
        let normalizedAddress = OnChainIdentifierPolicy.normalizedAddress(
            address,
            forChainIdentifier: chainId
        )
        if let currency = currency {
            return [
                "transactions_v4",
                chainId.lowercased(),
                normalizedAddress,
                currency.lowercased()
            ].joined(separator: "_")
        } else {
            return [
                "transactions_v4",
                chainId.lowercased(),
                normalizedAddress
            ].joined(separator: "_")
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedCache() {
        cacheQueue.sync(flags: .barrier) {
            if let data = UserDefaults.standard.data(forKey: self.balanceCacheStorageKey),
               let decodedCache = try? JSONDecoder().decode([String: BalanceCacheEntry].self, from: data) {
                // Only load non-expired entries or entries less than 24 hours old
                let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
                self.balanceCache = decodedCache.filter { entry in
                    // Keep if not expired OR if it was cached within last 24 hours
                    !entry.value.isExpired || entry.value.timestamp > oneDayAgo
                }
                Self.log.info("Loaded \(self.balanceCache.count, privacy: .public) cached balances from disk")
            } else {
                Self.log.info("No persisted cache found on disk")
            }
        }
    }
    
    private func persistCache(_ snapshot: [String: BalanceCacheEntry]) {
        if let encoded = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(encoded, forKey: self.balanceCacheStorageKey)
        }
    }
}
