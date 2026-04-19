//
//  PersistenceController.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 16/03/2026.
//

import Combine
import Foundation
import SwiftData

enum AppStorageMode: String, Codable, CaseIterable, Sendable {
    /// Legacy compatibility value retained only for tests and old UserDefaults values.
    /// Production runtime no longer supports local-only primary storage.
    case localOnly
    /// CloudKit is the only supported primary store for authoritative application data.
    case cloudKitPrimary
    /// Rollback to local-only is no longer available.
    case cloudRollbackBlocked

    // Legacy key kept only for UserDefaults deserialization of pre-rename values.
    init?(rawValue: String) {
        switch rawValue {
        case "localOnly": self = .localOnly
        case "cloudKitPrimary", "cloudPrimaryWithLocalMirror": self = .cloudKitPrimary
        case "cloudRollbackBlocked": self = .cloudRollbackBlocked
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .localOnly:
            return "Local only"
        case .cloudKitPrimary:
            return "CloudKit primary"
        case .cloudRollbackBlocked:
            return "Cloud rollback blocked"
        }
    }
}

enum PersistenceStoreKind: String, Codable, Sendable {
    case localPrimary
    case cloudPrimary

    var displayName: String {
        switch self {
        case .localPrimary:
            return "Local primary"
        case .cloudPrimary:
            return "Cloud primary"
        }
    }
}

struct PersistenceStoreDescriptor: Equatable, Codable, Sendable {
    let kind: PersistenceStoreKind
    let storeName: String
    let storeURL: URL?
    let cloudKitEnabled: Bool
}

struct PersistenceRuntimeBlocker: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct PersistenceRuntimeSnapshot: Equatable, Codable, Sendable {
    let activeMode: AppStorageMode
    let selectedMode: AppStorageMode
    let activeStoreKind: PersistenceStoreKind
    let localStorePath: String?
    let cloudStorePath: String?
    let cloudKitEnabled: Bool
    let migrationBlockers: [PersistenceRuntimeBlocker]
    let lastModeUpdatedAt: Date?
}

protocol StorageModeRegistry: AnyObject {
    var currentMode: AppStorageMode { get }
    var lastUpdatedAt: Date? { get }
    func setMode(_ mode: AppStorageMode)
}

final class UserDefaultsStorageModeRegistry: StorageModeRegistry {
    private let userDefaults: UserDefaults
    private let modeKey: String
    private let updatedAtKey: String

    init(
        userDefaults: UserDefaults = .standard,
        modeKey: String = "Persistence.StorageMode",
        updatedAtKey: String = "Persistence.StorageModeUpdatedAt"
    ) {
        self.userDefaults = userDefaults
        self.modeKey = modeKey
        self.updatedAtKey = updatedAtKey
    }

    var currentMode: AppStorageMode {
        guard let rawValue = userDefaults.string(forKey: modeKey),
              let mode = AppStorageMode(rawValue: rawValue) else {
            return .cloudKitPrimary
        }
        return mode
    }

    var lastUpdatedAt: Date? {
        userDefaults.object(forKey: updatedAtKey) as? Date
    }

    func setMode(_ mode: AppStorageMode) {
        userDefaults.set(mode.rawValue, forKey: modeKey)
        userDefaults.set(Date(), forKey: updatedAtKey)
    }
}

struct PersistenceRuntimeEnvironment: Equatable, Sendable {
    let isTestRun: Bool
    let appSupportURL: URL?
    let currentBuild: String

    static func current(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Self {
        let args = processInfo.arguments
        let isXCTestRun = processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
        let isPreviewRun = processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let isTestRun = isXCTestRun || isUITestRun || isPreviewRun

        let appSupport = isTestRun
            ? nil
            : fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let currentBuild = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"

        return Self(isTestRun: isTestRun, appSupportURL: appSupport, currentBuild: currentBuild)
    }

    static var preview: Self {
        Self(isTestRun: true, appSupportURL: nil, currentBuild: "preview")
    }
}

enum PersistenceControllerError: LocalizedError {
    case activationBlocked(AppStorageMode, [String])

    var errorDescription: String? {
        switch self {
        case .activationBlocked(let mode, let reasons):
            let joinedReasons = reasons.joined(separator: " ")
            return "Activation for \(mode.rawValue) is blocked. \(joinedReasons)"
        }
    }
}

struct PersistenceStackFactory {
    let environment: PersistenceRuntimeEnvironment
    let fileManager: FileManager

    init(
        environment: PersistenceRuntimeEnvironment = .current(),
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    static var schema: Schema {
        Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            AllocationHistory.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            CompletionEvent.self,
            ExecutionSnapshot.self
        ])
    }

    var backupRootURL: URL? {
        environment.appSupportURL?.appendingPathComponent("StoreBackups", isDirectory: true)
    }

    var localPrimaryDescriptor: PersistenceStoreDescriptor {
        PersistenceStoreDescriptor(
            kind: .localPrimary,
            storeName: "default",
            storeURL: environment.appSupportURL?.appendingPathComponent("default.store"),
            cloudKitEnabled: false
        )
    }

    var cloudPrimaryDescriptor: PersistenceStoreDescriptor {
        PersistenceStoreDescriptor(
            kind: .cloudPrimary,
            storeName: "cloud-primary",
            storeURL: environment.appSupportURL?.appendingPathComponent("cloud-primary.store"),
            cloudKitEnabled: true
        )
    }

    var cloudPrimaryStagingDescriptor: PersistenceStoreDescriptor {
        PersistenceStoreDescriptor(
            kind: .cloudPrimary,
            storeName: "cloud-primary-staging",
            storeURL: environment.appSupportURL?.appendingPathComponent("cloud-primary-staging.store"),
            cloudKitEnabled: false
        )
    }

    func ensureApplicationSupportDirectoryExists() {
        guard let appSupportURL = environment.appSupportURL else { return }
        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    }

    func backupStoreFilesIfPresent(descriptor: PersistenceStoreDescriptor) -> Int {
        guard !environment.isTestRun else { return 0 }
        guard let storeURL = descriptor.storeURL else { return 0 }
        guard let backupRootURL else { return 0 }

        let candidatePaths = [
            storeURL.path,
            storeURL.path + "-shm",
            storeURL.path + "-wal",
            storeURL.path + "-journal"
        ]

        let existingPaths = candidatePaths.filter { fileManager.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else { return 0 }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let backupFolder = backupRootURL.appendingPathComponent(
            "\(descriptor.storeName).store.backup-\(timestamp)",
            isDirectory: true
        )
        try? fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        var copiedCount = 0
        for path in existingPaths {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let destination = backupFolder.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                try fileManager.copyItem(atPath: path, toPath: destination.path)
                copiedCount += 1
            } catch {
                continue
            }
        }
        return copiedCount
    }

    func backupStoreFilesIfNeededForCurrentBuild(descriptor: PersistenceStoreDescriptor) {
        guard !environment.isTestRun else { return }
        let backupKey = "StoreBackups.lastBackedUpBuild.\(descriptor.storeName)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: backupKey) != environment.currentBuild else { return }
        let copied = backupStoreFilesIfPresent(descriptor: descriptor)
        if copied > 0 {
            defaults.set(environment.currentBuild, forKey: backupKey)
        }
    }

    func makeContainer(for mode: AppStorageMode) throws -> ModelContainer {
        ensureApplicationSupportDirectoryExists()

        let activeDescriptor: PersistenceStoreDescriptor
        let cloudKitSetting: ModelConfiguration.CloudKitDatabase

        switch mode {
        case .localOnly:
            activeDescriptor = localPrimaryDescriptor
            cloudKitSetting = makeCloudKitSetting(enabled: false)
        case .cloudKitPrimary, .cloudRollbackBlocked:
            activeDescriptor = cloudPrimaryDescriptor
            cloudKitSetting = makeCloudKitSetting(enabled: true)
        }

        backupStoreFilesIfNeededForCurrentBuild(descriptor: activeDescriptor)

        let modelConfiguration = ModelConfiguration(
            activeDescriptor.storeName,
            schema: Self.schema,
            isStoredInMemoryOnly: environment.isTestRun,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: cloudKitSetting
        )

        do {
            return try ModelContainer(for: Self.schema, configurations: [modelConfiguration])
        } catch {
            _ = backupStoreFilesIfPresent(descriptor: activeDescriptor)
            throw error
        }
    }

    func makeContainer(
        descriptor: PersistenceStoreDescriptor,
        cloudKitEnabled: Bool
    ) throws -> ModelContainer {
        ensureApplicationSupportDirectoryExists()

        let cloudKitSetting = makeCloudKitSetting(enabled: cloudKitEnabled)
        let modelConfiguration = ModelConfiguration(
            descriptor.storeName,
            schema: Self.schema,
            isStoredInMemoryOnly: environment.isTestRun,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: cloudKitSetting
        )

        return try ModelContainer(for: Self.schema, configurations: [modelConfiguration])
    }

    private func makeCloudKitSetting(enabled: Bool) -> ModelConfiguration.CloudKitDatabase {
        guard enabled, !environment.isTestRun else {
            return .none
        }
        return .automatic
    }

    func removeStoreFiles(descriptor: PersistenceStoreDescriptor) {
        guard let storeURL = descriptor.storeURL else { return }
        let suffixes = ["", "-shm", "-wal", "-journal"]
        for suffix in suffixes {
            let path = storeURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    func replaceStoreFiles(from source: PersistenceStoreDescriptor, to destination: PersistenceStoreDescriptor) throws {
        guard let sourceURL = source.storeURL, let destinationURL = destination.storeURL else { return }

        ensureApplicationSupportDirectoryExists()
        removeStoreFiles(descriptor: destination)

        let suffixes = ["", "-shm", "-wal", "-journal"]
        for suffix in suffixes {
            let sourcePath = sourceURL.path + suffix
            guard fileManager.fileExists(atPath: sourcePath) else { continue }
            let destinationPath = destinationURL.path + suffix
            try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
        }
    }

    func storeFilesExist(descriptor: PersistenceStoreDescriptor) -> Bool {
        guard let storeURL = descriptor.storeURL else { return false }
        let suffixes = ["", "-shm", "-wal", "-journal"]
        return suffixes.contains { suffix in
            fileManager.fileExists(atPath: storeURL.path + suffix)
        }
    }

    func runtimeSnapshot(
        activeMode: AppStorageMode,
        selectedMode: AppStorageMode,
        lastModeUpdatedAt: Date?
    ) -> PersistenceRuntimeSnapshot {
        let storeKind: PersistenceStoreKind
        let cloudKitEnabled: Bool
        switch activeMode {
        case .localOnly:
            storeKind = .localPrimary
            cloudKitEnabled = false
        case .cloudKitPrimary, .cloudRollbackBlocked:
            storeKind = .cloudPrimary
            cloudKitEnabled = true
        }

        return PersistenceRuntimeSnapshot(
            activeMode: activeMode,
            selectedMode: selectedMode,
            activeStoreKind: storeKind,
            localStorePath: localPrimaryDescriptor.storeURL?.path,
            cloudStorePath: cloudPrimaryDescriptor.storeURL?.path,
            cloudKitEnabled: cloudKitEnabled,
            migrationBlockers: migrationBlockers(activeMode: activeMode, selectedMode: selectedMode),
            lastModeUpdatedAt: lastModeUpdatedAt
        )
    }

    func migrationBlockers(activeMode: AppStorageMode, selectedMode: AppStorageMode) -> [PersistenceRuntimeBlocker] {
        // If already running on CloudKit, no blockers
        if activeMode == .cloudKitPrimary || activeMode == .cloudRollbackBlocked {
            return []
        }

        if selectedMode == .cloudKitPrimary || selectedMode == .cloudRollbackBlocked {
            return [
                PersistenceRuntimeBlocker(
                    id: "relaunch-required",
                    title: "Relaunch required",
                    detail: "Migration data is prepared. Close and reopen the app to activate CloudKit runtime."
                )
            ]
        }

        // In local-only mode, report what's needed to migrate
        var blockers: [PersistenceRuntimeBlocker] = []

        blockers.append(
            PersistenceRuntimeBlocker(
                id: "runtime-disabled",
                title: "CloudKit runtime is not active",
                detail: "The app is still pointed at the retired local-only mode. Relaunch on the CloudKit primary runtime or clear stale configuration."
            )
        )

        return blockers
    }

    static func makePreviewContainer() -> ModelContainer {
        let previewFactory = PersistenceStackFactory(environment: .preview)
        return try! previewFactory.makeContainer(for: .localOnly)
    }
}

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    static let pendingCloudCleanupKey = "CloudKit.PendingStoreCleanup"
    static let pendingStagingCleanupKey = "CloudKit.PendingStagingStoreCleanup"

    @Published private(set) var snapshot: PersistenceRuntimeSnapshot
    @Published private(set) var activeContainer: ModelContainer

    private let storageModeRegistry: StorageModeRegistry
    let stackFactory: PersistenceStackFactory
    private(set) var activeMode: AppStorageMode

    var activeMainContext: ModelContext {
        activeContainer.mainContext
    }

    convenience init() {
        self.init(
            storageModeRegistry: UserDefaultsStorageModeRegistry(),
            stackFactory: PersistenceStackFactory()
        )
    }

    init(
        storageModeRegistry: StorageModeRegistry,
        stackFactory: PersistenceStackFactory
    ) {
        self.storageModeRegistry = storageModeRegistry
        self.stackFactory = stackFactory
        let mode = Self.resolveBootMode(
            registryMode: storageModeRegistry.currentMode,
            storageModeRegistry: storageModeRegistry,
            stackFactory: stackFactory
        )
        self.activeMode = mode
        self.activeContainer = try! stackFactory.makeContainer(for: mode)
        self.snapshot = stackFactory.runtimeSnapshot(
            activeMode: mode,
            selectedMode: storageModeRegistry.currentMode,
            lastModeUpdatedAt: storageModeRegistry.lastUpdatedAt
        )
    }

    static func performDeferredCloudStoreCleanupIfNeeded() {
        let cleanupTargets = [
            (pendingCloudCleanupKey, "cloud store"),
            (pendingStagingCleanupKey, "staging store")
        ]

        for (key, label) in cleanupTargets {
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
            AppLog.info(
                "Deferred \(label) cleanup: removed \(removed) file(s) at \(storePath)",
                category: .swiftData
            )
        }
    }

    static func performLegacyLocalStoreCleanupIfNeeded() {
        let stackFactory = PersistenceStackFactory()
        guard !stackFactory.environment.isTestRun else { return }

        let descriptor = stackFactory.localPrimaryDescriptor
        guard stackFactory.storeFilesExist(descriptor: descriptor) else { return }

        stackFactory.removeStoreFiles(descriptor: descriptor)
        AppLog.info(
            "Removed retired local-primary store files after CloudKit hard cutover",
            category: .swiftData
        )
    }

    private static func resolveBootMode(
        registryMode: AppStorageMode,
        storageModeRegistry: StorageModeRegistry,
        stackFactory: PersistenceStackFactory
    ) -> AppStorageMode {
        guard !stackFactory.environment.isTestRun else { return registryMode }

        if registryMode != .cloudKitPrimary {
            storageModeRegistry.setMode(.cloudKitPrimary)
            AppLog.warning(
                "Reconciled startup mode to CloudKit primary; legacy local runtime is retired",
                category: .swiftData
            )
        }

        return .cloudKitPrimary
    }

    func refresh() {
        snapshot = stackFactory.runtimeSnapshot(
            activeMode: activeMode,
            selectedMode: storageModeRegistry.currentMode,
            lastModeUpdatedAt: storageModeRegistry.lastUpdatedAt
        )
    }

    func activate(mode: AppStorageMode) throws {
        if mode == .localOnly {
            throw PersistenceControllerError.activationBlocked(
                mode,
                ["Legacy local runtime has been removed. Authoritative application data now lives only in CloudKit."]
            )
        }

        // Mode changes require app restart — the container is created at init time.
        // This method validates that the requested mode is achievable and updates the registry.
        if mode != .localOnly && activeMode == .localOnly {
            // Cutover coordinator handles the actual migration. This just validates.
            let blockers = stackFactory
                .migrationBlockers(activeMode: activeMode, selectedMode: mode)
            if !blockers.isEmpty {
                throw PersistenceControllerError.activationBlocked(mode, blockers.map(\.detail))
            }
        }

        refresh()
    }

    /// Hot-swap the active container to a pre-built container.
    /// Called by the cutover coordinator after copy+validate succeed.
    /// The caller is responsible for persisting the mode to the registry
    /// only AFTER this method returns successfully.
    func switchToContainer(_ container: ModelContainer, mode: AppStorageMode) throws {
        activeMode = mode
        activeContainer = container
        refresh()
        AppLog.info("Hot-swapped to \(mode.displayName) container", category: .swiftData)
    }
}
