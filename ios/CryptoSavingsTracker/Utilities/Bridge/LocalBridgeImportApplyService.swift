import Foundation
import SwiftData

enum BridgeImportApplyDisposition: String, Codable, Equatable, Sendable {
    case applied
    case acceptedAlreadyApplied
}

struct BridgeImportReceipt: Codable, Equatable, Sendable {
    let packageID: String
    let editedDatasetFingerprint: String
    let appliedAt: Date
    let sourceDeviceName: String?
    let sourceDeviceFingerprint: String?
}

struct BridgeImportApplyResult: Equatable, Sendable {
    let disposition: BridgeImportApplyDisposition
    let receipt: BridgeImportReceipt
    let entityCounts: [BridgeEntityCount]
}

protocol BridgeImportReceiptStoring {
    func receipt(for packageID: String) throws -> BridgeImportReceipt?
    func save(_ receipt: BridgeImportReceipt) throws
}

enum UserDefaultsBridgeImportReceiptStoreError: LocalizedError {
    case corruptStorage

    var errorDescription: String? {
        switch self {
        case .corruptStorage:
            return "Stored bridge import receipts are corrupt."
        }
    }
}

@MainActor
final class UserDefaultsBridgeImportReceiptStore: BridgeImportReceiptStoring {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "LocalBridge.ImportReceipts"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func receipt(for packageID: String) throws -> BridgeImportReceipt? {
        try loadReceipts()[packageID]
    }

    func save(_ receipt: BridgeImportReceipt) throws {
        var receipts = try loadReceipts()
        receipts[receipt.packageID] = receipt
        try persist(receipts)
    }

    private func loadReceipts() throws -> [String: BridgeImportReceipt] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: BridgeImportReceipt].self, from: data)
        } catch {
            throw UserDefaultsBridgeImportReceiptStoreError.corruptStorage
        }
    }

    private func persist(_ receipts: [String: BridgeImportReceipt]) throws {
        let data = try JSONEncoder().encode(receipts)
        userDefaults.set(data, forKey: storageKey)
    }
}

enum LocalBridgeImportApplyError: LocalizedError {
    case runtimeNotCloudKitPrimary
    case trustedDeviceRequired
    case trustedDeviceRevoked
    case packageNotApproved
    case invalidEditedDatasetFingerprint(expected: String, actual: String)
    case validationFailed([String])
    case receiptConflict(packageID: String)
    case malformedPackage([String])
    case unsupportedExecutionDetails([String])
    case applyPlanFingerprintMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotCloudKitPrimary:
            return "Local Bridge import apply is available only after CloudKit becomes the active authoritative runtime."
        case .trustedDeviceRequired:
            return "Bridge import apply requires an active trusted device."
        case .trustedDeviceRevoked:
            return "The sending bridge device is no longer trusted."
        case .packageNotApproved:
            return "Bridge import apply is blocked until operator review is explicitly approved."
        case let .invalidEditedDatasetFingerprint(expected, actual):
            return "Edited dataset fingerprint mismatch. Expected \(expected), got \(actual)."
        case let .validationFailed(issues):
            return issues.joined(separator: " ")
        case let .receiptConflict(packageID):
            return "Import receipt conflict for package \(packageID)."
        case let .malformedPackage(issues):
            return issues.joined(separator: " ")
        case let .unsupportedExecutionDetails(issues):
            return issues.joined(separator: " ")
        case let .applyPlanFingerprintMismatch(expected, actual):
            return "Bridge import apply would produce fingerprint \(actual), expected \(expected)."
        }
    }
}

@MainActor
final class LocalBridgeImportApplyService {
    private let persistenceController: PersistenceController
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let validationService: LocalBridgeImportValidationService
    private let receiptStore: BridgeImportReceiptStoring

    init(
        persistenceController: PersistenceController,
        snapshotExportService: LocalBridgeSnapshotExportService,
        validationService: LocalBridgeImportValidationService,
        receiptStore: BridgeImportReceiptStoring
    ) {
        self.persistenceController = persistenceController
        self.snapshotExportService = snapshotExportService
        self.validationService = validationService
        self.receiptStore = receiptStore
    }

    convenience init(
        snapshotExportService: LocalBridgeSnapshotExportService,
        validationService: LocalBridgeImportValidationService,
        receiptStore: BridgeImportReceiptStoring
    ) {
        self.init(
            persistenceController: .shared,
            snapshotExportService: snapshotExportService,
            validationService: validationService,
            receiptStore: receiptStore
        )
    }

    convenience init() {
        let exportService = LocalBridgeSnapshotExportService()
        self.init(
            persistenceController: .shared,
            snapshotExportService: exportService,
            validationService: LocalBridgeImportValidationService(snapshotExportService: exportService),
            receiptStore: UserDefaultsBridgeImportReceiptStore()
        )
    }

    func applyReviewedPackageToAuthoritativeDataset(
        _ package: SignedImportPackage,
        trustedDevice: TrustedBridgeDevice?,
        reviewStatus: BridgeImportReviewStatus
    ) throws -> BridgeImportApplyResult {
        guard persistenceController.activeMode == .cloudKitPrimary || persistenceController.activeMode == .cloudRollbackBlocked else {
            throw LocalBridgeImportApplyError.runtimeNotCloudKitPrimary
        }

        return try applyReviewedPackage(
            package,
            trustedDevice: trustedDevice,
            reviewStatus: reviewStatus,
            in: persistenceController.activeContainer
        )
    }

    func applyReviewedPackage(
        _ package: SignedImportPackage,
        trustedDevice: TrustedBridgeDevice?,
        reviewStatus: BridgeImportReviewStatus,
        in container: ModelContainer
    ) throws -> BridgeImportApplyResult {
        guard let trustedDevice else {
            throw LocalBridgeImportApplyError.trustedDeviceRequired
        }
        guard trustedDevice.trustState == .active else {
            throw LocalBridgeImportApplyError.trustedDeviceRevoked
        }
        guard reviewStatus.operatorDecision == .approved else {
            throw LocalBridgeImportApplyError.packageNotApproved
        }

        if let existingReceipt = try receiptStore.receipt(for: package.packageID) {
            guard existingReceipt.editedDatasetFingerprint == package.editedDatasetFingerprint else {
                throw LocalBridgeImportApplyError.receiptConflict(packageID: package.packageID)
            }

            return BridgeImportApplyResult(
                disposition: .acceptedAlreadyApplied,
                receipt: existingReceipt,
                entityCounts: package.snapshotEnvelope.entityCounts
            )
        }

        let embeddedFingerprint = try package.snapshotEnvelope.computedDatasetFingerprint()
        guard embeddedFingerprint == package.editedDatasetFingerprint else {
            throw LocalBridgeImportApplyError.invalidEditedDatasetFingerprint(
                expected: package.editedDatasetFingerprint,
                actual: embeddedFingerprint
            )
        }

        let currentSnapshot = try snapshotExportService.exportSnapshot(from: ModelContext(container))
        let freshReview = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: currentSnapshot
        )
        if !freshReview.blockingIssues.isEmpty {
            throw LocalBridgeImportApplyError.validationFailed(freshReview.blockingIssues)
        }

        let effectiveEnvelope = try normalizeEnvelopeForApply(
            package.snapshotEnvelope,
            currentSnapshot: currentSnapshot
        )
        try validatePackageShape(effectiveEnvelope)

        let writeContext = ModelContext(container)
        let indexes = try makeIndexes(in: writeContext)
        let applyPlan = try makeApplyPlan(for: effectiveEnvelope, using: indexes, in: writeContext)
        applyPlan.apply()
        writeContext.processPendingChanges()

        let predictedSnapshot = try snapshotExportService.exportSnapshot(from: writeContext)
        let expectedAuthoritativeEnvelope = try authoritativeEnvelopeAfterApply(effectiveEnvelope)
        guard predictedSnapshot.manifest.baseDatasetFingerprint == expectedAuthoritativeEnvelope.manifest.baseDatasetFingerprint else {
            throw LocalBridgeImportApplyError.applyPlanFingerprintMismatch(
                expected: expectedAuthoritativeEnvelope.manifest.baseDatasetFingerprint,
                actual: predictedSnapshot.manifest.baseDatasetFingerprint
            )
        }

        try writeContext.save()

        let receipt = BridgeImportReceipt(
            packageID: package.packageID,
            editedDatasetFingerprint: package.editedDatasetFingerprint,
            appliedAt: Date(),
            sourceDeviceName: freshReview.reviewSummaryDTO?.package.sourceDeviceName ?? trustedDevice.displayName,
            sourceDeviceFingerprint: freshReview.reviewSummaryDTO?.package.sourceDeviceFingerprint ?? trustedDevice.shortFingerprint
        )
        try receiptStore.save(receipt)

        return BridgeImportApplyResult(
            disposition: .applied,
            receipt: receipt,
            entityCounts: predictedSnapshot.entityCounts
        )
    }

    private func normalizeEnvelopeForApply(
        _ incoming: SnapshotEnvelope,
        currentSnapshot: SnapshotEnvelope
    ) throws -> SnapshotEnvelope {
        let goals = overlay(currentSnapshot.goals, with: incoming.goals, id: \.id)
        let assets = overlay(currentSnapshot.assets, with: incoming.assets, id: \.id)
        var transactions = overlay(currentSnapshot.transactions, with: incoming.transactions, id: \.id)
        var assetAllocations = overlay(currentSnapshot.assetAllocations, with: incoming.assetAllocations, id: \.id)
        var allocationHistories = overlay(currentSnapshot.allocationHistories, with: incoming.allocationHistories, id: \.id)
        var monthlyPlans = overlay(currentSnapshot.monthlyPlans, with: incoming.monthlyPlans, id: \.id)
        var monthlyExecutionRecords = overlay(currentSnapshot.monthlyExecutionRecords, with: incoming.monthlyExecutionRecords, id: \.id)
        var completedExecutions = overlay(currentSnapshot.completedExecutions, with: incoming.completedExecutions, id: \.id)
        var executionSnapshots = overlay(currentSnapshot.executionSnapshots, with: incoming.executionSnapshots, id: \.id)
        var completionEvents = overlay(currentSnapshot.completionEvents, with: incoming.completionEvents, id: \.eventId)

        let activeGoalIDs = Set(goals.values.filter { $0.recordState == .active }.map(\.id))
        let activeAssetIDs = Set(assets.values.filter { $0.recordState == .active }.map(\.id))

        transactions = Dictionary(uniqueKeysWithValues: transactions.values.map { snapshot in
            guard
                snapshot.recordState == .active,
                let assetId = snapshot.assetId,
                !activeAssetIDs.contains(assetId)
            else {
                return (snapshot.id, snapshot)
            }
            return (snapshot.id, deleted(snapshot))
        })

        assetAllocations = Dictionary(uniqueKeysWithValues: assetAllocations.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            guard
                let assetId = snapshot.assetId,
                let goalId = snapshot.goalId,
                activeAssetIDs.contains(assetId),
                activeGoalIDs.contains(goalId)
            else {
                return (snapshot.id, deleted(snapshot))
            }
            return (snapshot.id, snapshot)
        })

        allocationHistories = Dictionary(uniqueKeysWithValues: allocationHistories.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            let normalizedAssetID = snapshot.assetId.flatMap { activeAssetIDs.contains($0) ? $0 : nil }
            let normalizedGoalID = snapshot.goalId.flatMap { activeGoalIDs.contains($0) ? $0 : nil }
            return (
                snapshot.id,
                BridgeAllocationHistorySnapshot(
                    id: snapshot.id,
                    recordState: .active,
                    assetId: normalizedAssetID,
                    goalId: normalizedGoalID,
                    amount: snapshot.amount,
                    timestamp: snapshot.timestamp,
                    createdAt: snapshot.createdAt,
                    monthLabel: snapshot.monthLabel
                )
            )
        })

        let provisionalRecordIDs = Set(monthlyExecutionRecords.values.filter { $0.recordState == .active }.map(\.id))
        monthlyPlans = Dictionary(uniqueKeysWithValues: monthlyPlans.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            guard activeGoalIDs.contains(snapshot.goalId) else {
                return (snapshot.id, deleted(snapshot))
            }
            let normalizedExecutionRecordID = snapshot.executionRecordId.flatMap {
                provisionalRecordIDs.contains($0) ? $0 : nil
            }
            return (
                snapshot.id,
                BridgeMonthlyPlanSnapshot(
                    id: snapshot.id,
                    recordState: .active,
                    goalId: snapshot.goalId,
                    monthLabel: snapshot.monthLabel,
                    requiredMonthly: snapshot.requiredMonthly,
                    remainingAmount: snapshot.remainingAmount,
                    monthsRemaining: snapshot.monthsRemaining,
                    currency: snapshot.currency,
                    statusRawValue: snapshot.statusRawValue,
                    stateRawValue: snapshot.stateRawValue,
                    executionRecordId: normalizedExecutionRecordID,
                    flexStateRawValue: snapshot.flexStateRawValue,
                    customAmount: snapshot.customAmount,
                    isProtected: snapshot.isProtected,
                    isSkipped: snapshot.isSkipped,
                    createdDate: snapshot.createdDate,
                    lastModifiedDate: snapshot.lastModifiedDate
                )
            )
        })

        let activePlanIDs = Set(monthlyPlans.values.filter { $0.recordState == .active }.map(\.id))
        monthlyExecutionRecords = Dictionary(uniqueKeysWithValues: monthlyExecutionRecords.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            return (
                snapshot.id,
                BridgeMonthlyExecutionRecordSnapshot(
                    id: snapshot.id,
                    recordState: .active,
                    monthLabel: snapshot.monthLabel,
                    statusRawValue: snapshot.statusRawValue,
                    createdAt: snapshot.createdAt,
                    startedAt: snapshot.startedAt,
                    completedAt: snapshot.completedAt,
                    canUndoUntil: snapshot.canUndoUntil,
                    goalIds: snapshot.goalIds.filter { activeGoalIDs.contains($0) },
                    snapshotId: snapshot.snapshotId,
                    completedExecutionId: snapshot.completedExecutionId,
                    planIds: snapshot.planIds.filter { activePlanIDs.contains($0) },
                    completionEventIds: snapshot.completionEventIds
                )
            )
        })

        let activeRecordIDs = Set(monthlyExecutionRecords.values.filter { $0.recordState == .active }.map(\.id))
        executionSnapshots = Dictionary(uniqueKeysWithValues: executionSnapshots.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            guard activeRecordIDs.contains(snapshot.executionRecordId) else {
                return (snapshot.id, deleted(snapshot))
            }
            return (snapshot.id, snapshot)
        })
        completedExecutions = Dictionary(uniqueKeysWithValues: completedExecutions.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            guard activeRecordIDs.contains(snapshot.executionRecordId) else {
                return (snapshot.id, deleted(snapshot))
            }
            return (snapshot.id, snapshot)
        })

        let activeCompletedExecutionIDs = Set(completedExecutions.values.filter { $0.recordState == .active }.map(\.id))
        completionEvents = Dictionary(uniqueKeysWithValues: completionEvents.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.eventId, snapshot) }
            guard
                activeRecordIDs.contains(snapshot.executionRecordId),
                activeCompletedExecutionIDs.contains(snapshot.completionSnapshotId)
            else {
                return (snapshot.eventId, deleted(snapshot))
            }
            return (snapshot.eventId, snapshot)
        })

        let activeExecutionSnapshotIDs = Set(executionSnapshots.values.filter { $0.recordState == .active }.map(\.id))
        let activeCompletionEventIDs = Set(completionEvents.values.filter { $0.recordState == .active }.map(\.eventId))
        monthlyExecutionRecords = Dictionary(uniqueKeysWithValues: monthlyExecutionRecords.values.map { snapshot in
            guard snapshot.recordState == .active else { return (snapshot.id, snapshot) }
            return (
                snapshot.id,
                BridgeMonthlyExecutionRecordSnapshot(
                    id: snapshot.id,
                    recordState: .active,
                    monthLabel: snapshot.monthLabel,
                    statusRawValue: snapshot.statusRawValue,
                    createdAt: snapshot.createdAt,
                    startedAt: snapshot.startedAt,
                    completedAt: snapshot.completedAt,
                    canUndoUntil: snapshot.canUndoUntil,
                    goalIds: snapshot.goalIds.filter { activeGoalIDs.contains($0) },
                    snapshotId: snapshot.snapshotId.flatMap { activeExecutionSnapshotIDs.contains($0) ? $0 : nil },
                    completedExecutionId: snapshot.completedExecutionId.flatMap { activeCompletedExecutionIDs.contains($0) ? $0 : nil },
                    planIds: snapshot.planIds.filter { activePlanIDs.contains($0) },
                    completionEventIds: snapshot.completionEventIds.filter { activeCompletionEventIDs.contains($0) }
                )
            )
        })

        let normalizedEnvelope = SnapshotEnvelope(
            manifest: incoming.manifest.withBaseDatasetFingerprint(""),
            goals: goals.values.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: assets.values.sorted { $0.id.uuidString < $1.id.uuidString },
            transactions: transactions.values.sorted { $0.id.uuidString < $1.id.uuidString },
            assetAllocations: assetAllocations.values.sorted { $0.id.uuidString < $1.id.uuidString },
            allocationHistories: allocationHistories.values.sorted { $0.id.uuidString < $1.id.uuidString },
            monthlyPlans: monthlyPlans.values.sorted { $0.id.uuidString < $1.id.uuidString },
            monthlyExecutionRecords: monthlyExecutionRecords.values.sorted { $0.id.uuidString < $1.id.uuidString },
            completedExecutions: completedExecutions.values.sorted { $0.id.uuidString < $1.id.uuidString },
            executionSnapshots: executionSnapshots.values.sorted { $0.id.uuidString < $1.id.uuidString },
            completionEvents: completionEvents.values.sorted { $0.eventId.uuidString < $1.eventId.uuidString }
        )
        let normalizedManifest = SnapshotManifest(
            snapshotID: incoming.manifest.snapshotID,
            canonicalEncodingVersion: incoming.manifest.canonicalEncodingVersion,
            snapshotSchemaVersion: incoming.manifest.snapshotSchemaVersion,
            exportedAt: incoming.manifest.exportedAt,
            appModelSchemaVersion: incoming.manifest.appModelSchemaVersion,
            entityCounts: normalizedEnvelope.entityCounts,
            baseDatasetFingerprint: ""
        )
        return try SnapshotEnvelope(
            manifest: normalizedManifest,
            goals: normalizedEnvelope.goals,
            assets: normalizedEnvelope.assets,
            transactions: normalizedEnvelope.transactions,
            assetAllocations: normalizedEnvelope.assetAllocations,
            allocationHistories: normalizedEnvelope.allocationHistories,
            monthlyPlans: normalizedEnvelope.monthlyPlans,
            monthlyExecutionRecords: normalizedEnvelope.monthlyExecutionRecords,
            completedExecutions: normalizedEnvelope.completedExecutions,
            executionSnapshots: normalizedEnvelope.executionSnapshots,
            completionEvents: normalizedEnvelope.completionEvents
        ).withComputedFingerprint()
    }

    private func authoritativeEnvelopeAfterApply(_ envelope: SnapshotEnvelope) throws -> SnapshotEnvelope {
        let authoritativeManifest = SnapshotManifest(
            snapshotID: envelope.manifest.snapshotID,
            canonicalEncodingVersion: envelope.manifest.canonicalEncodingVersion,
            snapshotSchemaVersion: envelope.manifest.snapshotSchemaVersion,
            exportedAt: envelope.manifest.exportedAt,
            appModelSchemaVersion: envelope.manifest.appModelSchemaVersion,
            entityCounts: [],
            baseDatasetFingerprint: ""
        )

        let authoritativeEnvelope = SnapshotEnvelope(
            manifest: authoritativeManifest,
            goals: envelope.goals.filter { $0.recordState != .deleted },
            assets: envelope.assets.filter { $0.recordState != .deleted },
            transactions: envelope.transactions.filter { $0.recordState != .deleted },
            assetAllocations: envelope.assetAllocations.filter { $0.recordState != .deleted },
            allocationHistories: envelope.allocationHistories.filter { $0.recordState != .deleted },
            monthlyPlans: envelope.monthlyPlans.filter { $0.recordState != .deleted },
            monthlyExecutionRecords: envelope.monthlyExecutionRecords.filter { $0.recordState != .deleted },
            completedExecutions: envelope.completedExecutions.filter { $0.recordState != .deleted },
            executionSnapshots: envelope.executionSnapshots.filter { $0.recordState != .deleted },
            completionEvents: envelope.completionEvents.filter { $0.recordState != .deleted }
        )

        let normalizedManifest = SnapshotManifest(
            snapshotID: authoritativeEnvelope.manifest.snapshotID,
            canonicalEncodingVersion: authoritativeEnvelope.manifest.canonicalEncodingVersion,
            snapshotSchemaVersion: authoritativeEnvelope.manifest.snapshotSchemaVersion,
            exportedAt: authoritativeEnvelope.manifest.exportedAt,
            appModelSchemaVersion: authoritativeEnvelope.manifest.appModelSchemaVersion,
            entityCounts: authoritativeEnvelope.entityCounts,
            baseDatasetFingerprint: ""
        )

        return try SnapshotEnvelope(
            manifest: normalizedManifest,
            goals: authoritativeEnvelope.goals,
            assets: authoritativeEnvelope.assets,
            transactions: authoritativeEnvelope.transactions,
            assetAllocations: authoritativeEnvelope.assetAllocations,
            allocationHistories: authoritativeEnvelope.allocationHistories,
            monthlyPlans: authoritativeEnvelope.monthlyPlans,
            monthlyExecutionRecords: authoritativeEnvelope.monthlyExecutionRecords,
            completedExecutions: authoritativeEnvelope.completedExecutions,
            executionSnapshots: authoritativeEnvelope.executionSnapshots,
            completionEvents: authoritativeEnvelope.completionEvents
        ).withComputedFingerprint()
    }

    private func validatePackageShape(_ envelope: SnapshotEnvelope) throws {
        var issues: [String] = []

        issues.append(contentsOf: duplicateIDIssues(for: envelope.goals, entityName: "Goal", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.assets, entityName: "Asset", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.transactions, entityName: "Transaction", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.assetAllocations, entityName: "AssetAllocation", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.allocationHistories, entityName: "AllocationHistory", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.monthlyPlans, entityName: "MonthlyPlan", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.monthlyExecutionRecords, entityName: "MonthlyExecutionRecord", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.completedExecutions, entityName: "CompletedExecution", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.executionSnapshots, entityName: "ExecutionSnapshot", id: \.id))
        issues.append(contentsOf: duplicateIDIssues(for: envelope.completionEvents, entityName: "CompletionEvent", id: \.eventId))

        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.goals, entityName: "Goal", logicalKey: goalLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.assets, entityName: "Asset", logicalKey: assetLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.transactions, entityName: "Transaction", logicalKey: transactionLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.assetAllocations, entityName: "AssetAllocation", logicalKey: assetAllocationLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.allocationHistories, entityName: "AllocationHistory", logicalKey: allocationHistoryLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.monthlyPlans, entityName: "MonthlyPlan", logicalKey: monthlyPlanLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.monthlyExecutionRecords, entityName: "MonthlyExecutionRecord", logicalKey: monthlyExecutionRecordLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.completedExecutions, entityName: "CompletedExecution", logicalKey: completedExecutionLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.executionSnapshots, entityName: "ExecutionSnapshot", logicalKey: executionSnapshotLogicalKey))
        issues.append(contentsOf: duplicateLogicalKeyIssues(for: envelope.completionEvents, entityName: "CompletionEvent", logicalKey: completionEventLogicalKey))

        let activeGoals = envelope.goals.filter { $0.recordState == .active }
        let activeAssets = envelope.assets.filter { $0.recordState == .active }
        let activeTransactions = envelope.transactions.filter { $0.recordState == .active }
        let activeAssetAllocations = envelope.assetAllocations.filter { $0.recordState == .active }
        let activeAllocationHistories = envelope.allocationHistories.filter { $0.recordState == .active }
        let activeMonthlyPlans = envelope.monthlyPlans.filter { $0.recordState == .active }
        let activeMonthlyExecutionRecords = envelope.monthlyExecutionRecords.filter { $0.recordState == .active }
        let activeCompletedExecutions = envelope.completedExecutions.filter { $0.recordState == .active }
        let activeExecutionSnapshots = envelope.executionSnapshots.filter { $0.recordState == .active }
        let activeCompletionEvents = envelope.completionEvents.filter { $0.recordState == .active }

        let goalIDs = Set(activeGoals.map(\.id))
        let assetIDs = Set(activeAssets.map(\.id))
        let monthlyExecutionRecordIDs = Set(activeMonthlyExecutionRecords.map(\.id))
        let monthlyPlanIDs = Set(activeMonthlyPlans.map(\.id))
        let completedExecutionIDs = Set(activeCompletedExecutions.map(\.id))
        let executionSnapshotIDs = Set(activeExecutionSnapshots.map(\.id))
        let completionEventIDs = Set(activeCompletionEvents.map(\.eventId))

        for transaction in activeTransactions where transaction.assetId != nil && !assetIDs.contains(transaction.assetId!) {
            issues.append("Transaction \(transaction.id.uuidString) references missing asset \(transaction.assetId!.uuidString).")
        }

        for allocation in activeAssetAllocations {
            guard let assetId = allocation.assetId else {
                issues.append("AssetAllocation \(allocation.id.uuidString) is missing assetId.")
                continue
            }
            guard let goalId = allocation.goalId else {
                issues.append("AssetAllocation \(allocation.id.uuidString) is missing goalId.")
                continue
            }
            if !assetIDs.contains(assetId) {
                issues.append("AssetAllocation \(allocation.id.uuidString) references missing asset \(assetId.uuidString).")
            }
            if !goalIDs.contains(goalId) {
                issues.append("AssetAllocation \(allocation.id.uuidString) references missing goal \(goalId.uuidString).")
            }
        }

        for history in activeAllocationHistories {
            if let assetId = history.assetId, !assetIDs.contains(assetId) {
                issues.append("AllocationHistory \(history.id.uuidString) references missing asset \(assetId.uuidString).")
            }
            if let goalId = history.goalId, !goalIDs.contains(goalId) {
                issues.append("AllocationHistory \(history.id.uuidString) references missing goal \(goalId.uuidString).")
            }
        }

        for plan in activeMonthlyPlans where plan.executionRecordId != nil && !monthlyExecutionRecordIDs.contains(plan.executionRecordId!) {
            issues.append("MonthlyPlan \(plan.id.uuidString) references missing execution record \(plan.executionRecordId!.uuidString).")
        }

        let plansByExecutionRecord = Dictionary(grouping: activeMonthlyPlans.compactMap { plan in
            plan.executionRecordId.map { ($0, plan.id) }
        }, by: \.0).mapValues { Set($0.map(\.1)) }

        for record in activeMonthlyExecutionRecords {
            let referencedGoalIDs = Set(record.goalIds)
            let missingGoalIDs = referencedGoalIDs.subtracting(goalIDs)
            if !missingGoalIDs.isEmpty {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) references missing goal IDs.")
            }

            let referencedPlanIDs = Set(record.planIds)
            let missingPlanIDs = referencedPlanIDs.subtracting(monthlyPlanIDs)
            if !missingPlanIDs.isEmpty {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) references missing plan IDs.")
            }

            let expectedPlanIDs = plansByExecutionRecord[record.id] ?? []
            if referencedPlanIDs != expectedPlanIDs {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) plan IDs do not match MonthlyPlan.executionRecordId links.")
            }

            if let snapshotID = record.snapshotId, !executionSnapshotIDs.contains(snapshotID) {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) references missing execution snapshot \(snapshotID.uuidString).")
            }
            if let completedExecutionID = record.completedExecutionId, !completedExecutionIDs.contains(completedExecutionID) {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) references missing completed execution \(completedExecutionID.uuidString).")
            }
            let missingCompletionEventIDs = Set(record.completionEventIds).subtracting(completionEventIDs)
            if !missingCompletionEventIDs.isEmpty {
                issues.append("MonthlyExecutionRecord \(record.id.uuidString) references missing completion event IDs.")
            }
        }

        for completion in activeCompletedExecutions where !monthlyExecutionRecordIDs.contains(completion.executionRecordId) {
            issues.append("CompletedExecution \(completion.id.uuidString) references missing execution record \(completion.executionRecordId.uuidString).")
        }

        for snapshot in activeExecutionSnapshots where !monthlyExecutionRecordIDs.contains(snapshot.executionRecordId) {
            issues.append("ExecutionSnapshot \(snapshot.id.uuidString) references missing execution record \(snapshot.executionRecordId.uuidString).")
        }

        for event in activeCompletionEvents {
            if !monthlyExecutionRecordIDs.contains(event.executionRecordId) {
                issues.append("CompletionEvent \(event.eventId.uuidString) references missing execution record \(event.executionRecordId.uuidString).")
            }
            if !completedExecutionIDs.contains(event.completionSnapshotId) {
                issues.append("CompletionEvent \(event.eventId.uuidString) references missing completed execution \(event.completionSnapshotId.uuidString).")
            }
        }

        if !issues.isEmpty {
            throw LocalBridgeImportApplyError.malformedPackage(issues)
        }
    }

    private func makeApplyPlan(
        for envelope: SnapshotEnvelope,
        using indexes: BridgeAuthoritativeIndexes,
        in context: ModelContext
    ) throws -> BridgeImportApplyPlan {
        var goalsByIncomingID: [UUID: Goal] = [:]
        var assetsByIncomingID: [UUID: Asset] = [:]
        var recordsByIncomingID: [UUID: MonthlyExecutionRecord] = [:]
        var plansByIncomingID: [UUID: MonthlyPlan] = [:]
        var completedExecutionsByIncomingID: [UUID: CompletedExecution] = [:]
        var executionSnapshotsByIncomingID: [UUID: ExecutionSnapshot] = [:]
        var completionEventsByIncomingID: [UUID: CompletionEvent] = [:]

        var keptGoalIDs = Set<UUID>()
        var keptAssetIDs = Set<UUID>()
        var keptRecordIDs = Set<UUID>()
        var keptPlanIDs = Set<UUID>()
        var keptTransactionIDs = Set<UUID>()
        var keptAllocationIDs = Set<UUID>()
        var keptHistoryIDs = Set<UUID>()
        var keptCompletedExecutionIDs = Set<UUID>()
        var keptExecutionSnapshotIDs = Set<UUID>()
        var keptCompletionEventIDs = Set<UUID>()

        for snapshot in envelope.goals {
            if snapshot.recordState == .deleted {
                let goal = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "Goal",
                    existingByID: indexes.goals,
                    logicalMatches: indexes.goalList.filter { goalLogicalKey($0) == goalLogicalKey(snapshot) },
                    id: \Goal.id
                )
                context.delete(goal)
                keptGoalIDs.insert(goal.id)
                continue
            }
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "Goal",
                existingByID: indexes.goals,
                logicalMatches: indexes.goalList.filter { goalLogicalKey($0) == goalLogicalKey(snapshot) },
                id: \Goal.id
            ) {
                Goal(
                    name: snapshot.name,
                    currency: snapshot.currency,
                    targetAmount: snapshot.targetAmount,
                    deadline: snapshot.deadline,
                    startDate: snapshot.startDate,
                    emoji: snapshot.emoji,
                    description: snapshot.goalDescription,
                    link: snapshot.link
                )
            }
            let goal = match.model
            if match.isInsert {
                context.insert(goal)
                goal.id = snapshot.id
            }
            goal.name = snapshot.name
            goal.currency = snapshot.currency
            goal.targetAmount = snapshot.targetAmount
            goal.deadline = snapshot.deadline
            goal.startDate = snapshot.startDate
            goal.lifecycleStatusRawValue = snapshot.lifecycleStatusRawValue
            goal.emoji = snapshot.emoji
            goal.goalDescription = snapshot.goalDescription
            goal.link = snapshot.link

            goalsByIncomingID[snapshot.id] = goal
            keptGoalIDs.insert(goal.id)
        }

        for snapshot in envelope.assets {
            if snapshot.recordState == .deleted {
                let asset = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "Asset",
                    existingByID: indexes.assets,
                    logicalMatches: indexes.assetList.filter { assetLogicalKey($0) == assetLogicalKey(snapshot) },
                    id: \Asset.id
                )
                context.delete(asset)
                keptAssetIDs.insert(asset.id)
                continue
            }
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "Asset",
                existingByID: indexes.assets,
                logicalMatches: indexes.assetList.filter { assetLogicalKey($0) == assetLogicalKey(snapshot) },
                id: \Asset.id
            ) {
                Asset(currency: snapshot.currency, address: snapshot.address, chainId: snapshot.chainId)
            }
            let asset = match.model
            if match.isInsert {
                context.insert(asset)
                asset.id = snapshot.id
            }
            asset.currency = snapshot.currency
            asset.address = snapshot.address
            asset.chainId = snapshot.chainId

            assetsByIncomingID[snapshot.id] = asset
            keptAssetIDs.insert(asset.id)
        }

        for snapshot in envelope.monthlyExecutionRecords {
            if snapshot.recordState == .deleted {
                let record = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "MonthlyExecutionRecord",
                    existingByID: indexes.monthlyExecutionRecords,
                    logicalMatches: indexes.monthlyExecutionRecordList.filter {
                        monthlyExecutionRecordLogicalKey($0) == monthlyExecutionRecordLogicalKey(snapshot)
                    },
                    id: \MonthlyExecutionRecord.id
                )
                context.delete(record)
                keptRecordIDs.insert(record.id)
                continue
            }
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "MonthlyExecutionRecord",
                existingByID: indexes.monthlyExecutionRecords,
                logicalMatches: indexes.monthlyExecutionRecordList.filter {
                    monthlyExecutionRecordLogicalKey($0) == monthlyExecutionRecordLogicalKey(snapshot)
                },
                id: \MonthlyExecutionRecord.id
            ) {
                MonthlyExecutionRecord(monthLabel: snapshot.monthLabel, goalIds: [])
            }
            recordsByIncomingID[snapshot.id] = match.model
        }

        for snapshot in envelope.monthlyExecutionRecords {
            guard let record = recordsByIncomingID[snapshot.id] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "MonthlyExecutionRecord \(snapshot.id.uuidString) was not resolved during apply planning."
                ])
            }
            if indexes.monthlyExecutionRecords[record.id] == nil {
                context.insert(record)
                record.id = snapshot.id
            }
            record.monthLabel = snapshot.monthLabel
            record.statusRawValue = snapshot.statusRawValue
            record.createdAt = snapshot.createdAt
            record.startedAt = snapshot.startedAt
            record.completedAt = snapshot.completedAt
            record.canUndoUntil = snapshot.canUndoUntil
            let remappedGoalIDs = try snapshot.goalIds.map { incomingGoalID in
                guard let goal = goalsByIncomingID[incomingGoalID] else {
                    throw LocalBridgeImportApplyError.validationFailed([
                        "MonthlyExecutionRecord \(snapshot.id.uuidString) references unresolved goal \(incomingGoalID.uuidString)."
                    ])
                }
                return goal.id
            }
            record.trackedGoalIds = try JSONEncoder().encode(remappedGoalIDs)
            keptRecordIDs.insert(record.id)
        }

        for snapshot in envelope.monthlyPlans {
            if snapshot.recordState == .deleted {
                let plan = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "MonthlyPlan",
                    existingByID: indexes.monthlyPlans,
                    logicalMatches: indexes.monthlyPlanList.filter {
                        monthlyPlanLogicalKey($0) == monthlyPlanLogicalKey(monthLabel: snapshot.monthLabel, goalID: snapshot.goalId)
                    },
                    id: \MonthlyPlan.id
                )
                context.delete(plan)
                keptPlanIDs.insert(plan.id)
                continue
            }
            guard let goal = goalsByIncomingID[snapshot.goalId] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "MonthlyPlan \(snapshot.id.uuidString) references unresolved goal \(snapshot.goalId.uuidString)."
                ])
            }
            let executionRecord = try resolveExecutionRecord(
                incomingExecutionRecordID: snapshot.executionRecordId,
                forEntityName: "MonthlyPlan",
                entityID: snapshot.id,
                from: recordsByIncomingID
            )
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "MonthlyPlan",
                existingByID: indexes.monthlyPlans,
                logicalMatches: indexes.monthlyPlanList.filter {
                    monthlyPlanLogicalKey($0) == monthlyPlanLogicalKey(monthLabel: snapshot.monthLabel, goalID: goal.id)
                },
                id: \MonthlyPlan.id
            ) {
                let status = RequirementStatus(rawValue: snapshot.statusRawValue) ?? .onTrack
                let flexState = MonthlyPlan.FlexState(rawValue: snapshot.flexStateRawValue) ?? .flexible
                let state = MonthlyPlan.PlanState(rawValue: snapshot.stateRawValue) ?? .draft
                return MonthlyPlan(
                    goalId: goal.id,
                    monthLabel: snapshot.monthLabel,
                    requiredMonthly: snapshot.requiredMonthly,
                    remainingAmount: snapshot.remainingAmount,
                    monthsRemaining: snapshot.monthsRemaining,
                    currency: snapshot.currency,
                    status: status,
                    flexState: flexState,
                    state: state
                )
            }
            let plan = match.model
            if match.isInsert {
                context.insert(plan)
                plan.id = snapshot.id
            }
            plan.goalId = goal.id
            plan.monthLabel = snapshot.monthLabel
            plan.requiredMonthly = snapshot.requiredMonthly
            plan.remainingAmount = snapshot.remainingAmount
            plan.monthsRemaining = snapshot.monthsRemaining
            plan.currency = snapshot.currency
            plan.statusRawValue = snapshot.statusRawValue
            plan.stateRawValue = snapshot.stateRawValue
            plan.executionRecord = executionRecord
            plan.flexStateRawValue = snapshot.flexStateRawValue
            plan.customAmount = snapshot.customAmount
            plan.isProtected = snapshot.isProtected
            plan.isSkipped = snapshot.isSkipped
            plan.createdDate = snapshot.createdDate
            plan.lastModifiedDate = snapshot.lastModifiedDate

            plansByIncomingID[snapshot.id] = plan
            keptPlanIDs.insert(plan.id)
        }

        for snapshot in envelope.transactions {
            if snapshot.recordState == .deleted {
                let transaction = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "Transaction",
                    existingByID: indexes.transactions,
                    logicalMatches: indexes.transactionList.filter {
                        transactionLogicalKey($0) == transactionLogicalKey(
                            assetID: snapshot.assetId,
                            externalID: snapshot.externalId,
                            date: snapshot.date,
                            amount: snapshot.amount,
                            sourceRawValue: snapshot.sourceRawValue,
                            counterparty: snapshot.counterparty,
                            comment: snapshot.comment
                        )
                    },
                    id: \Transaction.id
                )
                context.delete(transaction)
                keptTransactionIDs.insert(transaction.id)
                continue
            }
            let asset = try resolveAsset(
                incomingAssetID: snapshot.assetId,
                forEntityName: "Transaction",
                entityID: snapshot.id,
                from: assetsByIncomingID
            )
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "Transaction",
                existingByID: indexes.transactions,
                logicalMatches: indexes.transactionList.filter {
                    transactionLogicalKey($0) == transactionLogicalKey(
                        assetID: asset?.id,
                        externalID: snapshot.externalId,
                        date: snapshot.date,
                        amount: snapshot.amount,
                        sourceRawValue: snapshot.sourceRawValue,
                        counterparty: snapshot.counterparty,
                        comment: snapshot.comment
                    )
                },
                id: \Transaction.id
            ) {
                let source = TransactionSource(rawValue: snapshot.sourceRawValue) ?? .manual
                return Transaction(
                    amount: snapshot.amount,
                    asset: asset,
                    date: snapshot.date,
                    source: source,
                    externalId: snapshot.externalId,
                    counterparty: snapshot.counterparty,
                    comment: snapshot.comment
                )
            }
            let transaction = match.model
            if match.isInsert {
                context.insert(transaction)
                transaction.id = snapshot.id
            }
            transaction.amount = snapshot.amount
            transaction.date = snapshot.date
            transaction.sourceRawValue = snapshot.sourceRawValue
            transaction.externalId = snapshot.externalId
            transaction.counterparty = snapshot.counterparty
            transaction.comment = snapshot.comment
            transaction.asset = asset
            keptTransactionIDs.insert(transaction.id)
        }

        for snapshot in envelope.assetAllocations {
            if snapshot.recordState == .deleted {
                let allocation = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "AssetAllocation",
                    existingByID: indexes.assetAllocations,
                    logicalMatches: indexes.assetAllocationList.filter {
                        assetAllocationLogicalKey($0) == assetAllocationLogicalKey(assetID: snapshot.assetId, goalID: snapshot.goalId)
                    },
                    id: \AssetAllocation.id
                )
                context.delete(allocation)
                keptAllocationIDs.insert(allocation.id)
                continue
            }
            guard let incomingAssetID = snapshot.assetId else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "AssetAllocation \(snapshot.id.uuidString) is missing assetId."
                ])
            }
            guard let incomingGoalID = snapshot.goalId else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "AssetAllocation \(snapshot.id.uuidString) is missing goalId."
                ])
            }
            guard let asset = assetsByIncomingID[incomingAssetID] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "AssetAllocation \(snapshot.id.uuidString) references unresolved asset \(incomingAssetID.uuidString)."
                ])
            }
            guard let goal = goalsByIncomingID[incomingGoalID] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "AssetAllocation \(snapshot.id.uuidString) references unresolved goal \(incomingGoalID.uuidString)."
                ])
            }
            let match = try resolveMatch(
                incomingID: snapshot.id,
                entityName: "AssetAllocation",
                existingByID: indexes.assetAllocations,
                logicalMatches: indexes.assetAllocationList.filter {
                    assetAllocationLogicalKey($0) == assetAllocationLogicalKey(assetID: asset.id, goalID: goal.id)
                },
                id: \AssetAllocation.id
            ) {
                AssetAllocation(asset: asset, goal: goal, amount: snapshot.amount)
            }
            let allocation = match.model
            if match.isInsert {
                context.insert(allocation)
                allocation.id = snapshot.id
            }
            allocation.amount = snapshot.amount
            allocation.createdDate = snapshot.createdDate
            allocation.lastModifiedDate = snapshot.lastModifiedDate
            allocation.asset = asset
            allocation.goal = goal
            keptAllocationIDs.insert(allocation.id)
        }

        for snapshot in envelope.allocationHistories {
            if snapshot.recordState == .deleted {
                let history = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "AllocationHistory",
                    existingByID: indexes.allocationHistories,
                    logicalMatches: indexes.allocationHistoryList.filter {
                        allocationHistoryLogicalKey($0) == allocationHistoryLogicalKey(
                            assetID: snapshot.assetId,
                            goalID: snapshot.goalId,
                            timestamp: snapshot.timestamp,
                            createdAt: snapshot.createdAt,
                            amount: snapshot.amount
                        )
                    },
                    id: \AllocationHistory.id
                )
                context.delete(history)
                keptHistoryIDs.insert(history.id)
                continue
            }
            let asset = try resolveAsset(
                incomingAssetID: snapshot.assetId,
                forEntityName: "AllocationHistory",
                entityID: snapshot.id,
                from: assetsByIncomingID
            )
            let goal = try resolveGoal(
                incomingGoalID: snapshot.goalId,
                forEntityName: "AllocationHistory",
                entityID: snapshot.id,
                from: goalsByIncomingID
            )
            let match: BridgeImportMatch<AllocationHistory>
            if asset == nil || goal == nil {
                guard let existing = indexes.allocationHistories[snapshot.id] else {
                    throw LocalBridgeImportApplyError.validationFailed([
                        "AllocationHistory \(snapshot.id.uuidString) cannot nullify missing parent references without an authoritative ID match."
                    ])
                }
                match = BridgeImportMatch(model: existing, isInsert: false)
            } else {
                let resolvedAsset = asset!
                let resolvedGoal = goal!
                match = try resolveMatch(
                    incomingID: snapshot.id,
                    entityName: "AllocationHistory",
                    existingByID: indexes.allocationHistories,
                    logicalMatches: indexes.allocationHistoryList.filter {
                        allocationHistoryLogicalKey($0) == allocationHistoryLogicalKey(
                            assetID: resolvedAsset.id,
                            goalID: resolvedGoal.id,
                            timestamp: snapshot.timestamp,
                            createdAt: snapshot.createdAt,
                            amount: snapshot.amount
                        )
                    },
                    id: \AllocationHistory.id
                ) {
                    AllocationHistory(asset: resolvedAsset, goal: resolvedGoal, amount: snapshot.amount, timestamp: snapshot.timestamp)
                }
            }
            let history = match.model
            if match.isInsert {
                context.insert(history)
                history.id = snapshot.id
            }
            history.amount = snapshot.amount
            history.timestamp = snapshot.timestamp
            history.createdAt = snapshot.createdAt
            history.monthLabel = snapshot.monthLabel
            history.assetId = asset?.id
            history.goalId = goal?.id
            history.asset = asset
            history.goal = goal
            keptHistoryIDs.insert(history.id)
        }

        for snapshot in envelope.monthlyExecutionRecords where snapshot.recordState == .active {
            guard let record = recordsByIncomingID[snapshot.id] else { continue }
            let linkedPlans = envelope.monthlyPlans.compactMap { planSnapshot in
                planSnapshot.recordState == .active && planSnapshot.executionRecordId == snapshot.id ? plansByIncomingID[planSnapshot.id] : nil
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            record.plans = linkedPlans.isEmpty ? nil : linkedPlans
        }

        for snapshot in envelope.executionSnapshots {
            if snapshot.recordState == .deleted {
                let executionSnapshot = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "ExecutionSnapshot",
                    existingByID: indexes.executionSnapshots,
                    logicalMatches: indexes.executionSnapshotList.filter {
                        executionSnapshotLogicalKey($0) == executionSnapshotLogicalKey(capturedAt: snapshot.capturedAt, totalPlanned: snapshot.totalPlanned)
                    },
                    id: \ExecutionSnapshot.id
                )
                context.delete(executionSnapshot)
                keptExecutionSnapshotIDs.insert(executionSnapshot.id)
                continue
            }
            guard let record = recordsByIncomingID[snapshot.executionRecordId] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "ExecutionSnapshot \(snapshot.id.uuidString) references unresolved execution record \(snapshot.executionRecordId.uuidString)."
                ])
            }

            let existingByID = indexes.executionSnapshots[snapshot.id]
            let nestedMatch = record.snapshot
            if let existingByID, let nestedMatch, existingByID.id != nestedMatch.id {
                throw LocalBridgeImportApplyError.validationFailed([
                    "ExecutionSnapshot \(snapshot.id.uuidString) has conflicting ID and nested execution-record matches."
                ])
            }

            let executionSnapshot = existingByID ?? nestedMatch ?? ExecutionSnapshot(
                id: snapshot.id,
                capturedAt: snapshot.capturedAt,
                totalPlanned: snapshot.totalPlanned,
                snapshotData: Data()
            )
            if existingByID == nil && nestedMatch == nil {
                context.insert(executionSnapshot)
            }
            executionSnapshot.id = snapshot.id
            executionSnapshot.capturedAt = snapshot.capturedAt
            executionSnapshot.totalPlanned = snapshot.totalPlanned
            executionSnapshot.snapshotData = try JSONEncoder().encode(
                snapshot.goalSnapshots.sorted { $0.goalId.uuidString < $1.goalId.uuidString }
            )
            executionSnapshot.executionRecord = record
            record.snapshot = executionSnapshot
            executionSnapshotsByIncomingID[snapshot.id] = executionSnapshot
            keptExecutionSnapshotIDs.insert(executionSnapshot.id)
        }

        for snapshot in envelope.completedExecutions {
            if snapshot.recordState == .deleted {
                let completedExecution = try resolveExistingForDelete(
                    incomingID: snapshot.id,
                    entityName: "CompletedExecution",
                    existingByID: indexes.completedExecutions,
                    logicalMatches: indexes.completedExecutionList.filter {
                        completedExecutionLogicalKey($0) == completedExecutionLogicalKey(monthLabel: snapshot.monthLabel)
                    },
                    id: \CompletedExecution.id
                )
                context.delete(completedExecution)
                keptCompletedExecutionIDs.insert(completedExecution.id)
                continue
            }
            guard let record = recordsByIncomingID[snapshot.executionRecordId] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "CompletedExecution \(snapshot.id.uuidString) references unresolved execution record \(snapshot.executionRecordId.uuidString)."
                ])
            }

            let existingByID = indexes.completedExecutions[snapshot.id]
            let nestedMatch = record.completedExecution
            if let existingByID, let nestedMatch, existingByID.id != nestedMatch.id {
                throw LocalBridgeImportApplyError.validationFailed([
                    "CompletedExecution \(snapshot.id.uuidString) has conflicting ID and nested execution-record matches."
                ])
            }

            let completedExecution = existingByID ?? nestedMatch ?? CompletedExecution(
                monthLabel: snapshot.monthLabel,
                completedAt: snapshot.completedAt,
                exchangeRatesSnapshot: snapshot.exchangeRatesSnapshot,
                goalSnapshots: snapshot.goalSnapshots.sorted { $0.goalId.uuidString < $1.goalId.uuidString },
                contributionSnapshots: snapshot.contributionSnapshots.sorted {
                    if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                    if $0.goalId != $1.goalId { return $0.goalId.uuidString < $1.goalId.uuidString }
                    return $0.assetId.uuidString < $1.assetId.uuidString
                }
            )
            if existingByID == nil && nestedMatch == nil {
                context.insert(completedExecution)
            }
            completedExecution.id = snapshot.id
            completedExecution.monthLabel = snapshot.monthLabel
            completedExecution.completedAt = snapshot.completedAt
            completedExecution.exchangeRatesSnapshotData = try JSONEncoder().encode(snapshot.exchangeRatesSnapshot)
            completedExecution.goalSnapshotsData = try JSONEncoder().encode(
                snapshot.goalSnapshots.sorted { $0.goalId.uuidString < $1.goalId.uuidString }
            )
            completedExecution.contributionSnapshotsData = try JSONEncoder().encode(
                snapshot.contributionSnapshots.sorted {
                    if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                    if $0.goalId != $1.goalId { return $0.goalId.uuidString < $1.goalId.uuidString }
                    return $0.assetId.uuidString < $1.assetId.uuidString
                }
            )
            completedExecution.executionRecord = record
            record.completedExecution = completedExecution
            completedExecutionsByIncomingID[snapshot.id] = completedExecution
            keptCompletedExecutionIDs.insert(completedExecution.id)
        }

        for snapshot in envelope.completionEvents {
            if snapshot.recordState == .deleted {
                let event = try resolveExistingForDelete(
                    incomingID: snapshot.eventId,
                    entityName: "CompletionEvent",
                    existingByID: indexes.completionEvents,
                    logicalMatches: indexes.completionEventList.filter {
                        completionEventLogicalKey($0) == completionEventLogicalKey(monthLabel: snapshot.monthLabel, sequence: snapshot.sequence)
                    },
                    id: \CompletionEvent.eventId
                )
                context.delete(event)
                keptCompletionEventIDs.insert(event.eventId)
                continue
            }
            guard let record = recordsByIncomingID[snapshot.executionRecordId] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "CompletionEvent \(snapshot.eventId.uuidString) references unresolved execution record \(snapshot.executionRecordId.uuidString)."
                ])
            }
            guard let completionSnapshot = completedExecutionsByIncomingID[snapshot.completionSnapshotId] else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "CompletionEvent \(snapshot.eventId.uuidString) references unresolved completed execution \(snapshot.completionSnapshotId.uuidString)."
                ])
            }

            let idMatch = indexes.completionEvents[snapshot.eventId]
            let logicalMatches = indexes.completionEventList.filter {
                completionEventLogicalKey($0) == completionEventLogicalKey(
                    monthLabel: snapshot.monthLabel,
                    sequence: snapshot.sequence
                )
            }
            let match = try resolveMatch(
                incomingID: snapshot.eventId,
                entityName: "CompletionEvent",
                existingByID: indexes.completionEvents,
                logicalMatches: logicalMatches,
                id: \CompletionEvent.eventId
            ) {
                CompletionEvent(
                    executionRecord: record,
                    sequence: snapshot.sequence,
                    sourceDiscriminator: snapshot.sourceDiscriminator,
                    completedAt: snapshot.completedAt,
                    completionSnapshot: completionSnapshot
                )
            }
            let event = match.model
            if match.isInsert {
                context.insert(event)
            }
            if idMatch == nil && match.isInsert {
                event.eventId = snapshot.eventId
            }
            event.eventId = snapshot.eventId
            event.executionRecordId = record.id
            event.monthLabel = snapshot.monthLabel
            event.sequence = snapshot.sequence
            event.sourceDiscriminator = snapshot.sourceDiscriminator
            event.completedAt = snapshot.completedAt
            event.undoneAt = snapshot.undoneAt
            event.undoReason = snapshot.undoReason
            event.createdAt = snapshot.createdAt
            event.executionRecord = record
            event.completionSnapshot = completionSnapshot
            completionEventsByIncomingID[snapshot.eventId] = event
            keptCompletionEventIDs.insert(event.eventId)
        }

        for snapshot in envelope.monthlyExecutionRecords where snapshot.recordState == .active {
            guard let record = recordsByIncomingID[snapshot.id] else { continue }
            if let snapshotID = snapshot.snapshotId {
                record.snapshot = executionSnapshotsByIncomingID[snapshotID]
            } else {
                record.snapshot = nil
            }
            if let completedExecutionID = snapshot.completedExecutionId {
                record.completedExecution = completedExecutionsByIncomingID[completedExecutionID]
            } else {
                record.completedExecution = nil
            }
            let linkedEvents = snapshot.completionEventIds.compactMap { completionEventsByIncomingID[$0] }
                .sorted {
                    if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                    return $0.eventId.uuidString < $1.eventId.uuidString
                }
            record.completionEvents = linkedEvents.isEmpty ? nil : linkedEvents
        }

        return BridgeImportApplyPlan {
            _ = keptTransactionIDs
            _ = keptAllocationIDs
            _ = keptHistoryIDs
            _ = keptPlanIDs
            _ = keptCompletionEventIDs
            _ = keptExecutionSnapshotIDs
            _ = keptCompletedExecutionIDs
            _ = keptRecordIDs
            _ = keptAssetIDs
            _ = keptGoalIDs
        }
    }

    private func resolveExistingForDelete<Model>(
        incomingID: UUID,
        entityName: String,
        existingByID: [UUID: Model],
        logicalMatches: [Model],
        id: KeyPath<Model, UUID>
    ) throws -> Model {
        if logicalMatches.count > 1 {
            throw LocalBridgeImportApplyError.validationFailed([
                "Ambiguous \(entityName) logical delete match for incoming ID \(incomingID.uuidString)."
            ])
        }

        let idMatch = existingByID[incomingID]
        let logicalMatch = logicalMatches.first
        if let idMatch, let logicalMatch, idMatch[keyPath: id] != logicalMatch[keyPath: id] {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(incomingID.uuidString) has conflicting ID and logical-key delete matches."
            ])
        }
        guard let matched = idMatch ?? logicalMatch else {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(incomingID.uuidString) marked deleted but no authoritative match exists."
            ])
        }
        return matched
    }

    private func duplicateIDIssues<Element>(
        for elements: [Element],
        entityName: String,
        id: KeyPath<Element, UUID>
    ) -> [String] {
        var seen = Set<UUID>()
        var duplicates: [UUID] = []

        for element in elements {
            let value = element[keyPath: id]
            if !seen.insert(value).inserted {
                duplicates.append(value)
            }
        }

        return duplicates.map { "\(entityName) contains duplicate ID \($0.uuidString)." }
    }

    private func duplicateLogicalKeyIssues<Element>(
        for elements: [Element],
        entityName: String,
        logicalKey: (Element) -> String
    ) -> [String] {
        var counts: [String: Int] = [:]
        for element in elements {
            counts[logicalKey(element), default: 0] += 1
        }
        return counts.compactMap { key, count in
            count > 1 ? "\(entityName) contains duplicate logical key \(key)." : nil
        }.sorted()
    }

    private func makeIndexes(in context: ModelContext) throws -> BridgeAuthoritativeIndexes {
        try BridgeAuthoritativeIndexes(
            goals: context.fetch(FetchDescriptor<Goal>()),
            assets: context.fetch(FetchDescriptor<Asset>()),
            transactions: context.fetch(FetchDescriptor<Transaction>()),
            assetAllocations: context.fetch(FetchDescriptor<AssetAllocation>()),
            allocationHistories: context.fetch(FetchDescriptor<AllocationHistory>()),
            monthlyPlans: context.fetch(FetchDescriptor<MonthlyPlan>()),
            monthlyExecutionRecords: context.fetch(FetchDescriptor<MonthlyExecutionRecord>()),
            completedExecutions: context.fetch(FetchDescriptor<CompletedExecution>()),
            executionSnapshots: context.fetch(FetchDescriptor<ExecutionSnapshot>()),
            completionEvents: context.fetch(FetchDescriptor<CompletionEvent>())
        )
    }

    private func resolveMatch<Model>(
        incomingID: UUID,
        entityName: String,
        existingByID: [UUID: Model],
        logicalMatches: [Model],
        id: KeyPath<Model, UUID>,
        makeNew: () -> Model
    ) throws -> BridgeImportMatch<Model> {
        let idMatch = existingByID[incomingID]
        if logicalMatches.count > 1 {
            throw LocalBridgeImportApplyError.validationFailed([
                "Ambiguous \(entityName) logical match for incoming ID \(incomingID.uuidString)."
            ])
        }

        let logicalMatch = logicalMatches.first
        if let idMatch, let logicalMatch, idMatch[keyPath: id] != logicalMatch[keyPath: id] {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(incomingID.uuidString) has conflicting ID and logical-key matches."
            ])
        }

        if let idMatch {
            return BridgeImportMatch(model: idMatch, isInsert: false)
        }
        if let logicalMatch {
            return BridgeImportMatch(model: logicalMatch, isInsert: false)
        }
        return BridgeImportMatch(model: makeNew(), isInsert: true)
    }

    private func resolveAsset(
        incomingAssetID: UUID?,
        forEntityName entityName: String,
        entityID: UUID,
        from resolvedAssets: [UUID: Asset]
    ) throws -> Asset? {
        guard let incomingAssetID else { return nil }
        guard let asset = resolvedAssets[incomingAssetID] else {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(entityID.uuidString) references unresolved asset \(incomingAssetID.uuidString)."
            ])
        }
        return asset
    }

    private func resolveExecutionRecord(
        incomingExecutionRecordID: UUID?,
        forEntityName entityName: String,
        entityID: UUID,
        from resolvedRecords: [UUID: MonthlyExecutionRecord]
    ) throws -> MonthlyExecutionRecord? {
        guard let incomingExecutionRecordID else { return nil }
        guard let record = resolvedRecords[incomingExecutionRecordID] else {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(entityID.uuidString) references unresolved execution record \(incomingExecutionRecordID.uuidString)."
            ])
        }
        return record
    }

    private func resolveGoal(
        incomingGoalID: UUID?,
        forEntityName entityName: String,
        entityID: UUID,
        from resolvedGoals: [UUID: Goal]
    ) throws -> Goal? {
        guard let incomingGoalID else { return nil }
        guard let goal = resolvedGoals[incomingGoalID] else {
            throw LocalBridgeImportApplyError.validationFailed([
                "\(entityName) \(entityID.uuidString) references unresolved goal \(incomingGoalID.uuidString)."
            ])
        }
        return goal
    }

    private func overlay<Element>(
        _ current: [Element],
        with incoming: [Element],
        id: KeyPath<Element, UUID>
    ) -> [UUID: Element] {
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0[keyPath: id], $0) })
        for element in incoming {
            merged[element[keyPath: id]] = element
        }
        return merged
    }

    private func overlay(
        _ current: [BridgeCompletionEventSnapshot],
        with incoming: [BridgeCompletionEventSnapshot],
        id: KeyPath<BridgeCompletionEventSnapshot, UUID>
    ) -> [UUID: BridgeCompletionEventSnapshot] {
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0[keyPath: id], $0) })
        for element in incoming {
            merged[element[keyPath: id]] = element
        }
        return merged
    }
}

private func deleted(_ snapshot: BridgeTransactionSnapshot) -> BridgeTransactionSnapshot {
    BridgeTransactionSnapshot(
        id: snapshot.id,
        recordState: .deleted,
        assetId: snapshot.assetId,
        amount: snapshot.amount,
        date: snapshot.date,
        sourceRawValue: snapshot.sourceRawValue,
        externalId: snapshot.externalId,
        counterparty: snapshot.counterparty,
        comment: snapshot.comment
    )
}

private func deleted(_ snapshot: BridgeAssetAllocationSnapshot) -> BridgeAssetAllocationSnapshot {
    BridgeAssetAllocationSnapshot(
        id: snapshot.id,
        recordState: .deleted,
        assetId: snapshot.assetId,
        goalId: snapshot.goalId,
        amount: snapshot.amount,
        createdDate: snapshot.createdDate,
        lastModifiedDate: snapshot.lastModifiedDate
    )
}

private func deleted(_ snapshot: BridgeMonthlyPlanSnapshot) -> BridgeMonthlyPlanSnapshot {
    BridgeMonthlyPlanSnapshot(
        id: snapshot.id,
        recordState: .deleted,
        goalId: snapshot.goalId,
        monthLabel: snapshot.monthLabel,
        requiredMonthly: snapshot.requiredMonthly,
        remainingAmount: snapshot.remainingAmount,
        monthsRemaining: snapshot.monthsRemaining,
        currency: snapshot.currency,
        statusRawValue: snapshot.statusRawValue,
        stateRawValue: snapshot.stateRawValue,
        executionRecordId: snapshot.executionRecordId,
        flexStateRawValue: snapshot.flexStateRawValue,
        customAmount: snapshot.customAmount,
        isProtected: snapshot.isProtected,
        isSkipped: snapshot.isSkipped,
        createdDate: snapshot.createdDate,
        lastModifiedDate: snapshot.lastModifiedDate
    )
}

private func deleted(_ snapshot: BridgeExecutionSnapshotPayload) -> BridgeExecutionSnapshotPayload {
    BridgeExecutionSnapshotPayload(
        id: snapshot.id,
        recordState: .deleted,
        executionRecordId: snapshot.executionRecordId,
        capturedAt: snapshot.capturedAt,
        totalPlanned: snapshot.totalPlanned,
        goalSnapshots: snapshot.goalSnapshots
    )
}

private func deleted(_ snapshot: BridgeCompletedExecutionSnapshot) -> BridgeCompletedExecutionSnapshot {
    BridgeCompletedExecutionSnapshot(
        id: snapshot.id,
        recordState: .deleted,
        executionRecordId: snapshot.executionRecordId,
        monthLabel: snapshot.monthLabel,
        completedAt: snapshot.completedAt,
        exchangeRatesSnapshot: snapshot.exchangeRatesSnapshot,
        goalSnapshots: snapshot.goalSnapshots,
        contributionSnapshots: snapshot.contributionSnapshots
    )
}

private func deleted(_ snapshot: BridgeCompletionEventSnapshot) -> BridgeCompletionEventSnapshot {
    BridgeCompletionEventSnapshot(
        eventId: snapshot.eventId,
        recordState: .deleted,
        executionRecordId: snapshot.executionRecordId,
        completionSnapshotId: snapshot.completionSnapshotId,
        monthLabel: snapshot.monthLabel,
        sequence: snapshot.sequence,
        sourceDiscriminator: snapshot.sourceDiscriminator,
        completedAt: snapshot.completedAt,
        undoneAt: snapshot.undoneAt,
        undoReason: snapshot.undoReason,
        createdAt: snapshot.createdAt
    )
}

private struct BridgeImportMatch<Model> {
    let model: Model
    let isInsert: Bool
}

private struct BridgeImportApplyPlan {
    private let applyClosure: () -> Void

    init(apply: @escaping () -> Void) {
        self.applyClosure = apply
    }

    func apply() {
        applyClosure()
    }
}

private struct BridgeAuthoritativeIndexes {
    let goalList: [Goal]
    let assetList: [Asset]
    let transactionList: [Transaction]
    let assetAllocationList: [AssetAllocation]
    let allocationHistoryList: [AllocationHistory]
    let monthlyPlanList: [MonthlyPlan]
    let monthlyExecutionRecordList: [MonthlyExecutionRecord]
    let completedExecutionList: [CompletedExecution]
    let executionSnapshotList: [ExecutionSnapshot]
    let completionEventList: [CompletionEvent]

    let goals: [UUID: Goal]
    let assets: [UUID: Asset]
    let transactions: [UUID: Transaction]
    let assetAllocations: [UUID: AssetAllocation]
    let allocationHistories: [UUID: AllocationHistory]
    let monthlyPlans: [UUID: MonthlyPlan]
    let monthlyExecutionRecords: [UUID: MonthlyExecutionRecord]
    let completedExecutions: [UUID: CompletedExecution]
    let executionSnapshots: [UUID: ExecutionSnapshot]
    let completionEvents: [UUID: CompletionEvent]

    init(
        goals: [Goal],
        assets: [Asset],
        transactions: [Transaction],
        assetAllocations: [AssetAllocation],
        allocationHistories: [AllocationHistory],
        monthlyPlans: [MonthlyPlan],
        monthlyExecutionRecords: [MonthlyExecutionRecord],
        completedExecutions: [CompletedExecution],
        executionSnapshots: [ExecutionSnapshot],
        completionEvents: [CompletionEvent]
    ) throws {
        self.goalList = goals
        self.assetList = assets
        self.transactionList = transactions
        self.assetAllocationList = assetAllocations
        self.allocationHistoryList = allocationHistories
        self.monthlyPlanList = monthlyPlans
        self.monthlyExecutionRecordList = monthlyExecutionRecords
        self.completedExecutionList = completedExecutions
        self.executionSnapshotList = executionSnapshots
        self.completionEventList = completionEvents

        self.goals = try Self.index(goals, id: \.id, entityName: "Goal")
        self.assets = try Self.index(assets, id: \.id, entityName: "Asset")
        self.transactions = try Self.index(transactions, id: \.id, entityName: "Transaction")
        self.assetAllocations = try Self.index(assetAllocations, id: \.id, entityName: "AssetAllocation")
        self.allocationHistories = try Self.index(allocationHistories, id: \.id, entityName: "AllocationHistory")
        self.monthlyPlans = try Self.index(monthlyPlans, id: \.id, entityName: "MonthlyPlan")
        self.monthlyExecutionRecords = try Self.index(monthlyExecutionRecords, id: \.id, entityName: "MonthlyExecutionRecord")
        self.completedExecutions = try Self.index(completedExecutions, id: \.id, entityName: "CompletedExecution")
        self.executionSnapshots = try Self.index(executionSnapshots, id: \.id, entityName: "ExecutionSnapshot")
        self.completionEvents = try Self.index(completionEvents, id: \.eventId, entityName: "CompletionEvent")
    }

    private static func index<Model>(
        _ models: [Model],
        id: KeyPath<Model, UUID>,
        entityName: String
    ) throws -> [UUID: Model] {
        var indexed: [UUID: Model] = [:]
        for model in models {
            let modelID = model[keyPath: id]
            guard indexed[modelID] == nil else {
                throw LocalBridgeImportApplyError.validationFailed([
                    "Authoritative \(entityName) dataset contains duplicate ID \(modelID.uuidString)."
                ])
            }
            indexed[modelID] = model
        }
        return indexed
    }
}

private func goalLogicalKey(_ snapshot: BridgeGoalSnapshot) -> String {
    goalLogicalKey(name: snapshot.name, currency: snapshot.currency, targetAmount: snapshot.targetAmount, deadline: snapshot.deadline)
}

private func goalLogicalKey(_ goal: Goal) -> String {
    goalLogicalKey(name: goal.name, currency: goal.currency, targetAmount: goal.targetAmount, deadline: goal.deadline)
}

private func goalLogicalKey(name: String, currency: String, targetAmount: Double, deadline: Date) -> String {
    [
        normalizedText(name),
        normalizedCurrency(currency),
        normalizedNumber(targetAmount),
        String(millisecondsSince1970(deadline))
    ].joined(separator: "|")
}

private func assetLogicalKey(_ snapshot: BridgeAssetSnapshot) -> String {
    assetLogicalKey(currency: snapshot.currency, chainID: snapshot.chainId, address: snapshot.address)
}

private func assetLogicalKey(_ asset: Asset) -> String {
    assetLogicalKey(currency: asset.currency, chainID: asset.chainId, address: asset.address)
}

private func assetLogicalKey(currency: String, chainID: String?, address: String?) -> String {
    [
        normalizedCurrency(currency),
        normalizedChainOrAddress(chainID),
        normalizedChainOrAddress(address)
    ].joined(separator: "|")
}

private func transactionLogicalKey(_ snapshot: BridgeTransactionSnapshot) -> String {
    transactionLogicalKey(
        assetID: snapshot.assetId,
        externalID: snapshot.externalId,
        date: snapshot.date,
        amount: snapshot.amount,
        sourceRawValue: snapshot.sourceRawValue,
        counterparty: snapshot.counterparty,
        comment: snapshot.comment
    )
}

private func transactionLogicalKey(_ transaction: Transaction) -> String {
    transactionLogicalKey(
        assetID: transaction.asset?.id,
        externalID: transaction.externalId,
        date: transaction.date,
        amount: transaction.amount,
        sourceRawValue: transaction.sourceRawValue,
        counterparty: transaction.counterparty,
        comment: transaction.comment
    )
}

private func transactionLogicalKey(
    assetID: UUID?,
    externalID: String?,
    date: Date,
    amount: Double,
    sourceRawValue: String,
    counterparty: String?,
    comment: String?
) -> String {
    let prefix = assetID?.uuidString ?? "nil"
    if let externalID, !externalID.isEmpty {
        return [prefix, normalizedText(externalID)].joined(separator: "|")
    }
    return [
        prefix,
        String(millisecondsSince1970(date)),
        normalizedNumber(amount),
        sourceRawValue,
        normalizedText(counterparty),
        normalizedText(comment)
    ].joined(separator: "|")
}

private func assetAllocationLogicalKey(_ snapshot: BridgeAssetAllocationSnapshot) -> String {
    assetAllocationLogicalKey(assetID: snapshot.assetId, goalID: snapshot.goalId)
}

private func assetAllocationLogicalKey(_ allocation: AssetAllocation) -> String {
    assetAllocationLogicalKey(assetID: allocation.asset?.id, goalID: allocation.goal?.id)
}

private func assetAllocationLogicalKey(assetID: UUID?, goalID: UUID?) -> String {
    [(assetID?.uuidString ?? "nil"), (goalID?.uuidString ?? "nil")].joined(separator: "|")
}

private func allocationHistoryLogicalKey(_ snapshot: BridgeAllocationHistorySnapshot) -> String {
    allocationHistoryLogicalKey(
        assetID: snapshot.assetId,
        goalID: snapshot.goalId,
        timestamp: snapshot.timestamp,
        createdAt: snapshot.createdAt,
        amount: snapshot.amount
    )
}

private func allocationHistoryLogicalKey(_ history: AllocationHistory) -> String {
    allocationHistoryLogicalKey(
        assetID: history.asset?.id ?? history.assetId,
        goalID: history.goal?.id ?? history.goalId,
        timestamp: history.timestamp,
        createdAt: history.createdAt,
        amount: history.amount
    )
}

private func allocationHistoryLogicalKey(
    assetID: UUID?,
    goalID: UUID?,
    timestamp: Date,
    createdAt: Date,
    amount: Double
) -> String {
    [
        assetID?.uuidString ?? "nil",
        goalID?.uuidString ?? "nil",
        String(millisecondsSince1970(timestamp)),
        String(millisecondsSince1970(createdAt)),
        normalizedNumber(amount)
    ].joined(separator: "|")
}

private func monthlyPlanLogicalKey(_ snapshot: BridgeMonthlyPlanSnapshot) -> String {
    monthlyPlanLogicalKey(monthLabel: snapshot.monthLabel, goalID: snapshot.goalId)
}

private func monthlyPlanLogicalKey(_ plan: MonthlyPlan) -> String {
    monthlyPlanLogicalKey(monthLabel: plan.monthLabel, goalID: plan.goalId)
}

private func monthlyPlanLogicalKey(monthLabel: String, goalID: UUID) -> String {
    [monthLabel, goalID.uuidString].joined(separator: "|")
}

private func monthlyExecutionRecordLogicalKey(_ snapshot: BridgeMonthlyExecutionRecordSnapshot) -> String {
    snapshot.monthLabel
}

private func monthlyExecutionRecordLogicalKey(_ record: MonthlyExecutionRecord) -> String {
    record.monthLabel
}

private func completedExecutionLogicalKey(_ snapshot: BridgeCompletedExecutionSnapshot) -> String {
    snapshot.monthLabel
}

private func completedExecutionLogicalKey(_ completion: CompletedExecution) -> String {
    completion.monthLabel
}

private func completedExecutionLogicalKey(monthLabel: String) -> String {
    monthLabel
}

private func executionSnapshotLogicalKey(_ snapshot: BridgeExecutionSnapshotPayload) -> String {
    snapshot.executionRecordId.uuidString
}

private func executionSnapshotLogicalKey(_ snapshot: ExecutionSnapshot) -> String {
    snapshot.executionRecord?.id.uuidString ?? "nil"
}

private func executionSnapshotLogicalKey(capturedAt: Date, totalPlanned: Double) -> String {
    [
        String(millisecondsSince1970(capturedAt)),
        normalizedNumber(totalPlanned)
    ].joined(separator: "|")
}

private func completionEventLogicalKey(_ snapshot: BridgeCompletionEventSnapshot) -> String {
    completionEventLogicalKey(monthLabel: snapshot.monthLabel, sequence: snapshot.sequence)
}

private func completionEventLogicalKey(_ event: CompletionEvent) -> String {
    completionEventLogicalKey(monthLabel: event.monthLabel, sequence: event.sequence)
}

private func completionEventLogicalKey(monthLabel: String, sequence: Int) -> String {
    [monthLabel, String(sequence)].joined(separator: "|")
}

private func normalizedText(_ value: String?) -> String {
    (value ?? "").precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedCurrency(_ value: String) -> String {
    value.uppercased()
}

private func normalizedChainOrAddress(_ value: String?) -> String {
    normalizedText(value).lowercased()
}

private func normalizedNumber(_ value: Double) -> String {
    String(format: "%.12f", value)
}

private func millisecondsSince1970(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000.0).rounded())
}
