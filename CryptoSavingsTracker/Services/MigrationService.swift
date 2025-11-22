//
//  MigrationService.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 25/08/2025.
//

import SwiftData
import Foundation

/// Simple schema versioning
enum SchemaVersion: Int, Comparable {
    case v1 = 1  // Direct Asset->Goal relationship
    case v2 = 2  // AssetAllocation join table (percentage-based)
    case v3 = 3  // Fixed-amount allocations
    case v4 = 4  // Execution tracking (executionRecordId in Contribution)

    static var latest: SchemaVersion { .v4 }

    static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Service responsible for handling data migrations between schema versions
@MainActor
class MigrationService {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Check if migration is needed and perform it
    func performMigrationIfNeeded() async throws {
        let currentVersion = getCurrentSchemaVersion()
        let targetVersion = SchemaVersion.latest

        if currentVersion < targetVersion {
            print("Migration needed from version \(currentVersion.rawValue) to \(targetVersion.rawValue)")

            // Perform migrations in sequence
            if currentVersion < .v2 {
                try await migrateToV2()
            }
            if currentVersion < .v3 {
                try await migrateToV3()
            }
            if currentVersion < .v4 {
                try await migrateToV4()
            }

            setSchemaVersion(targetVersion)
        }
    }
    
    /// Migrate from V1 (direct Asset->Goal relationship) to V2 (AssetAllocation join table)
    private func migrateToV2() async throws {
        print("Starting migration to V2 (AssetAllocation model)")
        
        // For this implementation, we'll assume that existing assets need to be migrated
        // In a production app, you would preserve the old relationship data during migration
        
        // Get all existing assets and goals
        let assetDescriptor = FetchDescriptor<Asset>()
        let existingAssets = try modelContext.fetch(assetDescriptor)
        
        let goalDescriptor = FetchDescriptor<Goal>()
        let existingGoals = try modelContext.fetch(goalDescriptor)
        
        var migratedCount = 0
        
        // Since we can't access the old asset.goal relationship (it's been removed),
        // we'll create a simple migration strategy:
        // 1. If there's only one goal, assign all assets to it with 100% allocation
        // 2. If there are multiple goals, leave unallocated and require user to manually allocate
        
        if existingGoals.count == 1, let singleGoal = existingGoals.first {
            // Simple case: one goal exists, allocate all assets to it
            for asset in existingAssets {
                if asset.allocations.isEmpty {
                    let allocation = AssetAllocation(asset: asset, goal: singleGoal, percentage: 1.0)
                    modelContext.insert(allocation)
                    migratedCount += 1
                    print("Migrated asset \(asset.currency) to goal \(singleGoal.name) with 100% allocation")
                }
            }
        } else {
            // Multiple goals or no goals: leave assets unallocated for manual allocation
            print("Multiple goals detected. Assets will remain unallocated and require manual allocation.")
        }
        
        // Save all the new allocations
        try modelContext.save()
        print("Migration completed. Created \(migratedCount) allocations.")
        
        // Set migration completed flag
        UserDefaults.standard.set(true, forKey: "V2MigrationCompleted")
    }

    /// Migrate from V2 (percentage-based allocations) to V3 (fixed-amount allocations)
    /// NOTE: V3 migration removed - we're staying with percentage-based allocations
    private func migrateToV3() async throws {
        print("Skipping V3 migration - percentage-based allocations are current architecture")
        // V3 migration is no longer needed after architecture rollback
        // AllocationMigrationService was removed
    }

    /// Migrate from V3 to V4 (add executionRecordId to Contribution)
    private func migrateToV4() async throws {
        print("Starting migration to V4 (execution tracking)")

        // The executionRecordId field is optional, so existing Contribution records
        // don't need any data transformation - they'll just have nil values
        // This migration is essentially a no-op for data, but we track it for versioning

        let descriptor = FetchDescriptor<Contribution>()
        let contributions = try modelContext.fetch(descriptor)

        print("Migration to V4 completed. \(contributions.count) existing contributions will have nil executionRecordId.")
        print("✓ Contribution model now supports execution tracking")

        // Set migration completed flag
        UserDefaults.standard.set(true, forKey: "V4MigrationCompleted")
    }

    /// Get the current schema version from UserDefaults
    private func getCurrentSchemaVersion() -> SchemaVersion {
        let version = UserDefaults.standard.integer(forKey: "SchemaVersion")
        return SchemaVersion(rawValue: version) ?? .v1
    }
    
    /// Set the current schema version in UserDefaults
    private func setSchemaVersion(_ version: SchemaVersion) {
        UserDefaults.standard.set(version.rawValue, forKey: "SchemaVersion")
    }
}

/// Extension to support migration detection
extension MigrationService {
    
    /// Check if any assets exist without allocations (indicates need for migration)
    func needsMigration() throws -> Bool {
        let assetDescriptor = FetchDescriptor<Asset>()
        let assets = try modelContext.fetch(assetDescriptor)
        
        // If there are assets but no allocations, we likely need migration
        if !assets.isEmpty {
            let allocationDescriptor = FetchDescriptor<AssetAllocation>()
            let allocations = try modelContext.fetch(allocationDescriptor)
            
            if allocations.isEmpty {
                return true
            }
        }
        
        return false
    }
}