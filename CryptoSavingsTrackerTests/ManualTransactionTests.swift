//
//  ManualTransactionTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by Assistant on 06/08/2025.
//

import Foundation
import Testing
import SwiftData
@testable import CryptoSavingsTracker

@Suite("Manual Transaction Tests")
struct ManualTransactionTests {
    
    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    }
    
    @Test func manualTransactionRelationship() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create goal and asset
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        
        // Verify initial state
        #expect(asset.transactions.count == 0)
        #expect(asset.manualBalance == 0)
        
        // Add transaction
        let transaction = Transaction(amount: 0.5, asset: asset, comment: "Test transaction")
        asset.transactions.append(transaction)
        context.insert(transaction)
        try context.save()
        
        // Force context to refresh
        context.processPendingChanges()
        
        // Verify transaction was added
        #expect(asset.transactions.count == 1)
        #expect(asset.manualBalance == 0.5)
        #expect(transaction.asset.id == asset.id)
    }
    
    @Test func multipleManualTransactions() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        
        // Add multiple transactions
        let tx1 = Transaction(amount: 0.1, asset: asset, comment: "First")
        let tx2 = Transaction(amount: 0.2, asset: asset, comment: "Second")
        let tx3 = Transaction(amount: 0.3, asset: asset, comment: "Third")
        
        asset.transactions.append(tx1)
        asset.transactions.append(tx2)
        asset.transactions.append(tx3)
        
        context.insert(tx1)
        context.insert(tx2)
        context.insert(tx3)
        
        try context.save()
        context.processPendingChanges()
        
        #expect(asset.transactions.count == 3)
        #expect(asset.manualBalance == 0.6) // 0.1 + 0.2 + 0.3
    }
    
    @Test func manualAssetWithoutAddress() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal) // No address = manual only
        
        context.insert(goal)
        context.insert(asset)
        
        let transaction = Transaction(amount: 1.0, asset: asset, comment: "Manual BTC")
        asset.transactions.append(transaction)
        context.insert(transaction)
        
        try context.save()
        context.processPendingChanges()
        
        #expect(asset.address == nil)
        #expect(asset.chainId == nil)
        #expect(asset.manualBalance == 1.0)
        
        // Test async getCurrentAmount
        let currentAmount = await asset.getCurrentAmount()
        #expect(currentAmount == 1.0) // Should be manual balance only
    }
    
    @Test func deleteTransaction() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        
        // Add transactions
        let tx1 = Transaction(amount: 0.5, asset: asset, comment: "First transaction")
        let tx2 = Transaction(amount: 0.3, asset: asset, comment: "Second transaction")
        
        asset.transactions.append(tx1)
        asset.transactions.append(tx2)
        
        context.insert(tx1)
        context.insert(tx2)
        
        try context.save()
        context.processPendingChanges()
        
        // Verify initial state
        #expect(asset.transactions.count == 2)
        #expect(asset.manualBalance == 0.8) // 0.5 + 0.3
        
        // Delete first transaction
        if let txToDelete = asset.transactions.first {
            // Remove from relationship
            if let index = asset.transactions.firstIndex(where: { $0.id == txToDelete.id }) {
                asset.transactions.remove(at: index)
            }
            
            // Delete from context
            context.delete(txToDelete)
            try context.save()
            context.processPendingChanges()
        }
        
        // Verify deletion
        #expect(asset.transactions.count == 1)
        #expect(asset.manualBalance == 0.3) // Only second transaction remains
        
        // Verify the remaining transaction is the correct one
        if let remainingTransaction = asset.transactions.first {
            #expect(remainingTransaction.comment == "Second transaction")
            #expect(remainingTransaction.amount == 0.3)
        }
    }
    
    @Test func deleteAllTransactions() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        
        // Add multiple transactions
        for i in 1...5 {
            let tx = Transaction(amount: Double(i) * 0.1, asset: asset, comment: "Transaction \(i)")
            asset.transactions.append(tx)
            context.insert(tx)
        }
        
        try context.save()
        context.processPendingChanges()
        
        // Verify initial state
        #expect(asset.transactions.count == 5)
        #expect(asset.manualBalance == 1.5) // 0.1 + 0.2 + 0.3 + 0.4 + 0.5
        
        // Delete all transactions
        let transactionsToDelete = Array(asset.transactions)
        for transaction in transactionsToDelete {
            if let index = asset.transactions.firstIndex(where: { $0.id == transaction.id }) {
                asset.transactions.remove(at: index)
            }
            context.delete(transaction)
        }
        
        try context.save()
        context.processPendingChanges()
        
        // Verify all deleted
        #expect(asset.transactions.count == 0)
        #expect(asset.manualBalance == 0.0)
    }
}