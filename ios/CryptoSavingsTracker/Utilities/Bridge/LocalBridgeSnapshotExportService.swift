import Foundation
import SwiftData

enum LocalBridgeSnapshotExportError: LocalizedError {
    case runtimeNotCloudKitPrimary

    var errorDescription: String? {
        switch self {
        case .runtimeNotCloudKitPrimary:
            return "Local Bridge Sync export is available only after CloudKit becomes the active authoritative runtime."
        }
    }
}

@MainActor
final class LocalBridgeSnapshotExportService {
    private let persistenceController: PersistenceController
    private let capabilityManifest: BridgeCapabilityManifest

    convenience init() {
        self.init(
            persistenceController: .shared,
            capabilityManifest: .current()
        )
    }

    init(
        persistenceController: PersistenceController,
        capabilityManifest: BridgeCapabilityManifest
    ) {
        self.persistenceController = persistenceController
        self.capabilityManifest = capabilityManifest
    }

    func exportAuthoritativeSnapshot() throws -> SnapshotEnvelope {
        guard persistenceController.activeMode == .cloudKitPrimary || persistenceController.activeMode == .cloudRollbackBlocked else {
            throw LocalBridgeSnapshotExportError.runtimeNotCloudKitPrimary
        }

        return try exportSnapshot(from: persistenceController.activeMainContext)
    }

    func exportSnapshot(from context: ModelContext) throws -> SnapshotEnvelope {
        let goals = try context.fetch(FetchDescriptor<Goal>())
            .map {
                BridgeGoalSnapshot(
                    id: $0.id,
                    name: $0.name,
                    currency: $0.currency,
                    targetAmount: $0.targetAmount,
                    deadline: $0.deadline,
                    startDate: $0.startDate,
                    lifecycleStatusRawValue: $0.lifecycleStatusRawValue,
                    emoji: $0.emoji,
                    goalDescription: $0.goalDescription,
                    link: $0.link
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let assets = try context.fetch(FetchDescriptor<Asset>())
            .map {
                BridgeAssetSnapshot(
                    id: $0.id,
                    currency: $0.currency,
                    address: $0.address,
                    chainId: $0.chainId
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
            .map {
                BridgeTransactionSnapshot(
                    id: $0.id,
                    assetId: $0.asset?.id,
                    amount: $0.amount,
                    date: $0.date,
                    sourceRawValue: $0.sourceRawValue,
                    externalId: $0.externalId,
                    counterparty: $0.counterparty,
                    comment: $0.comment
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let assetAllocations = try context.fetch(FetchDescriptor<AssetAllocation>())
            .map {
                BridgeAssetAllocationSnapshot(
                    id: $0.id,
                    assetId: $0.asset?.id,
                    goalId: $0.goal?.id,
                    amount: $0.amount,
                    createdDate: $0.createdDate,
                    lastModifiedDate: $0.lastModifiedDate
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let allocationHistories = try context.fetch(FetchDescriptor<AllocationHistory>())
            .map {
                BridgeAllocationHistorySnapshot(
                    id: $0.id,
                    assetId: $0.assetId,
                    goalId: $0.goalId,
                    amount: $0.amount,
                    timestamp: $0.timestamp,
                    createdAt: $0.createdAt,
                    monthLabel: $0.monthLabel
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let monthlyPlans = try context.fetch(FetchDescriptor<MonthlyPlan>())
            .map {
                BridgeMonthlyPlanSnapshot(
                    id: $0.id,
                    goalId: $0.goalId,
                    monthLabel: $0.monthLabel,
                    requiredMonthly: $0.requiredMonthly,
                    remainingAmount: $0.remainingAmount,
                    monthsRemaining: $0.monthsRemaining,
                    currency: $0.currency,
                    statusRawValue: $0.statusRawValue,
                    stateRawValue: $0.stateRawValue,
                    executionRecordId: $0.executionRecord?.id,
                    flexStateRawValue: $0.flexStateRawValue,
                    customAmount: $0.customAmount,
                    isProtected: $0.isProtected,
                    isSkipped: $0.isSkipped,
                    createdDate: $0.createdDate,
                    lastModifiedDate: $0.lastModifiedDate
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let monthlyExecutionRecords = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())
            .map { record in
                BridgeMonthlyExecutionRecordSnapshot(
                    id: record.id,
                    monthLabel: record.monthLabel,
                    statusRawValue: record.statusRawValue,
                    createdAt: record.createdAt,
                    startedAt: record.startedAt,
                    completedAt: record.completedAt,
                    canUndoUntil: record.canUndoUntil,
                    goalIds: record.goalIds.sorted { $0.uuidString < $1.uuidString },
                    snapshotId: record.snapshot?.id,
                    completedExecutionId: record.completedExecution?.id,
                    planIds: (record.plans ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString },
                    completionEventIds: (record.completionEvents ?? []).map(\.eventId).sorted { $0.uuidString < $1.uuidString }
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let manifest = SnapshotManifest(
            snapshotID: UUID(),
            canonicalEncodingVersion: capabilityManifest.maximumSupportedCanonicalEncodingVersion,
            snapshotSchemaVersion: capabilityManifest.maximumSupportedSnapshotSchemaVersion,
            exportedAt: Date(),
            appModelSchemaVersion: capabilityManifest.appModelSchemaVersion,
            entityCounts: [
                BridgeEntityCount(name: "Goal", count: goals.count),
                BridgeEntityCount(name: "Asset", count: assets.count),
                BridgeEntityCount(name: "Transaction", count: transactions.count),
                BridgeEntityCount(name: "AssetAllocation", count: assetAllocations.count),
                BridgeEntityCount(name: "AllocationHistory", count: allocationHistories.count),
                BridgeEntityCount(name: "MonthlyPlan", count: monthlyPlans.count),
                BridgeEntityCount(name: "MonthlyExecutionRecord", count: monthlyExecutionRecords.count)
            ],
            baseDatasetFingerprint: ""
        )

        return try SnapshotEnvelope(
            manifest: manifest,
            goals: goals,
            assets: assets,
            transactions: transactions,
            assetAllocations: assetAllocations,
            allocationHistories: allocationHistories,
            monthlyPlans: monthlyPlans,
            monthlyExecutionRecords: monthlyExecutionRecords
        ).withComputedFingerprint()
    }
}
