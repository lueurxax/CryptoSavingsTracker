import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceControllerTests {
    private func makeRegistry(
        defaults: UserDefaults,
        modeKey: String = "test.mode",
        updatedAtKey: String = "test.updatedAt",
        seedMode: AppStorageMode? = nil
    ) -> UserDefaultsStorageModeRegistry {
        if let seedMode {
            defaults.set(seedMode.rawValue, forKey: modeKey)
            defaults.removeObject(forKey: updatedAtKey)
        }
        return UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: modeKey,
            updatedAtKey: updatedAtKey
        )
    }

    @Test("Storage mode registry persists selected mode and timestamp")
    func storageModeRegistryPersistsSelection() {
        let suiteName = "PersistenceControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let registry = makeRegistry(defaults: defaults)

        #expect(registry.currentMode == .cloudKitPrimary)
        #expect(registry.lastUpdatedAt == nil)

        registry.setMode(.cloudKitPrimary)

        #expect(registry.currentMode == .cloudKitPrimary)
        #expect(registry.lastUpdatedAt != nil)
    }

    @Test("Persistence stack factory reports deterministic local and cloud store paths")
    func persistenceStackFactoryReportsStorePaths() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let environment = PersistenceRuntimeEnvironment(
            isTestRun: false,
            appSupportURL: tempRoot,
            currentBuild: "test-build"
        )
        let factory = PersistenceStackFactory(environment: environment)

        let container = try factory.makeContainer(for: .localOnly)
        let context = ModelContext(container)
        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.isEmpty)

        let snapshot = factory.runtimeSnapshot(
            activeMode: .localOnly,
            selectedMode: .localOnly,
            lastModeUpdatedAt: nil
        )

        #expect(snapshot.localStorePath == tempRoot.appendingPathComponent("default.store").path)
        #expect(snapshot.cloudStorePath == tempRoot.appendingPathComponent("cloud-primary.store").path)
        #expect(snapshot.activeStoreKind == .localPrimary)
        #expect(snapshot.cloudKitEnabled == false)
    }

    // MARK: - Hot-Swap Proof

    @Test("After switchToCloudContainer, writes go to the new container, not the old one")
    func hotSwapProof() throws {
        let suiteName = "PersistenceControllerTests.HotSwap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let registry = makeRegistry(defaults: defaults, seedMode: .localOnly)

        // Use in-memory test environment (isTestRun = true)
        let factory = PersistenceStackFactory(
            environment: .preview
        )

        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        // 1. Verify initial state is local-only
        #expect(controller.activeMode == .localOnly)

        // 2. Capture a reference to the initial (local) container
        let localContainer = controller.activeContainer
        let localContext = localContainer.mainContext

        // Write a Goal to the local container to prove it's working
        let localGoal = Goal(
            name: "Local Goal", currency: "USD", targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 30)
        )
        localContext.insert(localGoal)
        try localContext.save()

        let localGoalCount = try localContext.fetchCount(FetchDescriptor<Goal>())
        #expect(localGoalCount == 1)

        // 3. Build a cloud container and hot-swap (mirrors cutover coordinator flow)
        let cloudContainer = try factory.makeContainer(for: .cloudKitPrimary)
        try controller.switchToContainer(cloudContainer, mode: .cloudKitPrimary)

        // 4. Verify controller state changed
        #expect(controller.activeMode == .cloudKitPrimary)
        #expect(controller.activeContainer !== localContainer)

        // 5. Write a new Goal through the controller's active context
        let cloudGoal = Goal(
            name: "Cloud Goal", currency: "BTC", targetAmount: 2.0,
            deadline: Date().addingTimeInterval(86400 * 60)
        )
        controller.activeMainContext.insert(cloudGoal)
        try controller.activeMainContext.save()

        // 6. The new Goal should be in the cloud container
        let cloudContext = controller.activeContainer.mainContext
        let cloudGoalCount = try cloudContext.fetchCount(FetchDescriptor<Goal>())
        #expect(cloudGoalCount == 1)

        // Verify it's the right goal
        let cloudGoals = try cloudContext.fetch(FetchDescriptor<Goal>())
        #expect(cloudGoals.first?.name == "Cloud Goal")

        // 7. The old local container should still have only the original local goal
        let localGoalCountAfter = try localContext.fetchCount(FetchDescriptor<Goal>())
        #expect(localGoalCountAfter == 1)
        let localGoals = try localContext.fetch(FetchDescriptor<Goal>())
        #expect(localGoals.first?.name == "Local Goal")
    }

    @Test("Persistence controller reconciles production bootstrap to cloud mode")
    func persistenceControllerReconcilesBootstrapToCloudMode() throws {
        let suiteName = "PersistenceControllerTests.Controller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let registry = makeRegistry(defaults: defaults)
        let factory = PersistenceStackFactory(
            environment: PersistenceRuntimeEnvironment(
                isTestRun: false,
                appSupportURL: tempRoot,
                currentBuild: "test-build"
            )
        )

        let controller = PersistenceController(
            storageModeRegistry: registry,
            stackFactory: factory
        )

        #expect(controller.snapshot.activeMode == .cloudKitPrimary)
        #expect(controller.snapshot.selectedMode == .cloudKitPrimary)
        #expect(controller.snapshot.migrationBlockers.isEmpty)

        controller.refresh()
        #expect(controller.snapshot.activeMode == .cloudKitPrimary)
        #expect(controller.snapshot.selectedMode == .cloudKitPrimary)
    }
}
