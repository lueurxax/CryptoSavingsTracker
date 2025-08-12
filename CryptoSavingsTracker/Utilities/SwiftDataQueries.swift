//
//  SwiftDataQueries.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation
import SwiftData

/// Optimized query descriptors for SwiftData models
struct SwiftDataQueries {
    
    // MARK: - Goal Queries
    
    /// Fetch active goals sorted by deadline (nearest first)
    static func activeGoals() -> FetchDescriptor<Goal> {
        FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.archivedDate == nil
            },
            sortBy: [
                SortDescriptor(\.deadline, order: .forward)
            ]
        )
    }
    
    /// Fetch urgent goals (deadline within 7 days)
    static func urgentGoals() -> FetchDescriptor<Goal> {
        let sevenDaysFromNow = Date().addingTimeInterval(7 * 24 * 60 * 60)
        return FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.archivedDate == nil &&
                goal.deadline <= sevenDaysFromNow &&
                goal.deadline >= Date()
            },
            sortBy: [
                SortDescriptor(\.deadline, order: .forward)
            ]
        )
    }
    
    /// Fetch achieved goals
    static func achievedGoals() -> FetchDescriptor<Goal> {
        FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.archivedDate == nil &&
                goal.manualTotal >= goal.targetAmount
            },
            sortBy: [
                SortDescriptor(\.lastModifiedDate, order: .reverse)
            ]
        )
    }
    
    /// Fetch goals by currency
    static func goalsByCurrency(_ currency: String) -> FetchDescriptor<Goal> {
        FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.archivedDate == nil &&
                goal.currency == currency
            },
            sortBy: [
                SortDescriptor(\.deadline, order: .forward)
            ]
        )
    }
    
    /// Fetch goals with reminders enabled
    static func goalsWithReminders() -> FetchDescriptor<Goal> {
        FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.archivedDate == nil &&
                goal.reminderFrequency != nil
            },
            sortBy: [
                SortDescriptor(\.reminderTime, order: .forward)
            ]
        )
    }
    
    /// Fetch goals modified recently (last 7 days)
    static func recentlyModifiedGoals() -> FetchDescriptor<Goal> {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.lastModifiedDate >= sevenDaysAgo
            },
            sortBy: [
                SortDescriptor(\.lastModifiedDate, order: .reverse)
            ]
        )
    }
    
    // MARK: - Asset Queries
    
    /// Fetch assets with on-chain addresses
    static func assetsWithOnChainAddresses() -> FetchDescriptor<Asset> {
        FetchDescriptor<Asset>(
            predicate: #Predicate { asset in
                asset.address != nil &&
                asset.chainId != nil
            }
        )
    }
    
    /// Fetch assets by currency
    static func assetsByCurrency(_ currency: String) -> FetchDescriptor<Asset> {
        FetchDescriptor<Asset>(
            predicate: #Predicate { asset in
                asset.currency == currency
            }
        )
    }
    
    /// Fetch assets for a specific goal
    static func assetsForGoal(goalId: UUID) -> FetchDescriptor<Asset> {
        FetchDescriptor<Asset>(
            predicate: #Predicate { asset in
                asset.goal.id == goalId
            }
        )
    }
    
    // MARK: - Transaction Queries
    
    /// Fetch recent transactions (last 30 days)
    static func recentTransactions() -> FetchDescriptor<Transaction> {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.date >= thirtyDaysAgo
            },
            sortBy: [
                SortDescriptor(\.date, order: .reverse)
            ]
        )
    }
    
    /// Fetch transactions for a specific asset
    static func transactionsForAsset(assetId: UUID) -> FetchDescriptor<Transaction> {
        FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.asset.id == assetId
            },
            sortBy: [
                SortDescriptor(\.date, order: .reverse)
            ]
        )
    }
    
    /// Fetch large transactions (above threshold)
    static func largeTransactions(threshold: Double) -> FetchDescriptor<Transaction> {
        FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                abs(transaction.amount) >= threshold
            },
            sortBy: [
                SortDescriptor(\.amount, order: .reverse)
            ]
        )
    }
    
    /// Fetch transactions with comments
    static func transactionsWithComments() -> FetchDescriptor<Transaction> {
        FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.comment != nil &&
                transaction.comment != ""
            },
            sortBy: [
                SortDescriptor(\.date, order: .reverse)
            ]
        )
    }
    
    // MARK: - Batch Fetching
    
    /// Configuration for batch fetching
    struct BatchConfiguration {
        let batchSize: Int
        let prefetchingEnabled: Bool
        
        static let `default` = BatchConfiguration(
            batchSize: 50,
            prefetchingEnabled: true
        )
        
        static let large = BatchConfiguration(
            batchSize: 100,
            prefetchingEnabled: true
        )
        
        static let small = BatchConfiguration(
            batchSize: 20,
            prefetchingEnabled: false
        )
    }
    
    /// Apply batch configuration to a descriptor
    static func applyBatchConfiguration<T: PersistentModel>(
        to descriptor: FetchDescriptor<T>,
        configuration: BatchConfiguration
    ) -> FetchDescriptor<T> {
        var updatedDescriptor = descriptor
        updatedDescriptor.fetchLimit = configuration.batchSize
        return updatedDescriptor
    }
}

// MARK: - Query Performance Monitoring

final class QueryPerformanceMonitor {
    static let shared = QueryPerformanceMonitor()
    
    private var queryTimes: [String: TimeInterval] = [:]
    private let queue = DispatchQueue(label: "com.cryptosavingstracker.querymonitor")
    
    func measureQuery<T>(_ name: String, block: () async throws -> T) async throws -> T {
        let startTime = Date()
        
        do {
            let result = try await block()
            let elapsed = Date().timeIntervalSince(startTime)
            
            queue.async {
                self.queryTimes[name] = elapsed
                
                if elapsed > 0.5 {
                    AppLog.warning("Slow query '\(name)': \(String(format: "%.3f", elapsed))s", category: .performance)
                } else {
                    AppLog.debug("Query '\(name)': \(String(format: "%.3f", elapsed))s", category: .performance)
                }
            }
            
            return result
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            
            queue.async {
                AppLog.error("Query '\(name)' failed after \(String(format: "%.3f", elapsed))s: \(error)", category: .performance)
            }
            
            throw error
        }
    }
    
    func getAverageQueryTime(for name: String) -> TimeInterval? {
        queue.sync {
            return queryTimes[name]
        }
    }
    
    func reset() {
        queue.async {
            self.queryTimes.removeAll()
        }
    }
}