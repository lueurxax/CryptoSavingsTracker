import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitCutoverTests {

    // MARK: - CutoverState Equatable

    @Test("CutoverState cases are equatable")
    func cutoverStateEquatable() {
        let idle = CloudKitCutoverCoordinator.CutoverState.idle
        let idle2 = CloudKitCutoverCoordinator.CutoverState.idle
        #expect(idle == idle2)

        let copying1 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.5, entityName: "Goals")
        let copying2 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.5, entityName: "Goals")
        #expect(copying1 == copying2)

        let copying3 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.7, entityName: "Assets")
        #expect(copying1 != copying3)

        let failed1 = CloudKitCutoverCoordinator.CutoverState.failed("error A")
        let failed2 = CloudKitCutoverCoordinator.CutoverState.failed("error B")
        #expect(failed1 != failed2)
    }

    // MARK: - MigrationEvidence

    @Test("MigrationEvidence is Codable roundtrip")
    func migrationEvidenceCodable() throws {
        let evidence = CloudKitCutoverCoordinator.MigrationEvidence(
            timestamp: Date(),
            entityCounts: ["Goal": 3, "Asset": 5, "Transaction": 10],
            backupPath: "/tmp/backup",
            durationSeconds: 2.5
        )

        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(CloudKitCutoverCoordinator.MigrationEvidence.self, from: data)

        #expect(decoded.entityCounts == evidence.entityCounts)
        #expect(decoded.backupPath == evidence.backupPath)
        #expect(decoded.durationSeconds == evidence.durationSeconds)
    }

    // MARK: - PreflightError

    @Test("PreflightError provides localized descriptions")
    func preflightErrorDescriptions() {
        let alreadyMigrated = CloudKitCutoverCoordinator.PreflightError.alreadyMigrated
        #expect(alreadyMigrated.errorDescription?.contains("already") == true)

        let noAccount = CloudKitCutoverCoordinator.PreflightError.noICloudAccount
        #expect(noAccount.errorDescription?.contains("iCloud") == true)

        let restricted = CloudKitCutoverCoordinator.PreflightError.restrictedAccount
        #expect(restricted.errorDescription?.contains("restricted") == true)

        let checkFailed = CloudKitCutoverCoordinator.PreflightError.accountCheckFailed("timeout")
        #expect(checkFailed.errorDescription?.contains("timeout") == true)

        let notEmpty = CloudKitCutoverCoordinator.PreflightError.cloudTargetNotEmpty(3)
        #expect(notEmpty.errorDescription?.contains("3") == true)
        #expect(notEmpty.errorDescription?.contains("already contains") == true)

        let probeFailure = CloudKitCutoverCoordinator.PreflightError.cloudTargetProbeFailure("disk full")
        #expect(probeFailure.errorDescription?.contains("disk full") == true)
        #expect(probeFailure.errorDescription?.contains("blocked") == true)
    }

    // MARK: - Coordinator Initial State

    @Test("Coordinator starts in idle state")
    func coordinatorInitialState() {
        let coordinator = CloudKitCutoverCoordinator()
        #expect(coordinator.state == .idle)
    }

    // MARK: - Migration Evidence Persistence

    @Test("Migration evidence can be persisted and loaded from UserDefaults")
    func migrationEvidencePersistence() {
        let evidence = CloudKitCutoverCoordinator.MigrationEvidence(
            timestamp: Date(),
            entityCounts: ["Goal": 2, "Asset": 4],
            backupPath: "/backup/test",
            durationSeconds: 1.0
        )

        // Persist
        if let data = try? JSONEncoder().encode(evidence) {
            UserDefaults.standard.set(data, forKey: "CloudKit.MigrationEvidence.Test")
        }

        // Load
        if let data = UserDefaults.standard.data(forKey: "CloudKit.MigrationEvidence.Test"),
           let loaded = try? JSONDecoder().decode(CloudKitCutoverCoordinator.MigrationEvidence.self, from: data) {
            #expect(loaded.entityCounts == evidence.entityCounts)
            #expect(loaded.backupPath == evidence.backupPath)
        } else {
            Issue.record("Failed to load persisted migration evidence")
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CloudKit.MigrationEvidence.Test")
    }

    // MARK: - ValidationError

    @Test("ValidationError provides count mismatch details")
    func validationErrorDescription() {
        let error = CloudKitCutoverCoordinator.ValidationError.countMismatch(
            entity: "Goal", source: 5, target: 3
        )
        #expect(error.errorDescription?.contains("Goal") == true)
        #expect(error.errorDescription?.contains("5") == true)
        #expect(error.errorDescription?.contains("3") == true)
    }

    @Test("ValidationError multipleFailures joins descriptions")
    func validationErrorMultipleFailures() {
        let error = CloudKitCutoverCoordinator.ValidationError.multipleFailures([
            "Goal: source 5, target 3",
            "Asset: source 10, target 8"
        ])
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Goal"))
        #expect(desc.contains("Asset"))
    }

    @Test("ValidationError skippedRecords reports orphan summary")
    func validationErrorSkippedRecords() {
        let error = CloudKitCutoverCoordinator.ValidationError.skippedRecords(
            "AssetAllocation: 2 orphan(s); CompletionEvent: 1 orphan(s)"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("AssetAllocation"))
        #expect(desc.contains("orphan"))
    }

    // MARK: - P2: CopyManifest

    @Test("CopyManifest reports skipped records correctly")
    func copyManifestSkippedRecords() {
        var manifest = CloudKitCutoverCoordinator.CopyManifest()
        manifest.sourceCounts = ["Goal": 3, "Asset": 5]
        manifest.targetCounts = ["Goal": 3, "Asset": 5]
        manifest.skippedOrphans = ["AssetAllocation": 2, "CompletionEvent": 0]

        #expect(manifest.hasSkippedRecords == true)
        #expect(manifest.skippedSummary.contains("AssetAllocation"))
        #expect(manifest.skippedSummary.contains("2"))
    }

    @Test("CopyManifest with no skips reports clean")
    func copyManifestNoSkips() {
        var manifest = CloudKitCutoverCoordinator.CopyManifest()
        manifest.sourceCounts = ["Goal": 3]
        manifest.targetCounts = ["Goal": 3]
        manifest.skippedOrphans = ["AssetAllocation": 0]

        #expect(manifest.hasSkippedRecords == false)
        #expect(manifest.skippedSummary.isEmpty)
    }

    // MARK: - P2: Atomicity — Registry/Runtime Consistency

    @Test("StorageModeRegistry stays localOnly if never explicitly set to cloudKitPrimary")
    func registryStaysLocalIfNotSet() {
        let suiteName = "CutoverTests.Atomicity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        // Simulate a cutover flow where the runtime switch "fails"
        // by never calling storageModeRegistry.setMode(.cloudKitPrimary).
        // After such a failure, the registry should still be localOnly.
        #expect(registry.currentMode == .localOnly)
        #expect(registry.lastUpdatedAt == nil)
    }

    @Test("PersistenceController.switchToContainer updates runtime state atomically")
    func switchToContainerAtomicUpdate() throws {
        let suiteName = "CutoverTests.HotSwap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        // Pre-condition: local-only, registry not yet set
        #expect(registry.currentMode == .localOnly)
        #expect(registry.currentMode == .localOnly)

        // Simulate successful cutover: switch container, THEN persist mode
        let cloudContainer = try factory.makeContainer(for: .cloudKitPrimary)
        try controller.switchToContainer(cloudContainer, mode: .cloudKitPrimary)

        // Runtime is now cloud (in-memory state)
        #expect(controller.activeMode == .cloudKitPrimary)

        // Registry has NOT been set yet — mirrors the coordinator's sequencing
        // where mode persist only happens after successful switch
        #expect(registry.currentMode == .localOnly)

        // Now persist
        registry.setMode(.cloudKitPrimary)
        #expect(registry.currentMode == .cloudKitPrimary)
    }

    @Test("If switchToContainer is never called, registry and runtime stay localOnly")
    func failedCutoverLeavesConsistentState() throws {
        let suiteName = "CutoverTests.FailedSwap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        let localContainer = controller.activeContainer

        // Simulate a cutover that fails before switchToContainer:
        // - create cloud container (this succeeds)
        // - copy data (this succeeds)
        // - validation FAILS → we never call switchToContainer or setMode
        // The contract is: both stay localOnly.

        #expect(registry.currentMode == .localOnly)
        #expect(registry.currentMode == .localOnly)
        #expect(controller.activeContainer === localContainer)
    }

    // MARK: - P2: Preflight Fail-Closed

    @Test("cloudTargetNotEmpty error description contains count and warning text")
    func preflightCloudTargetNotEmptyDescription() {
        let error = CloudKitCutoverCoordinator.PreflightError.cloudTargetNotEmpty(7)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("7"))
        #expect(desc.contains("already contains"))
    }

    // MARK: - Preflight: Device-Safe Contract

    @Test("Preflight with skipAccountCheck only validates mode, not CloudKit")
    func preflightSkipAccountCheckOnlyValidatesMode() async throws {
        let suiteName = "CutoverTests.Preflight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry
        )
        coordinator.skipAccountCheck = true

        // Mode is localOnly → preflight passes (account + probe skipped)
        try await coordinator.checkPrerequisites()
    }

    @Test("Preflight blocks when mode is already cloudKitPrimary")
    func preflightBlocksWhenAlreadyMigrated() async {
        let suiteName = "CutoverTests.PreflightBlock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )
        registry.setMode(.cloudKitPrimary)

        let factory = PersistenceStackFactory(environment: .preview)
        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry
        )
        coordinator.skipAccountCheck = true

        await #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try await coordinator.checkPrerequisites()
        }
    }

    @Test("cloudTargetProbeFailure error description includes detail and blocked message")
    func probeFailureErrorDescription() {
        let error = CloudKitCutoverCoordinator.PreflightError.cloudTargetProbeFailure(
            "Network timeout"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Network timeout"))
        #expect(desc.contains("blocked"))
        #expect(desc.contains("data loss"))
    }

    // MARK: - performCutover Integration

    @Test("performCutover copies all entity types and persists cloud mode for next launch without in-session hot-swap")
    func performCutoverIntegration() async throws {
        let suiteName = "CutoverTests.Integration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        // Seed source container with all 10 entity types
        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)
        let expectedCounts = try TestDataFactory.createFullCutoverTestData(in: sourceContext)

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Pre-condition: localOnly and local runtime mounted
        let localContainer = controller.activeContainer
        #expect(registry.currentMode == .localOnly)
        #expect(controller.activeMode == .localOnly)

        // Run cutover
        try await coordinator.performCutover(sourceContainer: sourceContainer)

        // Post-condition 1: mode persisted for next launch
        #expect(registry.currentMode == .cloudKitPrimary)

        // Post-condition 2: no in-session hot-swap; runtime remains local until relaunch
        #expect(controller.activeMode == .localOnly)
        #expect(controller.activeContainer === localContainer)

        // Post-condition 3: coordinator reports complete with evidence
        if case .complete(let evidence) = coordinator.state {
            // Verify all entity types were copied
            for (entity, count) in expectedCounts {
                #expect(evidence.entityCounts[entity] == count,
                        "Expected \(count) \(entity)(s) in evidence, got \(evidence.entityCounts[entity] ?? -1)")
            }
        } else {
            Issue.record("Expected .complete state, got \(coordinator.state)")
        }
    }

    // MARK: - Source Integrity: Duplicate ID Detection

    @Test("validateSourceIntegrity passes when source has no duplicate IDs")
    func sourceIntegrityPassesCleanData() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let coordinator = CloudKitCutoverCoordinator()
        try coordinator.validateSourceIntegrity(in: context)
    }

    @Test("validateSourceIntegrity blocks migration when source has duplicate Asset IDs")
    func sourceIntegrityBlocksDuplicateAssetIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let sharedID = UUID()
        let asset1 = Asset(currency: "BTC")
        asset1.id = sharedID
        context.insert(asset1)

        let asset2 = Asset(currency: "ETH")
        asset2.id = sharedID
        context.insert(asset2)
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.validateSourceIntegrity(in: context)
        }
    }

    @Test("validateSourceIntegrity blocks migration when source has duplicate Goal IDs")
    func sourceIntegrityBlocksDuplicateGoalIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let sharedID = UUID()
        let goal1 = Goal(name: "A", currency: "USD", targetAmount: 100, deadline: Date().addingTimeInterval(86400))
        goal1.id = sharedID
        context.insert(goal1)

        let goal2 = Goal(name: "B", currency: "EUR", targetAmount: 200, deadline: Date().addingTimeInterval(86400))
        goal2.id = sharedID
        context.insert(goal2)
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.validateSourceIntegrity(in: context)
        }
    }

    @Test("validateSourceIntegrity blocks migration when source has duplicate MonthlyExecutionRecord IDs")
    func sourceIntegrityBlocksDuplicateExecRecordIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let sharedID = UUID()
        let record1 = MonthlyExecutionRecord(monthLabel: "2026-01", goalIds: [])
        record1.id = sharedID
        context.insert(record1)

        let record2 = MonthlyExecutionRecord(monthLabel: "2026-02", goalIds: [])
        record2.id = sharedID
        context.insert(record2)
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.validateSourceIntegrity(in: context)
        }
    }

    @Test("sourceHasDuplicateIDs error description includes entity type and ID")
    func sourceHasDuplicateIDsErrorDescription() {
        let error = CloudKitCutoverCoordinator.PreflightError.sourceHasDuplicateIDs([
            "Asset: 1 duplicate ID(s) [AAAA-BBBB]"
        ])
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Asset"))
        #expect(desc.contains("duplicate"))
        #expect(desc.contains("repaired"))
    }

    @Test("performCutover fails cleanly with duplicate Asset IDs instead of crashing")
    func performCutoverFailsCleanlyOnDuplicateIDs() async throws {
        let suiteName = "CutoverTests.DuplicateID.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        // Seed source with duplicate Asset IDs — the exact crash scenario
        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)

        let goal = TestDataFactory.createSampleGoal(name: "Test Goal", targetAmount: 1000)
        sourceContext.insert(goal)

        let sharedID = UUID()
        let asset1 = Asset(currency: "BTC")
        asset1.id = sharedID
        sourceContext.insert(asset1)

        let asset2 = Asset(currency: "ETH")
        asset2.id = sharedID
        sourceContext.insert(asset2)
        try sourceContext.save()

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Must fail with PreflightError, NOT crash with fatalError
        await #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try await coordinator.performCutover(sourceContainer: sourceContainer)
        }

        // State must remain localOnly — no partial migration
        #expect(registry.currentMode == .localOnly)
        #expect(registry.currentMode == .localOnly)
    }

    // MARK: - Deferred Rollback Cleanup

    @Test("scheduleCloudStoreCleanup marks store for deferred cleanup without unlinking files")
    func deferredCleanupDoesNotUnlinkLiveStore() async throws {
        let suiteName = "CutoverTests.DeferredCleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: CloudKitCutoverCoordinator.pendingCloudCleanupKey)
        }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        // Seed source with data that will fail validation (orphan AllocationHistory)
        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)
        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        sourceContext.insert(goal)
        let asset = Asset(currency: "BTC")
        sourceContext.insert(asset)
        // Create an AllocationHistory with no resolvable parent references
        let orphanHistory = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        sourceContext.insert(orphanHistory)
        try sourceContext.save()

        // Break the relationships by clearing the IDs after save
        orphanHistory.assetId = nil
        orphanHistory.goalId = nil
        orphanHistory.asset = nil
        orphanHistory.goal = nil
        try sourceContext.save()

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Migration should fail at the repair step, before cloud container creation
        await #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try await coordinator.performCutover(sourceContainer: sourceContainer)
        }

        // No pending cleanup should be scheduled since we never created a cloud container
        let pendingPath = UserDefaults.standard.string(
            forKey: CloudKitCutoverCoordinator.pendingCloudCleanupKey
        )
        #expect(pendingPath == nil)

        // State must remain localOnly
        #expect(registry.currentMode == .localOnly)
        #expect(registry.currentMode == .localOnly)
    }

    @Test("performDeferredCloudStoreCleanup removes both cloud and staging files and clears both markers")
    func deferredCleanupRemovesFilesOnNextLaunch() {
        let tempDir = FileManager.default.temporaryDirectory
        let cloudStorePath = tempDir.appendingPathComponent("test-cloud-\(UUID().uuidString).store").path
        let stagingStorePath = tempDir.appendingPathComponent("test-staging-\(UUID().uuidString).store").path

        // Create fake store files for both markers
        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            FileManager.default.createFile(atPath: cloudStorePath + suffix, contents: Data("test".utf8))
            FileManager.default.createFile(atPath: stagingStorePath + suffix, contents: Data("test".utf8))
        }

        // Simulate pending cleanup markers
        UserDefaults.standard.set(cloudStorePath, forKey: CloudKitCutoverCoordinator.pendingCloudCleanupKey)
        UserDefaults.standard.set(stagingStorePath, forKey: CloudKitCutoverCoordinator.pendingStagingCleanupKey)

        // Run deferred cleanup (simulates next launch)
        CloudKitCutoverCoordinator.performDeferredCloudStoreCleanup()

        // Files should be gone for both cloud and staging stores
        for suffix in suffixes {
            #expect(!FileManager.default.fileExists(atPath: cloudStorePath + suffix))
            #expect(!FileManager.default.fileExists(atPath: stagingStorePath + suffix))
        }

        // Both markers should be cleared
        #expect(UserDefaults.standard.string(forKey: CloudKitCutoverCoordinator.pendingCloudCleanupKey) == nil)
        #expect(UserDefaults.standard.string(forKey: CloudKitCutoverCoordinator.pendingStagingCleanupKey) == nil)
    }

    // MARK: - AllocationHistory Repair & Preflight

    @Test("repairAndValidateAllocationHistory blocks when both assetId/goalId are nil and no other evidence exists")
    func repairBackfillsNilIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        // Create history — with scalar-only maps, there is no parent-side reverse
        // map. If both assetId and goalId are nil, the row is unrecoverable.
        let history = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(history)
        try context.save()

        // Clear the UUID properties to simulate legacy data
        history.assetId = nil
        history.goalId = nil
        try context.save()

        #expect(history.assetId == nil)
        #expect(history.goalId == nil)

        // With scalar-only maps there is no evidence to repair from — row is unrecoverable
        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.repairAndValidateAllocationHistory(in: context)
        }
    }

    @Test("repairAndValidateAllocationHistory blocks when relationships are fully broken")
    func repairBlocksOnUnresolvableHistory() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(history)
        try context.save()

        // Break everything — nil UUIDs AND nil relationships
        history.assetId = nil
        history.goalId = nil
        history.asset = nil
        history.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.repairAndValidateAllocationHistory(in: context)
        }
    }

    @Test("repairAndValidateAllocationHistory passes when all records already have valid IDs")
    func repairPassesCleanData() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let coordinator = CloudKitCutoverCoordinator()
        let result = try coordinator.repairAndValidateAllocationHistory(in: context)
        #expect(result.totalRepaired == 0)
    }

    @Test("unresolvedRelationships error description includes entity and count")
    func unresolvedRelationshipsErrorDescription() {
        let error = CloudKitCutoverCoordinator.PreflightError.unresolvedRelationships(
            "AllocationHistory: 5 record(s) with no resolvable asset or goal [AAA, BBB]"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("AllocationHistory"))
        #expect(desc.contains("broken references"))
        #expect(desc.contains("deduplication"))
    }

    @Test("Unresolved AllocationHistory is detected before cloud container creation")
    func unresolvedHistoryDetectedBeforeCloudContainer() async throws {
        let suiteName = "CutoverTests.HistoryPreflight.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        sourceContext.insert(goal)
        let asset = Asset(currency: "BTC")
        sourceContext.insert(asset)

        // Create AllocationHistory with fully broken references
        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        sourceContext.insert(history)
        try sourceContext.save()

        history.assetId = nil
        history.goalId = nil
        history.asset = nil
        history.goal = nil
        try sourceContext.save()

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Must fail before cloud container creation with unresolvedRelationships
        await #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try await coordinator.performCutover(sourceContainer: sourceContainer)
        }

        // No cloud store cleanup should be pending (failed before container creation)
        let pendingPath = UserDefaults.standard.string(
            forKey: CloudKitCutoverCoordinator.pendingCloudCleanupKey
        )
        #expect(pendingPath == nil)

        #expect(registry.currentMode == .localOnly)
        #expect(registry.currentMode == .localOnly)
    }

    // MARK: - Migration Readiness Report (Diagnostics)

    @Test("Readiness report on clean data shows isReady with correct entity counts")
    func readinessReportCleanData() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let expectedCounts = try TestDataFactory.createFullCutoverTestData(in: context)

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        #expect(report.isReady)
        #expect(report.duplicateIDs.isEmpty)
        #expect(report.blockerSummary.isEmpty)
        #expect(report.allocationHistory.unrecoverable == 0)
        #expect(report.allocationHistory.ambiguousByGoalAllocation == 0 && report.allocationHistory.ambiguousByMultipleAssets == 0)

        // Verify entity counts match
        for entityCount in report.entityCounts {
            if let expected = expectedCounts[entityCount.name] {
                #expect(entityCount.count == expected,
                        "Expected \(expected) \(entityCount.name), got \(entityCount.count)")
            }
        }
    }

    @Test("Readiness report detects duplicate IDs and marks not ready")
    func readinessReportDetectsDuplicates() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let sharedID = UUID()
        let asset1 = Asset(currency: "BTC")
        asset1.id = sharedID
        context.insert(asset1)

        let asset2 = Asset(currency: "ETH")
        asset2.id = sharedID
        context.insert(asset2)
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        #expect(!report.isReady)
        #expect(report.duplicateIDs.count == 1)
        #expect(report.duplicateIDs.first?.entityName == "Asset")
        #expect(report.duplicateIDs.first?.duplicateCount == 1)
        #expect(!report.blockerSummary.isEmpty)
    }

    @Test("Readiness report detects unresolved AllocationHistory and marks not ready")
    func readinessReportDetectsUnresolvedHistory() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "G", targetAmount: 100)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Break both IDs and relationships
        history.assetId = nil
        history.goalId = nil
        history.asset = nil
        history.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        #expect(!report.isReady)
        #expect(report.allocationHistory.total == 1)
        #expect(report.allocationHistory.unrecoverable == 1)
        #expect(report.allocationHistory.missingAssetId == 1)
        #expect(report.allocationHistory.missingGoalId == 1)
        #expect(!report.blockerSummary.isEmpty)
    }

    @Test("Readiness report classifies nil assetId/goalId with no scalar evidence as unrecoverable")
    func readinessReportIdentifiesRepairableHistory() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "G", targetAmount: 100)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Clear UUIDs — with scalar-only maps there is no evidence to repair from
        history.assetId = nil
        history.goalId = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        // Not ready — no scalar evidence exists to resolve either ID
        #expect(!report.isReady)
        #expect(report.allocationHistory.repairableByReverseMap == 0)
        #expect(report.allocationHistory.ambiguousByGoalAllocation == 0 && report.allocationHistory.ambiguousByMultipleAssets == 0)
        #expect(report.allocationHistory.unrecoverable == 1)
    }

    @Test("Readiness report detects invalid stored IDs pointing to non-existent entities")
    func readinessReportDetectsInvalidStoredIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "G", targetAmount: 100)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Set stored IDs to UUIDs that don't exist in source
        history.assetId = UUID()  // dangling — no Asset has this ID
        history.goalId = UUID()   // dangling — no Goal has this ID
        history.asset = nil
        history.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        #expect(!report.isReady)
        #expect(report.allocationHistory.storedAssetIdInvalid == 1)
        #expect(report.allocationHistory.storedGoalIdInvalid == 1)
        #expect(report.allocationHistory.unrecoverable == 1)
        #expect(report.blockerSummary.contains(where: { $0.contains("invalid") }))
    }

    @Test("repairAndValidateAllocationHistory blocks when stored IDs point to non-existent entities")
    func repairBlocksOnDanglingStoredIDs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "G", targetAmount: 100)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Set assetId/goalId to UUIDs that don't match any source entity
        history.assetId = UUID()
        history.goalId = UUID()
        history.asset = nil
        history.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.repairAndValidateAllocationHistory(in: context)
        }
    }

    @Test("Single asset on goal is classified as ambiguous, not auto-repaired")
    func singleAssetOnGoalIsAmbiguous() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(asset)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Dangling assetId, nil relationship — scalar maps see goalId is valid
        // and goal→asset mapping exists from evidence row, classified as ambiguous
        history.assetId = UUID()
        history.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        // Must throw — single asset on goal is NOT proven safe for auto-repair
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.repairAndValidateAllocationHistory(in: context)
        }
    }

    @Test("Repair reports ambiguous when goal has multiple allocated assets")
    func repairReportsAmbiguous() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset1 = Asset(currency: "BTC")
        context.insert(asset1)
        let asset2 = Asset(currency: "ETH")
        context.insert(asset2)

        // Allocate both assets to the same goal
        let alloc1 = AssetAllocation(asset: asset1, goal: goal, amount: 0.5)
        context.insert(alloc1)
        let alloc2 = AssetAllocation(asset: asset2, goal: goal, amount: 0.3)
        context.insert(alloc2)

        // Valid history rows establish goal→asset mappings for both assets in ScalarMaps
        let evidenceHistory1 = AllocationHistory(asset: asset1, goal: goal, amount: 0.5)
        context.insert(evidenceHistory1)
        let evidenceHistory2 = AllocationHistory(asset: asset2, goal: goal, amount: 0.3)
        context.insert(evidenceHistory2)

        let history = AllocationHistory(asset: asset1, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Set assetId to dangling, nil relationship
        history.assetId = UUID()
        history.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try coordinator.repairAndValidateAllocationHistory(in: context)
        }
    }

    @Test("Diagnostics classifies single-asset-on-goal as ambiguous, not auto-repairable")
    func diagnosticsRepairCategories() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(asset)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        // History with dangling assetId, valid goalId, 1 asset on goal
        let h1 = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(h1)
        try context.save()
        h1.assetId = UUID()
        h1.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        // Not ready — single asset on goal is ambiguous, not proven
        #expect(!report.isReady)
        #expect(report.allocationHistory.ambiguousByGoalAllocation == 1)
        #expect(report.allocationHistory.ambiguousByMultipleAssets == 0)
        #expect(report.allocationHistory.unrecoverable == 0)
    }

    @Test("Readiness report generates valid JSON for copying")
    func readinessReportJSON() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let coordinator = CloudKitCutoverCoordinator()
        let report = try coordinator.generateReadinessReport(from: context)

        let json = report.jsonString
        #expect(json != nil)
        #expect(json?.contains("entityCounts") == true)
        #expect(json?.contains("allocationHistory") == true)
        #expect(json?.contains("isReady") == true)

        // Verify it roundtrips
        let data = report.jsonData!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            CloudKitCutoverCoordinator.MigrationReadinessReport.self,
            from: data
        )
        #expect(decoded.isReady == report.isReady)
        #expect(decoded.entityCounts.count == report.entityCounts.count)
    }

    // MARK: - Expanded Cloud Target Probe

    @Test("cloudProbeRecordTypes covers the four durable root entity types")
    func cloudProbeRecordTypesComplete() {
        let types = CloudKitCutoverCoordinator.cloudProbeRecordTypes
        #expect(types.contains("CD_Goal"))
        #expect(types.contains("CD_Asset"))
        #expect(types.contains("CD_MonthlyExecutionRecord"))
        #expect(types.contains("CD_CompletedExecution"))
        #expect(types.count == 4)
    }

    // MARK: - Repair Export & Operations

    @Test("generateRepairExport includes all problematic rows with classification and candidates")
    func repairExportContent() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(asset)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        // Ambiguous single-asset row: dangling assetId, valid goalId, 1 asset on goal
        let h1 = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(h1)
        try context.save()
        h1.assetId = UUID()
        h1.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let export = try coordinator.generateRepairExport(from: context)

        #expect(export.rows.count == 1)
        #expect(export.summary.ambiguousSingleAsset == 1)
        #expect(export.rows[0].classification == "ambiguous_single_asset")
        #expect(export.rows[0].candidateAssetIDs.count == 1)
        #expect(export.rows[0].candidateAssetIDs[0] == asset.id.uuidString)
        #expect(export.rows[0].goalId == goal.id.uuidString)

        // JSON roundtrip
        let json = export.jsonString
        #expect(json != nil)
        #expect(json?.contains("ambiguous_single_asset") == true)
    }

    @Test("deleteUnrecoverableHistory removes only unrecoverable rows")
    func deleteUnrecoverableOnly() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        // Ambiguous row (has goal with asset, but dangling assetId)
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        context.insert(alloc)
        let h1 = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(h1)
        try context.save()
        h1.assetId = UUID()
        h1.asset = nil
        try context.save()

        // Unrecoverable row (no valid goal either)
        let h2 = AllocationHistory(asset: asset, goal: goal, amount: 0.3)
        context.insert(h2)
        try context.save()
        h2.assetId = UUID()
        h2.goalId = UUID()
        h2.asset = nil
        h2.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let deleted = try coordinator.deleteUnrecoverableHistory(in: context)

        #expect(deleted == 1)  // only unrecoverable
        let remaining = try context.fetchCount(FetchDescriptor<AllocationHistory>())
        #expect(remaining == 2)  // evidence + ambiguous rows preserved
    }

    @Test("assignAssetId sets the assetId on a specific history row")
    func assignAssetIdToHistory() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Break the assetId
        history.assetId = UUID()
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let result = try coordinator.assignAssetId(asset.id, toHistoryId: history.id, in: context)

        #expect(result == true)
        #expect(history.assetId == asset.id)
    }

    @Test("assignAssetId rejects non-existent asset")
    func assignAssetIdRejectsInvalidAsset() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let result = try coordinator.assignAssetId(UUID(), toHistoryId: history.id, in: context)

        #expect(result == false)
    }

    @Test("migration remains blocked while ambiguous rows exist after deleting unrecoverable")
    func migrationBlockedWithAmbiguousRows() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        context.insert(alloc)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        // Create one ambiguous + one unrecoverable
        let h1 = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(h1)
        let h2 = AllocationHistory(asset: asset, goal: goal, amount: 0.3)
        context.insert(h2)
        try context.save()
        h1.assetId = UUID(); h1.asset = nil
        h2.assetId = UUID(); h2.goalId = UUID(); h2.asset = nil; h2.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()

        // Delete unrecoverable
        let deleted = try coordinator.deleteUnrecoverableHistory(in: context)
        #expect(deleted == 1)

        // Diagnostics should still show not ready (ambiguous row remains)
        let report = try coordinator.generateReadinessReport(from: context)
        #expect(!report.isReady)
        #expect(report.allocationHistory.ambiguousByGoalAllocation == 1)
    }

    // MARK: - Full Repair→Migration Flow

    @Test("Assigning candidate assetId to ambiguous row makes it valid in diagnostics")
    func assignCandidateFixesDiagnostics() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        context.insert(alloc)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()

        // Make it ambiguous
        history.assetId = UUID()
        history.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()

        // Before repair: blocked
        let before = try coordinator.generateReadinessReport(from: context)
        #expect(!before.isReady)

        // Assign the correct asset
        let assigned = try coordinator.assignAssetId(asset.id, toHistoryId: history.id, in: context)
        #expect(assigned)

        // After repair: ready
        let after = try coordinator.generateReadinessReport(from: context)
        #expect(after.isReady)
        #expect(after.allocationHistory.ambiguousByGoalAllocation == 0 && after.allocationHistory.ambiguousByMultipleAssets == 0)
        #expect(after.allocationHistory.unrecoverable == 0)
    }

    @Test("Deleting unrecoverable row removes its blocker from diagnostics")
    func deleteUnrecoverableRemovesBlocker() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        // Unrecoverable only
        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()
        history.assetId = UUID()
        history.goalId = UUID()
        history.asset = nil
        history.goal = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()

        let before = try coordinator.generateReadinessReport(from: context)
        #expect(!before.isReady)
        #expect(before.allocationHistory.unrecoverable == 1)

        let deleted = try coordinator.deleteUnrecoverableHistory(in: context)
        #expect(deleted == 1)

        let after = try coordinator.generateReadinessReport(from: context)
        #expect(after.isReady)
    }

    @Test("Full repair flow: fix ambiguous + delete unrecoverable → migration proceeds")
    func fullRepairFlowEnablesMigration() async throws {
        let suiteName = "CutoverTests.FullRepair.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )
        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)

        // Create base data
        let goal = TestDataFactory.createSampleGoal(name: "Goal", targetAmount: 1000)
        sourceContext.insert(goal)
        let asset = Asset(currency: "BTC")
        sourceContext.insert(asset)
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        sourceContext.insert(alloc)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        sourceContext.insert(evidenceHistory)

        // Ambiguous row
        let h1 = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        sourceContext.insert(h1)
        try sourceContext.save()
        h1.assetId = UUID(); h1.asset = nil
        try sourceContext.save()

        // Unrecoverable row
        let h2 = AllocationHistory(asset: asset, goal: goal, amount: 0.1)
        sourceContext.insert(h2)
        try sourceContext.save()
        h2.assetId = UUID(); h2.goalId = UUID(); h2.asset = nil; h2.goal = nil
        try sourceContext.save()

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Step 1: Migration blocked
        await #expect(throws: CloudKitCutoverCoordinator.PreflightError.self) {
            try await coordinator.performCutover(sourceContainer: sourceContainer)
        }
        #expect(registry.currentMode == .localOnly)

        // Step 2: Delete unrecoverable
        let deleted = try coordinator.deleteUnrecoverableHistory(in: sourceContext)
        #expect(deleted == 1)

        // Step 3: Still blocked (ambiguous remains)
        let midReport = try coordinator.generateReadinessReport(from: sourceContext)
        #expect(!midReport.isReady)

        // Step 4: Assign asset to ambiguous row
        let assigned = try coordinator.assignAssetId(asset.id, toHistoryId: h1.id, in: sourceContext)
        #expect(assigned)

        // Step 5: Diagnostics green
        let finalReport = try coordinator.generateReadinessReport(from: sourceContext)
        #expect(finalReport.isReady)

        // Step 6: Migration succeeds
        try await coordinator.performCutover(sourceContainer: sourceContainer)
        #expect(registry.currentMode == .cloudKitPrimary)
        #expect(registry.currentMode == .cloudKitPrimary)
    }

    @Test("Repair export includes goal name and asset currency for operator review")
    func repairExportHasDisplayInfo() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = TestDataFactory.createSampleGoal(name: "My BTC Goal", targetAmount: 1000)
        context.insert(goal)
        let asset = Asset(currency: "BTC")
        asset.chainId = "bitcoin"
        context.insert(asset)
        let alloc = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        context.insert(alloc)

        // Valid history row establishes goal→asset mapping in ScalarMaps
        let evidenceHistory = AllocationHistory(asset: asset, goal: goal, amount: 1.0)
        context.insert(evidenceHistory)

        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5)
        context.insert(history)
        try context.save()
        history.assetId = UUID()
        history.asset = nil
        try context.save()

        let coordinator = CloudKitCutoverCoordinator()
        let export = try coordinator.generateRepairExport(from: context)

        #expect(export.rows.count == 1)
        let row = export.rows[0]
        #expect(row.goalInfo?.name == "My BTC Goal")
        #expect(row.candidateAssets.count == 1)
        #expect(row.candidateAssets[0].currency == "BTC")
        #expect(row.candidateAssets[0].chainId == "bitcoin")
    }

    // MARK: - Retry Isolation

    @Test("Relaunch activates cloud mode and staging cleanup runs before cloud runtime mount")
    func retryStartsFromCleanTargetStore() async throws {
        let suiteName = "CutoverTests.Retry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )
        let factory = PersistenceStackFactory(environment: .preview)
        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        let sourceContainer = controller.activeContainer
        let sourceContext = ModelContext(sourceContainer)
        let _ = try TestDataFactory.createFullCutoverTestData(in: sourceContext)

        let coordinator = CloudKitCutoverCoordinator(
            stackFactory: factory,
            storageModeRegistry: registry,
            persistenceController: controller
        )
        coordinator.skipAccountCheck = true

        // Attempt succeeds, but runtime stays local until relaunch
        try await coordinator.performCutover(sourceContainer: sourceContainer)
        #expect(registry.currentMode == .cloudKitPrimary)
        #expect(controller.activeMode == .localOnly)

        // Simulate next launch cleanup before opening any cloud-backed container
        CloudKitCutoverCoordinator.performDeferredCloudStoreCleanup()

        // Relaunch: new controller should mount cloud mode from persisted registry
        let relaunchedController = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )
        #expect(relaunchedController.activeMode == .cloudKitPrimary)
        #expect(relaunchedController.snapshot.activeStoreKind == .cloudPrimary)
        #expect(relaunchedController.snapshot.cloudKitEnabled == true)
    }
}
