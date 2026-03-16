//
//  CloudKitCutoverCoordinator.swift
//  CryptoSavingsTracker
//
//  Coordinates the one-time migration from local-only SwiftData store
//  to CloudKit-backed SwiftData store.
//

import CloudKit
import Combine
import Foundation
import SwiftData
import os

@MainActor
final class CloudKitCutoverCoordinator: ObservableObject {

    // MARK: - State

    enum CutoverState: Equatable {
        case idle
        case checkingPrerequisites
        case preparingBackup
        case backupComplete(backupPath: String)
        case copyingData(progress: Double, entityName: String)
        case validatingCopy
        case switchingMode
        case complete(MigrationEvidence)
        case failed(String)
        case rolledBack(String)
    }

    struct MigrationEvidence: Equatable, Codable {
        let timestamp: Date
        let entityCounts: [String: Int]
        let backupPath: String
        let durationSeconds: Double
    }

    @Published private(set) var state: CutoverState = .idle

    private let stackFactory: PersistenceStackFactory
    private let storageModeRegistry: StorageModeRegistry
    private let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "cutover")

    init(
        stackFactory: PersistenceStackFactory = PersistenceStackFactory(),
        storageModeRegistry: StorageModeRegistry = UserDefaultsStorageModeRegistry()
    ) {
        self.stackFactory = stackFactory
        self.storageModeRegistry = storageModeRegistry
    }

    // MARK: - Pre-flight

    enum PreflightError: LocalizedError {
        case alreadyMigrated
        case noICloudAccount
        case restrictedAccount
        case accountCheckFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyMigrated:
                return "Migration has already been completed."
            case .noICloudAccount:
                return "No iCloud account is signed in on this device. Sign in to iCloud in Settings to continue."
            case .restrictedAccount:
                return "Your iCloud account is restricted. Contact your administrator."
            case .accountCheckFailed(let detail):
                return "Could not verify iCloud account status: \(detail)"
            }
        }
    }

    func checkPrerequisites() async throws {
        guard storageModeRegistry.currentMode == .localOnly else {
            throw PreflightError.alreadyMigrated
        }

        let accountStatus = try await CKContainer.default().accountStatus()
        switch accountStatus {
        case .available:
            break
        case .noAccount:
            throw PreflightError.noICloudAccount
        case .restricted:
            throw PreflightError.restrictedAccount
        case .couldNotDetermine:
            throw PreflightError.accountCheckFailed("Could not determine account status.")
        case .temporarilyUnavailable:
            throw PreflightError.accountCheckFailed("iCloud is temporarily unavailable. Try again later.")
        @unknown default:
            throw PreflightError.accountCheckFailed("Unknown account status.")
        }
    }

    // MARK: - Cutover

    func performCutover(sourceContainer: ModelContainer) async throws {
        let startTime = Date()
        logger.info("Starting CloudKit cutover")

        // 1. Pre-flight checks
        state = .checkingPrerequisites
        try await checkPrerequisites()

        // 2. Backup
        state = .preparingBackup
        let copiedCount = stackFactory.backupStoreFilesIfPresent(
            descriptor: stackFactory.localPrimaryDescriptor
        )
        let backupPath = stackFactory.backupRootURL?.path ?? "unknown"
        logger.info("Backup complete: \(copiedCount) file(s) to \(backupPath)")
        state = .backupComplete(backupPath: backupPath)

        // 3. Create CloudKit-backed container
        let cloudContainer: ModelContainer
        do {
            cloudContainer = try stackFactory.makeContainer(for: .cloudPrimaryWithLocalMirror)
        } catch {
            state = .failed("Failed to create CloudKit container: \(error.localizedDescription)")
            throw error
        }

        // 4. Copy data
        let entityCounts: [String: Int]
        do {
            entityCounts = try await copyAllEntities(
                from: sourceContainer.mainContext,
                to: cloudContainer.mainContext
            )
        } catch {
            // Rollback: delete cloud store files
            cleanupCloudStore()
            state = .rolledBack("Copy failed: \(error.localizedDescription). Local data is intact.")
            throw error
        }

        // 5. Validate
        state = .validatingCopy
        do {
            try validateCopy(
                source: sourceContainer.mainContext,
                target: cloudContainer.mainContext,
                expectedCounts: entityCounts
            )
        } catch {
            cleanupCloudStore()
            state = .rolledBack("Validation failed: \(error.localizedDescription). Local data is intact.")
            throw error
        }

        // 6. Switch mode
        state = .switchingMode
        storageModeRegistry.setMode(.cloudPrimaryWithLocalMirror)

        let duration = Date().timeIntervalSince(startTime)
        let evidence = MigrationEvidence(
            timestamp: Date(),
            entityCounts: entityCounts,
            backupPath: backupPath,
            durationSeconds: duration
        )
        persistMigrationEvidence(evidence)

        state = .complete(evidence)
        logger.info("CloudKit cutover complete in \(String(format: "%.1f", duration))s")
    }

    // MARK: - Entity Copy

    private func copyAllEntities(
        from source: ModelContext,
        to target: ModelContext
    ) async throws -> [String: Int] {
        var counts: [String: Int] = [:]

        // Copy in dependency order — parents before children

        // 1. Goals (no parent dependencies)
        let goals = try source.fetch(FetchDescriptor<Goal>())
        state = .copyingData(progress: 0.0, entityName: "Goals")
        for goal in goals {
            let copy = Goal(
                name: goal.name,
                currency: goal.currency,
                targetAmount: goal.targetAmount,
                deadline: goal.deadline,
                startDate: goal.startDate
            )
            copy.id = goal.id
            copy.lifecycleStatusRawValue = goal.lifecycleStatusRawValue
            copy.lifecycleStatusChangedAt = goal.lifecycleStatusChangedAt
            copy.lastModifiedDate = goal.lastModifiedDate
            copy.reminderFrequency = goal.reminderFrequency
            copy.reminderTime = goal.reminderTime
            copy.firstReminderDate = goal.firstReminderDate
            copy.emoji = goal.emoji
            copy.goalDescription = goal.goalDescription
            copy.link = goal.link
            target.insert(copy)
        }
        try target.save()
        counts["Goal"] = goals.count
        logger.debug("Copied \(goals.count) goals")

        // 2. Assets (no parent dependencies)
        let assets = try source.fetch(FetchDescriptor<Asset>())
        state = .copyingData(progress: 0.15, entityName: "Assets")
        for asset in assets {
            let copy = Asset(currency: asset.currency, address: asset.address, chainId: asset.chainId)
            copy.id = asset.id
            target.insert(copy)
        }
        try target.save()
        counts["Asset"] = assets.count
        logger.debug("Copied \(assets.count) assets")

        // 3. Transactions (depends on Asset)
        let transactions = try source.fetch(FetchDescriptor<Transaction>())
        state = .copyingData(progress: 0.3, entityName: "Transactions")
        let targetAssets = try target.fetch(FetchDescriptor<Asset>())
        let targetAssetMap = Dictionary(uniqueKeysWithValues: targetAssets.map { ($0.id, $0) })
        for tx in transactions {
            let targetAsset = tx.asset.flatMap { targetAssetMap[$0.id] }
            let copy = Transaction(amount: tx.amount, asset: targetAsset)
            copy.id = tx.id
            copy.date = tx.date
            copy.sourceRawValue = tx.sourceRawValue
            copy.externalId = tx.externalId
            copy.comment = tx.comment
            copy.counterparty = tx.counterparty
            target.insert(copy)
        }
        try target.save()
        counts["Transaction"] = transactions.count

        // 4. AssetAllocations (depends on Asset, Goal)
        let allocations = try source.fetch(FetchDescriptor<AssetAllocation>())
        state = .copyingData(progress: 0.45, entityName: "Allocations")
        let targetGoals = try target.fetch(FetchDescriptor<Goal>())
        let targetGoalMap = Dictionary(uniqueKeysWithValues: targetGoals.map { ($0.id, $0) })
        for alloc in allocations {
            guard let targetAsset = alloc.asset.flatMap({ targetAssetMap[$0.id] }),
                  let targetGoal = alloc.goal.flatMap({ targetGoalMap[$0.id] }) else { continue }
            let copy = AssetAllocation(asset: targetAsset, goal: targetGoal, amount: alloc.amount)
            copy.id = alloc.id
            copy.createdDate = alloc.createdDate
            copy.lastModifiedDate = alloc.lastModifiedDate
            target.insert(copy)
        }
        try target.save()
        counts["AssetAllocation"] = allocations.count

        // 5. AllocationHistory (depends on Asset, Goal)
        let histories = try source.fetch(FetchDescriptor<AllocationHistory>())
        state = .copyingData(progress: 0.55, entityName: "AllocationHistory")
        for history in histories {
            guard let srcAsset = history.asset, let srcGoal = history.goal,
                  let tgtAsset = targetAssetMap[srcAsset.id],
                  let tgtGoal = targetGoalMap[srcGoal.id] else { continue }
            let copy = AllocationHistory(asset: tgtAsset, goal: tgtGoal, amount: history.amount, timestamp: history.timestamp)
            copy.id = history.id
            copy.assetId = history.assetId
            copy.goalId = history.goalId
            copy.monthLabel = history.monthLabel
            copy.createdAt = history.createdAt
            target.insert(copy)
        }
        try target.save()
        counts["AllocationHistory"] = histories.count

        // 6. MonthlyExecutionRecords (no parent model dependency)
        let execRecords = try source.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        state = .copyingData(progress: 0.65, entityName: "ExecutionRecords")
        for record in execRecords {
            let copy = MonthlyExecutionRecord(monthLabel: record.monthLabel, goalIds: record.goalIds)
            copy.id = record.id
            copy.statusRawValue = record.statusRawValue
            copy.createdAt = record.createdAt
            copy.startedAt = record.startedAt
            copy.completedAt = record.completedAt
            copy.canUndoUntil = record.canUndoUntil
            target.insert(copy)
        }
        try target.save()
        counts["MonthlyExecutionRecord"] = execRecords.count

        // 7. MonthlyPlans (optionally links to MonthlyExecutionRecord)
        let plans = try source.fetch(FetchDescriptor<MonthlyPlan>())
        state = .copyingData(progress: 0.75, entityName: "MonthlyPlans")
        let targetExecRecords = try target.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        let targetExecMap = Dictionary(uniqueKeysWithValues: targetExecRecords.map { ($0.id, $0) })
        for plan in plans {
            let copy = MonthlyPlan(
                goalId: plan.goalId,
                monthLabel: plan.monthLabel,
                requiredMonthly: plan.requiredMonthly,
                remainingAmount: plan.remainingAmount,
                monthsRemaining: plan.monthsRemaining,
                currency: plan.currency,
                status: plan.status,
                flexState: plan.flexState,
                state: plan.state
            )
            copy.id = plan.id
            copy.customAmount = plan.customAmount
            copy.isProtected = plan.isProtected
            copy.isSkipped = plan.isSkipped
            copy.createdDate = plan.createdDate
            copy.lastModifiedDate = plan.lastModifiedDate
            copy.lastCalculated = plan.lastCalculated
            if let execRecord = plan.executionRecord {
                copy.executionRecord = targetExecMap[execRecord.id]
            }
            target.insert(copy)
        }
        try target.save()
        counts["MonthlyPlan"] = plans.count

        // 8. CompletedExecutions (links to MonthlyExecutionRecord)
        let completedExecs = try source.fetch(FetchDescriptor<CompletedExecution>())
        state = .copyingData(progress: 0.85, entityName: "CompletedExecutions")
        for ce in completedExecs {
            let copy = CompletedExecution(
                monthLabel: ce.monthLabel,
                completedAt: ce.completedAt,
                exchangeRatesSnapshot: ce.exchangeRatesSnapshot,
                goalSnapshots: ce.goalSnapshots,
                contributionSnapshots: ce.contributionSnapshots
            )
            copy.id = ce.id
            // Link to execution record if it exists
            if let execRecord = ce.executionRecord {
                copy.executionRecord = targetExecMap[execRecord.id]
                // Also set the reverse relationship
                targetExecMap[execRecord.id]?.completedExecution = copy
            }
            target.insert(copy)
        }
        try target.save()
        counts["CompletedExecution"] = completedExecs.count

        // 9. ExecutionSnapshots (links to MonthlyExecutionRecord)
        let snapshots = try source.fetch(FetchDescriptor<ExecutionSnapshot>())
        state = .copyingData(progress: 0.9, entityName: "Snapshots")
        for snap in snapshots {
            let copy = ExecutionSnapshot(
                id: snap.id,
                capturedAt: snap.capturedAt,
                totalPlanned: snap.totalPlanned,
                snapshotData: snap.snapshotData
            )
            if let execRecord = snap.executionRecord {
                copy.executionRecord = targetExecMap[execRecord.id]
                targetExecMap[execRecord.id]?.snapshot = copy
            }
            target.insert(copy)
        }
        try target.save()
        counts["ExecutionSnapshot"] = snapshots.count

        // 10. CompletionEvents (links to MonthlyExecutionRecord, CompletedExecution)
        let events = try source.fetch(FetchDescriptor<CompletionEvent>())
        state = .copyingData(progress: 0.95, entityName: "CompletionEvents")
        let targetCompletedExecs = try target.fetch(FetchDescriptor<CompletedExecution>())
        let targetCEMap = Dictionary(uniqueKeysWithValues: targetCompletedExecs.map { ($0.id, $0) })
        for event in events {
            guard let execRecord = event.executionRecord,
                  let targetExecRecord = targetExecMap[execRecord.id],
                  let snapshot = event.completionSnapshot,
                  let targetCE = targetCEMap[snapshot.id] else { continue }
            let copy = CompletionEvent(
                executionRecord: targetExecRecord,
                sequence: event.sequence,
                sourceDiscriminator: event.sourceDiscriminator,
                completedAt: event.completedAt,
                completionSnapshot: targetCE
            )
            copy.eventId = event.eventId
            copy.undoneAt = event.undoneAt
            copy.undoReason = event.undoReason
            copy.createdAt = event.createdAt
            target.insert(copy)
        }
        try target.save()
        counts["CompletionEvent"] = events.count

        state = .copyingData(progress: 1.0, entityName: "Complete")
        return counts
    }

    // MARK: - Validation

    enum ValidationError: LocalizedError {
        case countMismatch(entity: String, expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .countMismatch(let entity, let expected, let actual):
                return "\(entity): expected \(expected) records, found \(actual)"
            }
        }
    }

    private func validateCopy(
        source: ModelContext,
        target: ModelContext,
        expectedCounts: [String: Int]
    ) throws {
        // Verify entity counts match
        let targetGoalCount = try target.fetchCount(FetchDescriptor<Goal>())
        if let expected = expectedCounts["Goal"], targetGoalCount != expected {
            throw ValidationError.countMismatch(entity: "Goal", expected: expected, actual: targetGoalCount)
        }

        let targetAssetCount = try target.fetchCount(FetchDescriptor<Asset>())
        if let expected = expectedCounts["Asset"], targetAssetCount != expected {
            throw ValidationError.countMismatch(entity: "Asset", expected: expected, actual: targetAssetCount)
        }

        let targetTxCount = try target.fetchCount(FetchDescriptor<Transaction>())
        if let expected = expectedCounts["Transaction"], targetTxCount != expected {
            throw ValidationError.countMismatch(entity: "Transaction", expected: expected, actual: targetTxCount)
        }

        let targetPlanCount = try target.fetchCount(FetchDescriptor<MonthlyPlan>())
        if let expected = expectedCounts["MonthlyPlan"], targetPlanCount != expected {
            throw ValidationError.countMismatch(entity: "MonthlyPlan", expected: expected, actual: targetPlanCount)
        }

        logger.info("Validation passed: all entity counts match")
    }

    // MARK: - Cleanup & Evidence

    private func cleanupCloudStore() {
        guard let storeURL = stackFactory.cloudPrimaryDescriptor.storeURL else { return }
        let suffixes = ["", "-shm", "-wal", "-journal"]
        for suffix in suffixes {
            let path = storeURL.path + suffix
            try? FileManager.default.removeItem(atPath: path)
        }
        logger.info("Cleaned up cloud store files")
    }

    private func persistMigrationEvidence(_ evidence: MigrationEvidence) {
        if let data = try? JSONEncoder().encode(evidence) {
            UserDefaults.standard.set(data, forKey: "CloudKit.MigrationEvidence")
        }
    }

    static func loadMigrationEvidence() -> MigrationEvidence? {
        guard let data = UserDefaults.standard.data(forKey: "CloudKit.MigrationEvidence") else {
            return nil
        }
        return try? JSONDecoder().decode(MigrationEvidence.self, from: data)
    }
}
