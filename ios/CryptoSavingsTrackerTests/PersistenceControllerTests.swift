import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceControllerTests {

    @Test("Storage mode registry persists selected mode and timestamp")
    func storageModeRegistryPersistsSelection() {
        let suiteName = "PersistenceControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )

        #expect(registry.currentMode == .localOnly)
        #expect(registry.lastUpdatedAt == nil)

        registry.setMode(.cloudPrimaryWithLocalMirror)

        #expect(registry.currentMode == .cloudPrimaryWithLocalMirror)
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

    @Test("Persistence controller boots local-only and blocks cloud activation")
    func persistenceControllerBlocksCloudActivation() throws {
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

        let registry = UserDefaultsStorageModeRegistry(
            userDefaults: defaults,
            modeKey: "test.mode",
            updatedAtKey: "test.updatedAt"
        )
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

        #expect(controller.snapshot.activeMode == .localOnly)
        #expect(controller.snapshot.selectedMode == .localOnly)
        // In local-only mode there is exactly 1 informational blocker
        #expect(controller.snapshot.migrationBlockers.count == 1)

        controller.refresh()
        #expect(controller.snapshot.activeMode == .localOnly)
        #expect(controller.snapshot.selectedMode == .localOnly)
    }
}
