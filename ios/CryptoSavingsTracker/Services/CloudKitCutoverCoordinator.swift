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
    private let persistenceController: PersistenceController?
    private let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "cutover")

    /// When true, skips the CKContainer account status check in preflight.
    /// Used only by integration tests that cannot reach real CloudKit.
    var skipAccountCheck = false

    /// Tracks whether a previous attempt failed in this session. If true, the
    /// cloud store files from the failed attempt must be removed before retrying.
    private var previousAttemptFailed = false

    convenience init(persistenceController: PersistenceController? = nil) {
        self.init(
            stackFactory: PersistenceStackFactory(),
            storageModeRegistry: UserDefaultsStorageModeRegistry(),
            persistenceController: persistenceController
        )
    }

    init(
        stackFactory: PersistenceStackFactory,
        storageModeRegistry: StorageModeRegistry,
        persistenceController: PersistenceController? = nil
    ) {
        self.stackFactory = stackFactory
        self.storageModeRegistry = storageModeRegistry
        self.persistenceController = persistenceController
    }

    private var activePersistenceController: PersistenceController {
        persistenceController ?? PersistenceController.shared
    }

    // MARK: - Pre-flight

    enum PreflightError: LocalizedError {
        case alreadyMigrated
        case noICloudAccount
        case restrictedAccount
        case accountCheckFailed(String)
        case cloudTargetNotEmpty(Int)
        case cloudTargetProbeFailure(String)
        case sourceHasDuplicateIDs([String])
        case unresolvedRelationships(String)

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
            case .cloudTargetNotEmpty(let count):
                return "CloudKit target store already contains \(count) record(s). Wipe the cloud store or use a fresh iCloud account to avoid merge conflicts."
            case .cloudTargetProbeFailure(let detail):
                return "Could not verify CloudKit target store is empty: \(detail). Migration blocked to prevent data loss."
            case .sourceHasDuplicateIDs(let details):
                return "Source data contains duplicate records that must be repaired before migration. \(details.joined(separator: "; "))"
            case .unresolvedRelationships(let detail):
                return "Source data has broken references that could not be repaired. \(detail). Run deduplication and retry."
            }
        }
    }

    func checkPrerequisites() async throws {
        guard storageModeRegistry.currentMode == .localOnly else {
            throw PreflightError.alreadyMigrated
        }

        if !skipAccountCheck {
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

        // Probe the CloudKit target for pre-existing data using the native
        // CKDatabase API. We deliberately avoid SwiftData fetch/fetchCount against
        // a CloudKit-backed ModelContext here — that can cause a framework trap
        // (crash) when the CloudKit mirroring delegate initializes.
        if !skipAccountCheck {
            try await probeCloudTargetViaCloudKit()
        }
    }

    /// Probes the CloudKit private database for pre-existing records using the
    /// native CKDatabase API. This avoids the SwiftData/CloudKit framework trap
    /// that occurs when calling fetchCount on a freshly-created CloudKit-backed
    /// ModelContext.
    ///
    /// Fail-closed: any CKDatabase error (except schema-not-deployed) blocks
    /// migration. Unknown cloud target state = blocked.
    /// Record types to probe in CloudKit. SwiftData/CoreData stores records as
    /// "CD_<EntityName>". We check the four durable root entity types to detect
    /// pre-existing data across the full migration scope.
    static let cloudProbeRecordTypes = [
        "CD_Goal",
        "CD_Asset",
        "CD_MonthlyExecutionRecord",
        "CD_CompletedExecution"
    ]

    private func probeCloudTargetViaCloudKit() async throws {
        let database = CKContainer.default().privateCloudDatabase
        var totalExisting = 0

        for recordType in Self.cloudProbeRecordTypes {
            let query = CKQuery(
                recordType: recordType,
                predicate: NSPredicate(value: true)
            )

            do {
                let (matchResults, _) = try await database.records(
                    matching: query,
                    resultsLimit: 1
                )
                totalExisting += matchResults.count
            } catch let ckError as CKError where ckError.code == .unknownItem {
                // Record type doesn't exist in CloudKit schema — no data has ever
                // been synced for this entity type. Safe to continue checking others.
                logger.info("CloudKit schema has no \(recordType) record type — OK")
            } catch {
                // Network failure, auth issue, or other CloudKit error.
                // Fail closed: unknown cloud target state = blocked.
                throw PreflightError.cloudTargetProbeFailure(
                    "\(recordType): \(error.localizedDescription)"
                )
            }
        }

        if totalExisting > 0 {
            throw PreflightError.cloudTargetNotEmpty(totalExisting)
        }

        logger.info("CloudKit target probe passed: all \(Self.cloudProbeRecordTypes.count) record types empty or absent")
    }

    // MARK: - Source Integrity

    /// Validates that the source store has no duplicate primary IDs for any
    /// migrated entity type. Duplicate IDs cause `Dictionary(uniqueKeysWithValues:)`
    /// traps during copy — a fatal crash on device. This check runs BEFORE any
    /// copy begins and blocks migration with a repair-required error.
    func validateSourceIntegrity(in context: ModelContext) throws {
        var duplicates: [String] = []

        func checkUnique<T: PersistentModel>(_ type: T.Type, name: String, id keyPath: KeyPath<T, UUID>) throws {
            let items = try context.fetch(FetchDescriptor<T>())
            var seen = Set<UUID>()
            var dupeIDs = Set<UUID>()
            for item in items {
                let itemID = item[keyPath: keyPath]
                if seen.contains(itemID) {
                    dupeIDs.insert(itemID)
                } else {
                    seen.insert(itemID)
                }
            }
            if !dupeIDs.isEmpty {
                let idList = dupeIDs.prefix(3).map(\.uuidString).joined(separator: ", ")
                let suffix = dupeIDs.count > 3 ? " and \(dupeIDs.count - 3) more" : ""
                duplicates.append("\(name): \(dupeIDs.count) duplicate ID(s) [\(idList)\(suffix)]")
            }
        }

        try checkUnique(Goal.self, name: "Goal", id: \.id)
        try checkUnique(Asset.self, name: "Asset", id: \.id)
        try checkUnique(Transaction.self, name: "Transaction", id: \.id)
        try checkUnique(AssetAllocation.self, name: "AssetAllocation", id: \.id)
        try checkUnique(AllocationHistory.self, name: "AllocationHistory", id: \.id)
        try checkUnique(MonthlyExecutionRecord.self, name: "MonthlyExecutionRecord", id: \.id)
        try checkUnique(MonthlyPlan.self, name: "MonthlyPlan", id: \.id)
        try checkUnique(CompletedExecution.self, name: "CompletedExecution", id: \.id)
        try checkUnique(ExecutionSnapshot.self, name: "ExecutionSnapshot", id: \.id)
        try checkUnique(CompletionEvent.self, name: "CompletionEvent", id: \.eventId)

        if !duplicates.isEmpty {
            logger.error("Source integrity check failed: \(duplicates.joined(separator: "; "))")
            throw PreflightError.sourceHasDuplicateIDs(duplicates)
        }

        logger.info("Source integrity check passed: no duplicate IDs found")
    }

    // MARK: - Relationship-Safe Scalar Maps

    /// Builds all maps needed for AllocationHistory diagnostics/repair using ONLY
    /// stored scalar fields. No SwiftData relationship traversal. No model property
    /// reads beyond `.id`, `.assetId`, `.goalId`.
    ///
    /// This avoids the "model instance was invalidated" crash that occurs when
    /// relationship arrays contain references to deleted entities.
    struct ScalarMaps {
        /// AllocationHistory rows that have a valid assetId → maps historyId → assetId
        let historyToAssetId: [UUID: UUID]
        /// AllocationHistory rows that have a valid goalId → maps historyId → goalId
        let historyToGoalId: [UUID: UUID]
        /// Goal → set of asset IDs, derived from AllocationHistory rows where both
        /// assetId and goalId are valid and point to existing entities
        let goalToAssetIDs: [UUID: Set<UUID>]

        /// Builds maps from fetched scalar snapshots. No model objects retained.
        /// `extraGoalAssetPairs` provides additional goal→asset mappings from any
        /// safe source (e.g. AssetAllocation scalar data from the copy path).
        static func build(
            histories: [(id: UUID, assetId: UUID?, goalId: UUID?)],
            sourceAssetIDs: Set<UUID>,
            sourceGoalIDs: Set<UUID>,
            extraGoalAssetPairs: [(goalId: UUID, assetId: UUID)] = []
        ) -> ScalarMaps {
            var historyToAssetId: [UUID: UUID] = [:]
            var historyToGoalId: [UUID: UUID] = [:]
            var goalToAssetIDs: [UUID: Set<UUID>] = [:]

            for h in histories {
                if let aid = h.assetId, sourceAssetIDs.contains(aid) {
                    historyToAssetId[h.id] = aid
                }
                if let gid = h.goalId, sourceGoalIDs.contains(gid) {
                    historyToGoalId[h.id] = gid
                }
                // If both are valid, this proves the asset was allocated to the goal
                if let aid = h.assetId, let gid = h.goalId,
                   sourceAssetIDs.contains(aid), sourceGoalIDs.contains(gid) {
                    goalToAssetIDs[gid, default: []].insert(aid)
                }
            }

            // Merge extra pairs (e.g. from AssetAllocation)
            for pair in extraGoalAssetPairs {
                if sourceAssetIDs.contains(pair.assetId), sourceGoalIDs.contains(pair.goalId) {
                    goalToAssetIDs[pair.goalId, default: []].insert(pair.assetId)
                }
            }

            return ScalarMaps(
                historyToAssetId: historyToAssetId,
                historyToGoalId: historyToGoalId,
                goalToAssetIDs: goalToAssetIDs
            )
        }
    }

    // MARK: - AllocationHistory Repair

    /// Repair result for operator visibility.
    struct AllocationHistoryRepairResult: Equatable {
        var repairedByReverseMap: Int = 0
        /// Rows where the goal has exactly 1 current asset. Not auto-repaired because
        /// current allocation state doesn't prove historical ownership.
        var ambiguousByGoalAllocationIDs: [UUID] = []
        /// Rows where the goal has multiple current assets — no way to determine which.
        var ambiguousByMultipleAssetsIDs: [UUID] = []
        var unrecoverableIDs: [UUID] = []

        var totalRepaired: Int { repairedByReverseMap }
        var totalFailed: Int {
            ambiguousByGoalAllocationIDs.count + ambiguousByMultipleAssetsIDs.count + unrecoverableIDs.count
        }
    }

    /// Repairs AllocationHistory records that have nil or invalid assetId/goalId.
    /// Uses only stored scalar IDs and parent-side reverse maps — NEVER dereferences
    /// child→parent relationships (`history.asset`, `history.goal`) which can crash
    /// with "Fatal error: model instance was invalidated" on corrupted data.
    ///
    /// Repair strategy (in priority order):
    /// 1. Parent-side reverse map: if asset.allocationHistory still contains this history
    ///    (evidence-based — the parent relationship proves ownership)
    /// 2. Ambiguous (single asset on goal): goal has exactly 1 current asset, but current
    ///    allocation state doesn't prove historical ownership. Not auto-repaired.
    /// 3. Ambiguous (multiple assets): goal has multiple assets, cannot determine which
    /// 4. Unrecoverable: no goal or no allocations to infer from
    @discardableResult
    func repairAndValidateAllocationHistory(in context: ModelContext) throws -> AllocationHistoryRepairResult {
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        let sourceAssetIDs = Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id))
        let sourceGoalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))

        // Build maps from scalar fields only — no relationship traversal
        let maps = ScalarMaps.build(
            histories: histories.map { ($0.id, $0.assetId, $0.goalId) },
            sourceAssetIDs: sourceAssetIDs,
            sourceGoalIDs: sourceGoalIDs
        )

        var result = AllocationHistoryRepairResult()

        for history in histories {
            let assetIdValid = history.assetId.map { sourceAssetIDs.contains($0) } ?? false
            let goalIdValid = history.goalId.map { sourceGoalIDs.contains($0) } ?? false

            if assetIdValid && goalIdValid { continue }

            // Strategy 1: scalar evidence from other history rows
            let inferredAssetId = maps.historyToAssetId[history.id]
            let inferredGoalId = maps.historyToGoalId[history.id]

            if !assetIdValid, let aid = inferredAssetId {
                history.assetId = aid
            }
            if !goalIdValid, let gid = inferredGoalId {
                history.goalId = gid
            }

            let assetFixed = history.assetId.map { sourceAssetIDs.contains($0) } ?? false
            let goalFixed = history.goalId.map { sourceGoalIDs.contains($0) } ?? false

            if assetFixed && goalFixed {
                result.repairedByReverseMap += 1
                continue
            }

            // Strategy 2: classify via goal→asset mappings (not auto-repaired)
            let effectiveGoalID = goalFixed ? history.goalId : nil
            if !assetFixed, let goalID = effectiveGoalID {
                let candidateAssets = maps.goalToAssetIDs[goalID] ?? []
                if candidateAssets.count == 1 {
                    result.ambiguousByGoalAllocationIDs.append(history.id)
                    continue
                } else if candidateAssets.count > 1 {
                    result.ambiguousByMultipleAssetsIDs.append(history.id)
                    continue
                }
            }

            result.unrecoverableIDs.append(history.id)
        }

        if result.totalRepaired > 0 {
            try context.save()
            logger.info("AllocationHistory repair: \(result.repairedByReverseMap) via scalar evidence")
        }

        if result.totalFailed > 0 {
            var details: [String] = []
            if !result.ambiguousByGoalAllocationIDs.isEmpty {
                let sample = result.ambiguousByGoalAllocationIDs.prefix(3).map(\.uuidString).joined(separator: ", ")
                details.append("\(result.ambiguousByGoalAllocationIDs.count) ambiguous (single asset on goal, unproven) [\(sample)]")
            }
            if !result.ambiguousByMultipleAssetsIDs.isEmpty {
                let sample = result.ambiguousByMultipleAssetsIDs.prefix(3).map(\.uuidString).joined(separator: ", ")
                details.append("\(result.ambiguousByMultipleAssetsIDs.count) ambiguous (goal has multiple assets) [\(sample)]")
            }
            if !result.unrecoverableIDs.isEmpty {
                let sample = result.unrecoverableIDs.prefix(3).map(\.uuidString).joined(separator: ", ")
                details.append("\(result.unrecoverableIDs.count) unrecoverable [\(sample)]")
            }
            let detail = "AllocationHistory: \(details.joined(separator: "; "))"
            logger.error("AllocationHistory repair incomplete: \(detail)")
            throw PreflightError.unresolvedRelationships(detail)
        }

        return result
    }

    // MARK: - AllocationHistory Repair Export & Operations

    /// Display info for an asset candidate in the repair flow.
    struct CandidateAsset: Codable, Equatable, Identifiable {
        let id: String
        let currency: String
        let address: String?
        let chainId: String?

        var displayLabel: String {
            var label = currency.uppercased()
            if let chain = chainId, !chain.isEmpty { label += " (\(chain))" }
            if let addr = address, !addr.isEmpty {
                let short = addr.count > 12 ? "\(addr.prefix(6))...\(addr.suffix(4))" : addr
                label += " \(short)"
            }
            return label
        }
    }

    /// Display info for a goal referenced by a problematic row.
    struct GoalInfo: Codable, Equatable {
        let id: String
        let name: String
        let currency: String
    }

    /// A single problematic AllocationHistory row with classification and candidate info.
    struct ProblematicHistoryRow: Codable, Equatable, Identifiable {
        var id: String { historyId }
        let historyId: String
        let storedAssetId: String?
        let goalId: String?
        let goalInfo: GoalInfo?
        let amount: Double
        let timestamp: Date
        let monthLabel: String
        let classification: String  // "ambiguous_single_asset" | "ambiguous_multi_asset" | "unrecoverable"
        let candidateAssetIDs: [String]
        let candidateAssets: [CandidateAsset]
    }

    /// Full export of all problematic AllocationHistory rows for operator review.
    struct RepairExport: Codable, Equatable {
        let rows: [ProblematicHistoryRow]
        let summary: RepairExportSummary
        let generatedAt: Date

        struct RepairExportSummary: Codable, Equatable {
            let ambiguousSingleAsset: Int
            let ambiguousMultiAsset: Int
            let unrecoverable: Int
            let total: Int
        }

        var jsonData: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(self)
        }

        var jsonString: String? {
            guard let data = jsonData else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    /// Snapshots a single model's scalar fields, skipping any model whose backing
    /// data has been invalidated. Returns nil if the model cannot be read safely.
    private static func snapshotAsset(_ asset: Asset) -> CandidateAsset? {
        // Access the most basic scalar first as a canary. If even .id faults, the
        // model is fully gone and we skip it silently.
        let assetId = asset.id
        return CandidateAsset(
            id: assetId.uuidString,
            currency: asset.currency,
            address: asset.address,
            chainId: asset.chainId
        )
    }

    private static func snapshotGoal(_ goal: Goal) -> GoalInfo? {
        let goalId = goal.id
        return GoalInfo(id: goalId.uuidString, name: goal.name, currency: goal.currency)
    }

    /// Generates a detailed export of all problematic AllocationHistory rows.
    /// Fully scalar-based: snapshots all display metadata immediately after fetch,
    /// then discards live model objects. No later reads from SwiftData backing data.
    ///
    /// All relationship traversal and model property access happens in the snapshot
    /// phase at the top. After that, only DTOs, UUID sets, and primitive maps are used.
    func generateRepairExport(from context: ModelContext) throws -> RepairExport {
        // --- Phase 1: Fetch and immediately snapshot everything into DTOs ---
        // After this phase, no live SwiftData model objects are retained or read.

        let assets = try context.fetch(FetchDescriptor<Asset>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())

        // Snapshot IDs (most basic scalar — least likely to fault)
        var sourceAssetIDs = Set<UUID>()
        var assetSnapshots: [UUID: CandidateAsset] = [:]
        for asset in assets {
            let aid = asset.id
            sourceAssetIDs.insert(aid)
            if let snap = Self.snapshotAsset(asset) {
                assetSnapshots[aid] = snap
            }
        }

        var sourceGoalIDs = Set<UUID>()
        var goalSnapshots: [UUID: GoalInfo] = [:]
        for goal in goals {
            let gid = goal.id
            sourceGoalIDs.insert(gid)
            if let snap = Self.snapshotGoal(goal) {
                goalSnapshots[gid] = snap
            }
        }

        // Snapshot history scalars
        struct HistorySnapshot {
            let id: UUID
            let assetId: UUID?
            let goalId: UUID?
            let amount: Double
            let timestamp: Date
            let monthLabel: String
        }
        var historySnapshots: [HistorySnapshot] = []
        for h in histories {
            historySnapshots.append(HistorySnapshot(
                id: h.id, assetId: h.assetId, goalId: h.goalId,
                amount: h.amount, timestamp: h.timestamp, monthLabel: h.monthLabel
            ))
        }

        // Build maps from scalar fields only — no relationship traversal
        let maps = ScalarMaps.build(
            histories: historySnapshots.map { ($0.id, $0.assetId, $0.goalId) },
            sourceAssetIDs: sourceAssetIDs,
            sourceGoalIDs: sourceGoalIDs
        )

        // --- Phase 2: Pure computation on DTOs only. No model objects past here. ---
        var rows: [ProblematicHistoryRow] = []

        for hs in historySnapshots {
            let assetIdValid = hs.assetId.map { sourceAssetIDs.contains($0) } ?? false
            let goalIdValid = hs.goalId.map { sourceGoalIDs.contains($0) } ?? false
            if assetIdValid && goalIdValid { continue }

            var assetResolved = assetIdValid
            var goalResolved = goalIdValid
            if !assetResolved, let rid = maps.historyToAssetId[hs.id] {
                assetResolved = true
                _ = rid  // already in map, just checking existence
            }
            if !goalResolved, let rid = maps.historyToGoalId[hs.id] {
                goalResolved = true
                _ = rid
            }
            if assetResolved && goalResolved { continue }

            let effectiveGoalID: UUID? = goalResolved ? (hs.goalId ?? maps.historyToGoalId[hs.id]) : nil
            let candidates: [UUID]
            let classification: String

            if !assetResolved, let goalID = effectiveGoalID {
                let candidateSet = maps.goalToAssetIDs[goalID] ?? []
                candidates = candidateSet.sorted { $0.uuidString < $1.uuidString }
                if candidateSet.count == 1 {
                    classification = "ambiguous_single_asset"
                } else if candidateSet.count > 1 {
                    classification = "ambiguous_multi_asset"
                } else {
                    classification = "unrecoverable"
                }
            } else {
                candidates = []
                classification = "unrecoverable"
            }

            let goalInfo = effectiveGoalID.flatMap { goalSnapshots[$0] }
            let candidateAssetInfos = candidates.compactMap { assetSnapshots[$0] }

            rows.append(ProblematicHistoryRow(
                historyId: hs.id.uuidString,
                storedAssetId: hs.assetId?.uuidString,
                goalId: hs.goalId?.uuidString,
                goalInfo: goalInfo,
                amount: hs.amount,
                timestamp: hs.timestamp,
                monthLabel: hs.monthLabel,
                classification: classification,
                candidateAssetIDs: candidates.map(\.uuidString),
                candidateAssets: candidateAssetInfos
            ))
        }

        let ambiguousSingle = rows.filter { $0.classification == "ambiguous_single_asset" }.count
        let ambiguousMulti = rows.filter { $0.classification == "ambiguous_multi_asset" }.count
        let unrecoverable = rows.filter { $0.classification == "unrecoverable" }.count

        return RepairExport(
            rows: rows,
            summary: .init(
                ambiguousSingleAsset: ambiguousSingle,
                ambiguousMultiAsset: ambiguousMulti,
                unrecoverable: unrecoverable,
                total: rows.count
            ),
            generatedAt: Date()
        )
    }

    /// Deletes only unrecoverable AllocationHistory rows (no valid goal, no candidates).
    /// Uses only scalar fields — no relationship traversal.
    /// Returns the count of rows deleted.
    @discardableResult
    func deleteUnrecoverableHistory(in context: ModelContext) throws -> Int {
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        let sourceAssetIDs = Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id))
        let sourceGoalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))

        let maps = ScalarMaps.build(
            histories: histories.map { ($0.id, $0.assetId, $0.goalId) },
            sourceAssetIDs: sourceAssetIDs,
            sourceGoalIDs: sourceGoalIDs
        )

        var toDelete: [AllocationHistory] = []

        for history in histories {
            let assetIdValid = history.assetId.map { sourceAssetIDs.contains($0) } ?? false
            let goalIdValid = history.goalId.map { sourceGoalIDs.contains($0) } ?? false
            if assetIdValid && goalIdValid { continue }

            let assetResolved = assetIdValid || maps.historyToAssetId[history.id] != nil
            let goalResolved = goalIdValid || maps.historyToGoalId[history.id] != nil
            if assetResolved && goalResolved { continue }

            let effectiveGoalID: UUID? = goalResolved ? (history.goalId ?? maps.historyToGoalId[history.id]) : nil
            if let goalID = effectiveGoalID {
                let candidateCount = maps.goalToAssetIDs[goalID]?.count ?? 0
                if candidateCount > 0 { continue }  // ambiguous, not unrecoverable
            }

            toDelete.append(history)
        }

        for history in toDelete {
            context.delete(history)
        }
        if !toDelete.isEmpty {
            try context.save()
            logger.info("Deleted \(toDelete.count) unrecoverable AllocationHistory row(s)")
        }

        return toDelete.count
    }

    /// Assigns a specific assetId to a single AllocationHistory row by ID.
    /// Validates that the target asset exists in the source store.
    /// Returns true if the assignment was made, false if the history or asset was not found.
    @discardableResult
    func assignAssetId(_ assetId: UUID, toHistoryId historyId: UUID, in context: ModelContext) throws -> Bool {
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let sourceAssetIDs = Set(assets.map(\.id))

        guard sourceAssetIDs.contains(assetId) else {
            logger.error("Cannot assign assetId \(assetId) — no matching Asset in source store")
            return false
        }

        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        guard let history = histories.first(where: { $0.id == historyId }) else {
            logger.error("Cannot assign assetId — AllocationHistory \(historyId) not found")
            return false
        }

        history.assetId = assetId
        try context.save()
        logger.info("Assigned assetId \(assetId) to AllocationHistory \(historyId)")
        return true
    }

    // MARK: - Migration Readiness Report

    /// Diagnostic report on local store quality. Runs entirely against the local
    /// SwiftData store — no CloudKit container is created or touched.
    struct MigrationReadinessReport: Codable, Equatable {
        struct EntityCount: Codable, Equatable {
            let name: String
            let count: Int
        }

        struct DuplicateIDReport: Codable, Equatable {
            let entityName: String
            let duplicateCount: Int
            let sampleIDs: [String]
        }

        struct AllocationHistoryDiagnostics: Codable, Equatable {
            let total: Int
            let storedAssetIdValid: Int
            let storedAssetIdInvalid: Int
            let storedGoalIdValid: Int
            let storedGoalIdInvalid: Int
            let missingAssetId: Int
            let missingGoalId: Int
            let repairableByReverseMap: Int
            let ambiguousByGoalAllocation: Int
            let ambiguousByMultipleAssets: Int
            let unrecoverable: Int
            let sampleAmbiguousIDs: [String]
            let sampleUnrecoverableIDs: [String]
        }

        let entityCounts: [EntityCount]
        let duplicateIDs: [DuplicateIDReport]
        let allocationHistory: AllocationHistoryDiagnostics
        let isReady: Bool
        let blockerSummary: [String]
        let generatedAt: Date

        var jsonData: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(self)
        }

        var jsonString: String? {
            guard let data = jsonData else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    /// Generates a local-only diagnostics report. Does not create any CloudKit
    /// containers. Safe to call repeatedly without side effects.
    func generateReadinessReport(from context: ModelContext) throws -> MigrationReadinessReport {
        var entityCounts: [MigrationReadinessReport.EntityCount] = []
        var duplicateReports: [MigrationReadinessReport.DuplicateIDReport] = []
        var blockers: [String] = []

        // Entity counts + duplicate detection
        func scan<T: PersistentModel>(_ type: T.Type, name: String, id keyPath: KeyPath<T, UUID>) throws {
            let items = try context.fetch(FetchDescriptor<T>())
            entityCounts.append(.init(name: name, count: items.count))

            var seen = Set<UUID>()
            var dupeIDs = Set<UUID>()
            for item in items {
                let itemID = item[keyPath: keyPath]
                if seen.contains(itemID) {
                    dupeIDs.insert(itemID)
                } else {
                    seen.insert(itemID)
                }
            }
            if !dupeIDs.isEmpty {
                duplicateReports.append(.init(
                    entityName: name,
                    duplicateCount: dupeIDs.count,
                    sampleIDs: Array(dupeIDs.prefix(3).map(\.uuidString))
                ))
                blockers.append("\(name): \(dupeIDs.count) duplicate ID(s)")
            }
        }

        try scan(Goal.self, name: "Goal", id: \.id)
        try scan(Asset.self, name: "Asset", id: \.id)
        try scan(Transaction.self, name: "Transaction", id: \.id)
        try scan(AssetAllocation.self, name: "AssetAllocation", id: \.id)
        try scan(AllocationHistory.self, name: "AllocationHistory", id: \.id)
        try scan(MonthlyExecutionRecord.self, name: "MonthlyExecutionRecord", id: \.id)
        try scan(MonthlyPlan.self, name: "MonthlyPlan", id: \.id)
        try scan(CompletedExecution.self, name: "CompletedExecution", id: \.id)
        try scan(ExecutionSnapshot.self, name: "ExecutionSnapshot", id: \.id)
        try scan(CompletionEvent.self, name: "CompletionEvent", id: \.eventId)

        // AllocationHistory diagnostics — validate stored IDs against actual source
        // entities. Uses ONLY stored scalar IDs and parent-side reverse maps. NEVER
        // dereferences child→parent relationships (history.asset, history.goal) which
        // crash with "model instance was invalidated" on corrupted data.
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        let sourceAssetIDs = Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id))
        let sourceGoalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))

        // Build maps from scalar fields only — no relationship traversal
        let maps = ScalarMaps.build(
            histories: histories.map { ($0.id, $0.assetId, $0.goalId) },
            sourceAssetIDs: sourceAssetIDs,
            sourceGoalIDs: sourceGoalIDs
        )

        var storedAssetIdValid = 0
        var storedAssetIdInvalid = 0
        var storedGoalIdValid = 0
        var storedGoalIdInvalid = 0
        var missingAssetId = 0
        var missingGoalId = 0
        var repairableByReverseMap = 0
        var ambiguousByGoalAllocationIDs: [UUID] = []
        var ambiguousByMultipleAssetsIDs: [UUID] = []
        var unrecoverableIDs: [UUID] = []

        for history in histories {
            // Classify stored assetId
            var assetResolved = false
            if let aid = history.assetId {
                if sourceAssetIDs.contains(aid) {
                    storedAssetIdValid += 1
                    assetResolved = true
                } else {
                    storedAssetIdInvalid += 1
                }
            } else {
                missingAssetId += 1
            }

            // Classify stored goalId
            var goalResolved = false
            if let gid = history.goalId {
                if sourceGoalIDs.contains(gid) {
                    storedGoalIdValid += 1
                    goalResolved = true
                } else {
                    storedGoalIdInvalid += 1
                }
            } else {
                missingGoalId += 1
            }

            if assetResolved && goalResolved { continue }  // fully valid

            // Strategy 1: scalar evidence from other history rows
            if !assetResolved, maps.historyToAssetId[history.id] != nil {
                assetResolved = true
            }
            if !goalResolved, maps.historyToGoalId[history.id] != nil {
                goalResolved = true
            }
            if assetResolved && goalResolved {
                repairableByReverseMap += 1
                continue
            }

            // Strategy 2: Classify via goal→asset mappings (not auto-repaired)
            let effectiveGoalID: UUID? = goalResolved ? (history.goalId ?? maps.historyToGoalId[history.id]) : nil
            if !assetResolved, let goalID = effectiveGoalID {
                let candidates = maps.goalToAssetIDs[goalID] ?? []
                if candidates.count == 1 {
                    // Single asset on goal — likely but not proven
                    ambiguousByGoalAllocationIDs.append(history.id)
                    continue
                } else if candidates.count > 1 {
                    ambiguousByMultipleAssetsIDs.append(history.id)
                    continue
                }
            }

            unrecoverableIDs.append(history.id)
        }

        let totalUnresolved = ambiguousByGoalAllocationIDs.count + ambiguousByMultipleAssetsIDs.count + unrecoverableIDs.count
        if totalUnresolved > 0 {
            blockers.append("AllocationHistory: \(totalUnresolved) unresolvable record(s) (\(ambiguousByGoalAllocationIDs.count) ambiguous/single-asset, \(ambiguousByMultipleAssetsIDs.count) ambiguous/multi-asset, \(unrecoverableIDs.count) unrecoverable)")
        }
        if storedAssetIdInvalid > 0 || storedGoalIdInvalid > 0 {
            blockers.append("AllocationHistory: \(storedAssetIdInvalid) invalid assetId(s), \(storedGoalIdInvalid) invalid goalId(s)")
        }

        let historyDiagnostics = MigrationReadinessReport.AllocationHistoryDiagnostics(
            total: histories.count,
            storedAssetIdValid: storedAssetIdValid,
            storedAssetIdInvalid: storedAssetIdInvalid,
            storedGoalIdValid: storedGoalIdValid,
            storedGoalIdInvalid: storedGoalIdInvalid,
            missingAssetId: missingAssetId,
            missingGoalId: missingGoalId,
            repairableByReverseMap: repairableByReverseMap,
            ambiguousByGoalAllocation: ambiguousByGoalAllocationIDs.count,
            ambiguousByMultipleAssets: ambiguousByMultipleAssetsIDs.count,
            unrecoverable: unrecoverableIDs.count,
            sampleAmbiguousIDs: Array((ambiguousByGoalAllocationIDs + ambiguousByMultipleAssetsIDs).prefix(5).map(\.uuidString)),
            sampleUnrecoverableIDs: Array(unrecoverableIDs.prefix(5).map(\.uuidString))
        )

        return MigrationReadinessReport(
            entityCounts: entityCounts,
            duplicateIDs: duplicateReports,
            allocationHistory: historyDiagnostics,
            isReady: blockers.isEmpty,
            blockerSummary: blockers,
            generatedAt: Date()
        )
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

        // 3. Validate source data integrity — duplicate IDs would crash the copy
        try validateSourceIntegrity(in: sourceContainer.mainContext)

        // 4. Repair AllocationHistory — backfill nil assetId/goalId from relationships,
        //    then block if any rows remain unresolvable
        try repairAndValidateAllocationHistory(in: sourceContainer.mainContext)

        // 5. Clean stale stores from previous failed attempts in this session.
        if previousAttemptFailed {
            removeStaleCloudStoreFiles()
        }
        stackFactory.removeStoreFiles(descriptor: stackFactory.cloudPrimaryStagingDescriptor)

        // 6. Create staging container with CloudKit disabled
        let stagingContainer: ModelContainer
        do {
            stagingContainer = try stackFactory.makeContainer(
                descriptor: stackFactory.cloudPrimaryStagingDescriptor,
                cloudKitEnabled: false
            )
        } catch {
            state = .failed("Failed to create staging container: \(error.localizedDescription)")
            throw error
        }

        // 7. Copy data into staging
        let manifest: CopyManifest
        do {
            manifest = try await copyAllEntities(
                from: sourceContainer.mainContext,
                to: stagingContainer.mainContext
            )
        } catch {
            stackFactory.removeStoreFiles(descriptor: stackFactory.cloudPrimaryStagingDescriptor)
            previousAttemptFailed = true
            state = .rolledBack("Staging copy failed: \(error.localizedDescription). Local data is intact.")
            throw error
        }

        // 8. Validate staging — compares target against source, fails on ANY skipped records
        state = .validatingCopy
        do {
            try validateCopy(
                source: sourceContainer.mainContext,
                target: stagingContainer.mainContext,
                manifest: manifest
            )
        } catch {
            stackFactory.removeStoreFiles(descriptor: stackFactory.cloudPrimaryStagingDescriptor)
            previousAttemptFailed = true
            state = .rolledBack("Staging validation failed: \(error.localizedDescription). Local data is intact.")
            throw error
        }

        // 9. Promote validated staging sqlite files into the final cloud-primary path
        //    before opening any CloudKit-backed container.
        do {
            removeStaleCloudStoreFiles()
            try stackFactory.replaceStoreFiles(
                from: stackFactory.cloudPrimaryStagingDescriptor,
                to: stackFactory.cloudPrimaryDescriptor
            )
            scheduleStagingStoreCleanup()
            logger.info("Promoted validated staging store into cloud-primary path")
        } catch {
            scheduleStagingStoreCleanup()
            previousAttemptFailed = true
            state = .rolledBack("Failed to promote staging store: \(error.localizedDescription). Local data is intact.")
            throw error
        }

        // 10. Persist the new mode for next launch.
        // Do NOT hot-swap the live runtime container in-session.
        // Existing views may still hold model instances from the local store, and
        // swapping containers causes those instances to be destroyed/reset under UI.
        // Promotion has already succeeded, so the next app launch can safely open the
        // CloudKit-backed store without risking stale-object crashes.
        state = .switchingMode
        storageModeRegistry.setMode(.cloudKitPrimary)

        previousAttemptFailed = false

        let duration = Date().timeIntervalSince(startTime)
        let evidence = MigrationEvidence(
            timestamp: Date(),
            entityCounts: manifest.sourceCounts,
            backupPath: backupPath,
            durationSeconds: duration
        )
        persistMigrationEvidence(evidence)

        state = .complete(evidence)
        logger.info("CloudKit cutover complete in \(String(format: "%.1f", duration))s; relaunch required to activate CloudKit runtime")
    }

    // MARK: - Entity Copy

    /// Tracks source and target counts for every entity type during copy.
    struct CopyManifest {
        var sourceCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]
        var skippedOrphans: [String: Int] = [:]

        var hasSkippedRecords: Bool {
            skippedOrphans.values.contains(where: { $0 > 0 })
        }

        var skippedSummary: String {
            skippedOrphans
                .filter { $0.value > 0 }
                .map { "\($0.key): \($0.value) orphan(s)" }
                .joined(separator: "; ")
        }
    }

    private func copyAllEntities(
        from source: ModelContext,
        to target: ModelContext
    ) async throws -> CopyManifest {
        var manifest = CopyManifest()

        // Copy in dependency order — parents before children

        // 1. Goals (no parent dependencies)
        let goals = try source.fetch(FetchDescriptor<Goal>())
        manifest.sourceCounts["Goal"] = goals.count
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
        manifest.targetCounts["Goal"] = goals.count

        // 2. Assets (no parent dependencies)
        let assets = try source.fetch(FetchDescriptor<Asset>())
        manifest.sourceCounts["Asset"] = assets.count
        state = .copyingData(progress: 0.15, entityName: "Assets")
        for asset in assets {
            let copy = Asset(currency: asset.currency, address: asset.address, chainId: asset.chainId)
            copy.id = asset.id
            target.insert(copy)
        }
        try target.save()
        manifest.targetCounts["Asset"] = assets.count

        let sourceTransactionAssetIDs = buildTransactionAssetMap(from: assets)
        let sourceAllocationAssetIDs = buildAllocationAssetMap(from: assets)
        let sourceHistoryAssetIDs = buildHistoryAssetMap(from: assets)

        // 3. Transactions (depends on Asset)
        let transactions = try source.fetch(FetchDescriptor<Transaction>())
        manifest.sourceCounts["Transaction"] = transactions.count
        state = .copyingData(progress: 0.3, entityName: "Transactions")
        let targetAssets = try target.fetch(FetchDescriptor<Asset>())
        // Defense-in-depth: use uniquingKeysWith to avoid fatalError if target
        // somehow contains duplicate IDs (source integrity check should catch this first)
        let targetAssetMap = Dictionary(targetAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for tx in transactions {
            let targetAsset = sourceTransactionAssetIDs[tx.id].flatMap { targetAssetMap[$0] }
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
        manifest.targetCounts["Transaction"] = transactions.count

        // 4. AssetAllocations (depends on Asset, Goal)
        let allocations = try source.fetch(FetchDescriptor<AssetAllocation>())
        manifest.sourceCounts["AssetAllocation"] = allocations.count
        state = .copyingData(progress: 0.45, entityName: "Allocations")
        let targetGoals = try target.fetch(FetchDescriptor<Goal>())
        let targetGoalMap = Dictionary(targetGoals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceAllocationGoalIDs = buildAllocationGoalMap(from: goals)
        var allocsCopied = 0
        var allocsSkipped = 0
        for alloc in allocations {
            guard let sourceAssetID = sourceAllocationAssetIDs[alloc.id],
                  let sourceGoalID = sourceAllocationGoalIDs[alloc.id],
                  let targetAsset = targetAssetMap[sourceAssetID],
                  let targetGoal = targetGoalMap[sourceGoalID] else {
                logger.warning("Orphan AssetAllocation \(alloc.id) — missing asset or goal in target")
                allocsSkipped += 1
                continue
            }
            let copy = AssetAllocation(asset: targetAsset, goal: targetGoal, amount: alloc.amount)
            copy.id = alloc.id
            copy.createdDate = alloc.createdDate
            copy.lastModifiedDate = alloc.lastModifiedDate
            target.insert(copy)
            allocsCopied += 1
        }
        try target.save()
        manifest.targetCounts["AssetAllocation"] = allocsCopied
        manifest.skippedOrphans["AssetAllocation"] = allocsSkipped

        // 5. AllocationHistory (depends on Asset, Goal)
        let histories = try source.fetch(FetchDescriptor<AllocationHistory>())
        manifest.sourceCounts["AllocationHistory"] = histories.count
        state = .copyingData(progress: 0.55, entityName: "AllocationHistory")
        let sourceHistoryGoalIDs = buildHistoryGoalMap(from: goals)
        var historiesCopied = 0
        var historiesSkipped = 0
        for history in histories {
            let sourceAssetID = history.assetId ?? sourceHistoryAssetIDs[history.id]
            let sourceGoalID = history.goalId ?? sourceHistoryGoalIDs[history.id]
            guard let sourceAssetID,
                  let sourceGoalID,
                  let tgtAsset = targetAssetMap[sourceAssetID],
                  let tgtGoal = targetGoalMap[sourceGoalID] else {
                logger.warning("Orphan AllocationHistory \(history.id) — missing asset or goal in target")
                historiesSkipped += 1
                continue
            }
            let copy = AllocationHistory(asset: tgtAsset, goal: tgtGoal, amount: history.amount, timestamp: history.timestamp)
            copy.id = history.id
            copy.assetId = history.assetId
            copy.goalId = history.goalId
            copy.monthLabel = history.monthLabel
            copy.createdAt = history.createdAt
            target.insert(copy)
            historiesCopied += 1
        }
        try target.save()
        manifest.targetCounts["AllocationHistory"] = historiesCopied
        manifest.skippedOrphans["AllocationHistory"] = historiesSkipped

        // 6. MonthlyExecutionRecords (no parent model dependency)
        let execRecords = try source.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        manifest.sourceCounts["MonthlyExecutionRecord"] = execRecords.count
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
        manifest.targetCounts["MonthlyExecutionRecord"] = execRecords.count

        let sourceExecutionRecordByMonth = Dictionary(
            execRecords.map { ($0.monthLabel, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sourceExecutionRecordIDByPlanKey = buildPlanExecutionRecordMap(from: execRecords)

        // 7. MonthlyPlans (optionally links to MonthlyExecutionRecord)
        let plans = try source.fetch(FetchDescriptor<MonthlyPlan>())
        manifest.sourceCounts["MonthlyPlan"] = plans.count
        state = .copyingData(progress: 0.75, entityName: "MonthlyPlans")
        let targetExecRecords = try target.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        let targetExecMap = Dictionary(targetExecRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
            let planKey = executionRecordKey(monthLabel: plan.monthLabel, goalID: plan.goalId)
            if let sourceExecRecordID = sourceExecutionRecordIDByPlanKey[planKey] {
                copy.executionRecord = targetExecMap[sourceExecRecordID]
            }
            target.insert(copy)
        }
        try target.save()
        manifest.targetCounts["MonthlyPlan"] = plans.count

        // 8. CompletedExecutions (links to MonthlyExecutionRecord)
        // Build source-side map: monthLabel -> execution record ID for linking
        let completedExecs = try source.fetch(FetchDescriptor<CompletedExecution>())
        manifest.sourceCounts["CompletedExecution"] = completedExecs.count
        state = .copyingData(progress: 0.85, entityName: "CompletedExecutions")
        // Track target CompletedExecution by ID for CompletionEvent linking below.
        // Do NOT read target-side relationships — that faults future backing data and crashes.
        var targetCompletedExecByExecRecordID: [UUID: CompletedExecution] = [:]
        var completedExecutionLinksDeferred = 0
        for ce in completedExecs {
            let copy = CompletedExecution(
                monthLabel: ce.monthLabel,
                completedAt: ce.completedAt,
                exchangeRatesSnapshot: ce.exchangeRatesSnapshot,
                goalSnapshots: ce.goalSnapshots,
                contributionSnapshots: ce.contributionSnapshots
            )
            copy.id = ce.id
            if let sourceExecRecord = sourceExecutionRecordByMonth[ce.monthLabel],
               let targetExecRecord = targetExecMap[sourceExecRecord.id] {
                // Do not set CompletedExecution.executionRecord during cutover.
                // This setter still faults SwiftData future backing data for some
                // corrupted local stores and crashes migration. We keep an in-memory
                // map for CompletionEvent relinking instead.
                targetCompletedExecByExecRecordID[sourceExecRecord.id] = copy
                completedExecutionLinksDeferred += 1
                _ = targetExecRecord
            }
            target.insert(copy)
        }
        try target.save()
        if completedExecutionLinksDeferred > 0 {
            logger.info("Deferred \(completedExecutionLinksDeferred) CompletedExecution.executionRecord link(s) during cutover to avoid future-backing-data traps")
        }
        manifest.targetCounts["CompletedExecution"] = completedExecs.count

        // 9. ExecutionSnapshots
        //
        // Intentionally do not traverse source-side `record.snapshot` relationships here.
        // Corrupted local stores can crash with
        // "Never access a full future backing data" when faulting execution graph links.
        // We still migrate the immutable snapshot rows themselves, but we do not attempt
        // to rebuild the source snapshot -> executionRecord link from live relationships.
        let snapshots = try source.fetch(FetchDescriptor<ExecutionSnapshot>())
        manifest.sourceCounts["ExecutionSnapshot"] = snapshots.count
        state = .copyingData(progress: 0.9, entityName: "Snapshots")
        for snap in snapshots {
            let copy = ExecutionSnapshot(
                id: snap.id,
                capturedAt: snap.capturedAt,
                totalPlanned: snap.totalPlanned,
                snapshotData: snap.snapshotData
            )
            target.insert(copy)
        }
        try target.save()
        manifest.targetCounts["ExecutionSnapshot"] = snapshots.count

        // 10. CompletionEvents (links to MonthlyExecutionRecord, CompletedExecution)
        // Use the precomputed targetCompletedExecByExecRecordID map — never read
        // target-side relationships which can fault SwiftData future backing data.
        let events = try source.fetch(FetchDescriptor<CompletionEvent>())
        manifest.sourceCounts["CompletionEvent"] = events.count
        state = .copyingData(progress: 0.95, entityName: "CompletionEvents")
        var eventsCopied = 0
        var eventsSkipped = 0
        for event in events {
            guard let targetExecRecord = targetExecMap[event.executionRecordId],
                  let targetCE = targetCompletedExecByExecRecordID[event.executionRecordId] else {
                logger.warning("Orphan CompletionEvent \(event.eventId) — missing execution record or completed execution in target")
                eventsSkipped += 1
                continue
            }
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
            eventsCopied += 1
        }
        try target.save()
        manifest.targetCounts["CompletionEvent"] = eventsCopied
        manifest.skippedOrphans["CompletionEvent"] = eventsSkipped

        state = .copyingData(progress: 1.0, entityName: "Complete")
        return manifest
    }

    private func buildTransactionAssetMap(from assets: [Asset]) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for asset in assets {
            for transaction in (asset.transactions ?? []) {
                mapping[transaction.id] = asset.id
            }
        }
        return mapping
    }

    private func buildAllocationAssetMap(from assets: [Asset]) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for asset in assets {
            for allocation in (asset.allocations ?? []) {
                mapping[allocation.id] = asset.id
            }
        }
        return mapping
    }

    private func buildAllocationGoalMap(from goals: [Goal]) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for goal in goals {
            for allocation in (goal.allocations ?? []) {
                mapping[allocation.id] = goal.id
            }
        }
        return mapping
    }

    private func buildHistoryAssetMap(from assets: [Asset]) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for asset in assets {
            for history in (asset.allocationHistory ?? []) {
                mapping[history.id] = asset.id
            }
        }
        return mapping
    }

    private func buildHistoryGoalMap(from goals: [Goal]) -> [UUID: UUID] {
        var mapping: [UUID: UUID] = [:]
        for goal in goals {
            for history in (goal.allocationHistory ?? []) {
                mapping[history.id] = goal.id
            }
        }
        return mapping
    }

    private func buildPlanExecutionRecordMap(from execRecords: [MonthlyExecutionRecord]) -> [String: UUID] {
        var mapping: [String: UUID] = [:]
        for record in execRecords {
            for goalID in record.goalIds {
                mapping[executionRecordKey(monthLabel: record.monthLabel, goalID: goalID)] = record.id
            }
        }
        return mapping
    }

    private func executionRecordKey(monthLabel: String, goalID: UUID) -> String {
        "\(monthLabel)|\(goalID.uuidString)"
    }

    // MARK: - Validation

    enum ValidationError: LocalizedError {
        case countMismatch(entity: String, source: Int, target: Int)
        case skippedRecords(String)
        case multipleFailures([String])

        var errorDescription: String? {
            switch self {
            case .countMismatch(let entity, let source, let target):
                return "\(entity): source has \(source) records, target has \(target)"
            case .skippedRecords(let summary):
                return "Migration incomplete — records skipped: \(summary)"
            case .multipleFailures(let descriptions):
                return descriptions.joined(separator: "; ")
            }
        }
    }

    private func validateCopy(
        source: ModelContext,
        target: ModelContext,
        manifest: CopyManifest
    ) throws {
        // Rule 1: Any skipped orphan records fail the migration.
        // The source store has referential integrity issues that must be
        // resolved before migration, not silently dropped.
        if manifest.hasSkippedRecords {
            throw ValidationError.skippedRecords(manifest.skippedSummary)
        }

        // Rule 2: Verify target counts match source counts for all entity types.
        var failures: [String] = []

        func check<T: PersistentModel>(_ type: T.Type, name: String) {
            guard let sourceCount = manifest.sourceCounts[name] else { return }
            do {
                let targetCount = try target.fetchCount(FetchDescriptor<T>())
                if targetCount != sourceCount {
                    failures.append("\(name): source \(sourceCount), target \(targetCount)")
                }
            } catch {
                failures.append("\(name): target fetch failed — \(error.localizedDescription)")
            }
        }

        check(Goal.self, name: "Goal")
        check(Asset.self, name: "Asset")
        check(Transaction.self, name: "Transaction")
        check(AssetAllocation.self, name: "AssetAllocation")
        check(AllocationHistory.self, name: "AllocationHistory")
        check(MonthlyExecutionRecord.self, name: "MonthlyExecutionRecord")
        check(MonthlyPlan.self, name: "MonthlyPlan")
        check(CompletedExecution.self, name: "CompletedExecution")
        check(ExecutionSnapshot.self, name: "ExecutionSnapshot")
        check(CompletionEvent.self, name: "CompletionEvent")

        if !failures.isEmpty {
            throw ValidationError.multipleFailures(failures)
        }

        logger.info("Validation passed: all \(manifest.sourceCounts.values.reduce(0, +)) source records present in target")
    }

    // MARK: - Cleanup & Evidence

    /// UserDefaults key used to mark the cloud store for deferred deletion.
    /// When set, the next launch should call `performDeferredCloudStoreCleanup()`
    /// BEFORE opening any cloud-backed container.
    static let pendingCloudCleanupKey = "CloudKit.PendingStoreCleanup"
    static let pendingStagingCleanupKey = "CloudKit.PendingStagingStoreCleanup"

    /// Removes stale cloud store files from a previous failed attempt in this session.
    /// Safe to call before creating a new cloud container because the old container's
    /// local variable has gone out of scope (ARC released it). Also clears any pending
    /// deferred cleanup marker since we're cleaning up now.
    private func removeStaleCloudStoreFiles() {
        guard let storeURL = stackFactory.cloudPrimaryDescriptor.storeURL else { return }
        let suffixes = ["", "-shm", "-wal", "-journal"]
        var removed = 0
        for suffix in suffixes {
            let path = storeURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
                removed += 1
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingCloudCleanupKey)
        if removed > 0 {
            logger.info("Removed \(removed) stale cloud store file(s) from previous failed attempt at \(storeURL.path)")
        }
    }

    /// Marks the cloud store for deferred deletion on next launch.
    /// Does NOT unlink files while the container/mirroring delegate is still active,
    /// which would trigger "vnode unlinked while in use" sqlite API violations.
    private func scheduleCloudStoreCleanup() {
        guard let storeURL = stackFactory.cloudPrimaryDescriptor.storeURL else { return }
        scheduleDeferredStoreCleanup(
            storeURL.path,
            key: Self.pendingCloudCleanupKey,
            label: "cloud store"
        )
    }

    /// Marks the staging store for deferred deletion on next launch.
    /// This avoids unlinking the sqlite files while the staging container still
    /// owns open file descriptors in the current process.
    private func scheduleStagingStoreCleanup() {
        guard let storeURL = stackFactory.cloudPrimaryStagingDescriptor.storeURL else { return }
        scheduleDeferredStoreCleanup(
            storeURL.path,
            key: Self.pendingStagingCleanupKey,
            label: "staging store"
        )
    }

    private func scheduleDeferredStoreCleanup(
        _ storePath: String,
        key: String,
        label: String
    ) {
        UserDefaults.standard.set(storePath, forKey: key)
        logger.info("Scheduled \(label) for deferred cleanup on next launch: \(storePath)")
    }

    /// Called on app launch (before opening any cloud container) to remove
    /// store files left behind by a failed cutover. Safe because no
    /// ModelContainer owns these files yet.
    static func performDeferredCloudStoreCleanup() {
        let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "cutover")
        let cleanupKeys = [
            (pendingCloudCleanupKey, "cloud store"),
            (pendingStagingCleanupKey, "staging store")
        ]

        for (key, label) in cleanupKeys {
            guard let storePath = UserDefaults.standard.string(forKey: key) else { continue }
            let suffixes = ["", "-shm", "-wal", "-journal"]
            var removed = 0
            for suffix in suffixes {
                let path = storePath + suffix
                if FileManager.default.fileExists(atPath: path) {
                    try? FileManager.default.removeItem(atPath: path)
                    removed += 1
                }
            }
            UserDefaults.standard.removeObject(forKey: key)
            logger.info("Deferred \(label) cleanup: removed \(removed) file(s) at \(storePath)")
        }
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
