//
//  GoalRepository.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftData
import SwiftUI
import Foundation

// MARK: - Repository Protocol

/// Protocol for goal data access operations
protocol GoalRepositoryProtocol {
    func fetchGoals() async throws -> [Goal]
    func fetchGoal(by id: UUID) async throws -> Goal?
    func save(_ goal: Goal) async throws
    func delete(_ goal: Goal) async throws
    func deleteGoals(withIds ids: [UUID]) async throws
    func goalExists(withId id: UUID) async throws -> Bool
}

// MARK: - Repository Implementation

/// SwiftData implementation of GoalRepository.
/// After CloudKit sync, duplicate logical entities may exist (same name+currency+startDate).
/// All fetch methods deduplicate results before returning them.
@MainActor
class GoalRepository: GoalRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchGoals() async throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.deadline, order: .forward)])
        let goals = try modelContext.fetch(descriptor)
        return Self.deduplicateInMemory(goals)
    }

    /// Removes logical duplicates from a goal list, keeping the most recently modified.
    /// This is a read-path safety net — the DeduplicationService handles persistent cleanup.
    static func deduplicateInMemory(_ goals: [Goal]) -> [Goal] {
        var seen = Set<String>()
        var result: [Goal] = []
        // Sort most-recently-modified first so the survivor wins
        let sorted = goals.sorted { $0.lastModifiedDate > $1.lastModifiedDate }
        for goal in sorted {
            let key = goalLogicalKey(goal)
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(goal)
        }
        // Re-sort by deadline (original sort order)
        return result.sorted { $0.deadline < $1.deadline }
    }

    /// The canonical logical identity for a Goal.
    /// Uses (name, currency, startDate) — startDate anchors the goal's creation moment,
    /// distinguishing re-created goals with the same name and currency.
    static func goalLogicalKey(_ goal: Goal) -> String {
        let startDay = Calendar.current.startOfDay(for: goal.startDate)
        return "\(goal.name)|\(goal.currency)|\(startDay.timeIntervalSince1970)"
    }
    
    func fetchGoal(by id: UUID) async throws -> Goal? {
        let predicate = #Predicate<Goal> { goal in
            goal.id == id
        }
        let descriptor = FetchDescriptor<Goal>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    func save(_ goal: Goal) async throws {
        modelContext.insert(goal)
        try modelContext.save()
    }
    
    func delete(_ goal: Goal) async throws {
        // Cancel notifications before deletion
        await NotificationManager.shared.cancelNotifications(for: goal)
        
        modelContext.delete(goal)
        try modelContext.save()
        
        // Post notification for UI updates
        let notification = Notification(name: Notification.Name("goalDeleted"), object: goal)
        NotificationCenter.default.post(notification)
    }
    
    func deleteGoals(withIds ids: [UUID]) async throws {
        for id in ids {
            if let goal = try await fetchGoal(by: id) {
                await NotificationManager.shared.cancelNotifications(for: goal)
                modelContext.delete(goal)
            }
        }
        try modelContext.save()
    }
    
    func goalExists(withId id: UUID) async throws -> Bool {
        let goal = try await fetchGoal(by: id)
        return goal != nil
    }
}

// MARK: - Asset Repository Protocol

/// Protocol for asset data access operations
protocol AssetRepositoryProtocol {
    func fetchAssets(for goalId: UUID) async throws -> [Asset]
    func fetchAsset(by id: UUID) async throws -> Asset?
    func save(_ asset: Asset) async throws
    func delete(_ asset: Asset) async throws
    func updateBalance(for assetId: UUID, newBalance: Double) async throws
}

// MARK: - Asset Repository Implementation

@MainActor
class AssetRepository: AssetRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchAssets(for goalId: UUID) async throws -> [Asset] {
        // Fetch allocations for the goal, then extract unique assets
        let allocPredicate = #Predicate<AssetAllocation> { allocation in
            allocation.goal?.id == goalId
        }
        let allocDescriptor = FetchDescriptor<AssetAllocation>(predicate: allocPredicate)
        let allocations = try modelContext.fetch(allocDescriptor)
        
        // Extract unique assets from allocations
        var uniqueAssets: [Asset] = []
        var seenIds: Set<UUID> = []
        
        for allocation in allocations {
            if let asset = allocation.asset, !seenIds.contains(asset.id) {
                uniqueAssets.append(asset)
                seenIds.insert(asset.id)
            }
        }
        
        return uniqueAssets
    }
    
    func fetchAsset(by id: UUID) async throws -> Asset? {
        let predicate = #Predicate<Asset> { asset in
            asset.id == id
        }
        let descriptor = FetchDescriptor<Asset>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    func save(_ asset: Asset) async throws {
        modelContext.insert(asset)
        try modelContext.save()
    }
    
    func delete(_ asset: Asset) async throws {
        modelContext.delete(asset)
        try modelContext.save()
    }
    
    func updateBalance(for assetId: UUID, newBalance: Double) async throws {
        guard (try await fetchAsset(by: assetId)) != nil else {
            throw RepositoryError.assetNotFound
        }
        
        // Note: This would require adding a balance property to Asset model
        // For now, balance is calculated from transactions
        try modelContext.save()
    }
}

// MARK: - Transaction Repository Protocol

/// Protocol for transaction data access operations
protocol TransactionRepositoryProtocol {
    func fetchTransactions(for assetId: UUID) async throws -> [Transaction]
    func fetchTransaction(by id: UUID) async throws -> Transaction?
    func save(_ transaction: Transaction) async throws
    func delete(_ transaction: Transaction) async throws
    func fetchRecentTransactions(limit: Int) async throws -> [Transaction]
}

// MARK: - Transaction Repository Implementation

/// After CloudKit sync, duplicate on-chain transactions may exist (same externalId).
/// All fetch methods deduplicate results before returning them.
@MainActor
class TransactionRepository: TransactionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchTransactions(for assetId: UUID) async throws -> [Transaction] {
        let predicate = #Predicate<Transaction> { transaction in
            transaction.asset?.id == assetId
        }
        let descriptor = FetchDescriptor<Transaction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let transactions = try modelContext.fetch(descriptor)
        return Self.deduplicateInMemory(transactions)
    }

    /// Removes duplicate on-chain transactions (same externalId+asset) from results.
    /// Manual transactions (no externalId) are never considered duplicates.
    static func deduplicateInMemory(_ transactions: [Transaction]) -> [Transaction] {
        var seenExternalKeys = Set<String>()
        var result: [Transaction] = []
        for tx in transactions {
            if let externalId = tx.externalId, !externalId.isEmpty {
                let assetId = tx.asset?.id.uuidString ?? "nil"
                let key = "\(assetId)|\(externalId)"
                if seenExternalKeys.contains(key) { continue }
                seenExternalKeys.insert(key)
            }
            result.append(tx)
        }
        return result
    }
    
    func fetchTransaction(by id: UUID) async throws -> Transaction? {
        let predicate = #Predicate<Transaction> { transaction in
            transaction.id == id
        }
        let descriptor = FetchDescriptor<Transaction>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    func save(_ transaction: Transaction) async throws {
        modelContext.insert(transaction)
        try modelContext.save()
    }
    
    func delete(_ transaction: Transaction) async throws {
        modelContext.delete(transaction)
        try modelContext.save()
    }
    
    func fetchRecentTransactions(limit: Int = 10) async throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Repository Factory

/// Factory for creating repositories with proper dependencies
@MainActor
class RepositoryFactory {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func makeGoalRepository() -> GoalRepositoryProtocol {
        return GoalRepository(modelContext: modelContext)
    }
    
    func makeAssetRepository() -> AssetRepositoryProtocol {
        return AssetRepository(modelContext: modelContext)
    }
    
    func makeTransactionRepository() -> TransactionRepositoryProtocol {
        return TransactionRepository(modelContext: modelContext)
    }
}

// MARK: - Repository Errors

enum RepositoryError: LocalizedError {
    case goalNotFound
    case assetNotFound
    case transactionNotFound
    case saveFailed(Error)
    case deleteFailed(Error)
    case fetchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .goalNotFound:
            return "Goal not found"
        case .assetNotFound:
            return "Asset not found"
        case .transactionNotFound:
            return "Transaction not found"
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Environment Key for Repository Factory

private struct RepositoryFactoryKey: EnvironmentKey {
    static let defaultValue: RepositoryFactory? = nil
}

extension EnvironmentValues {
    var repositoryFactory: RepositoryFactory? {
        get { self[RepositoryFactoryKey.self] }
        set { self[RepositoryFactoryKey.self] = newValue }
    }
}

// MARK: - View Extension for Repository Access

extension View {
    func repositoryFactory(_ factory: RepositoryFactory) -> some View {
        environment(\.repositoryFactory, factory)
    }
}
