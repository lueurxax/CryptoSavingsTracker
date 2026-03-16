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
    case localOnly
    case cloudPrimaryWithLocalMirror
    case cloudRollbackBlocked

    var displayName: String {
        switch self {
        case .localOnly:
            return "Local only"
        case .cloudPrimaryWithLocalMirror:
            return "Cloud primary with local mirror"
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
            return .localOnly
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
        backupStoreFilesIfNeededForCurrentBuild(descriptor: localPrimaryDescriptor)

        let activeDescriptor = localPrimaryDescriptor
        let modelConfiguration = ModelConfiguration(
            activeDescriptor.storeName,
            schema: Self.schema,
            isStoredInMemoryOnly: environment.isTestRun,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: Self.schema, configurations: [modelConfiguration])
        } catch {
            _ = backupStoreFilesIfPresent(descriptor: activeDescriptor)
            throw error
        }
    }

    func runtimeSnapshot(
        activeMode: AppStorageMode,
        selectedMode: AppStorageMode,
        lastModeUpdatedAt: Date?
    ) -> PersistenceRuntimeSnapshot {
        PersistenceRuntimeSnapshot(
            activeMode: activeMode,
            selectedMode: selectedMode,
            activeStoreKind: .localPrimary,
            localStorePath: localPrimaryDescriptor.storeURL?.path,
            cloudStorePath: cloudPrimaryDescriptor.storeURL?.path,
            cloudKitEnabled: false,
            migrationBlockers: migrationBlockers(activeMode: activeMode, selectedMode: selectedMode),
            lastModeUpdatedAt: lastModeUpdatedAt
        )
    }

    func migrationBlockers(activeMode: AppStorageMode, selectedMode: AppStorageMode) -> [PersistenceRuntimeBlocker] {
        var blockers: [PersistenceRuntimeBlocker] = []

        if activeMode == .localOnly {
            blockers.append(
                PersistenceRuntimeBlocker(
                    id: "runtime-disabled",
                    title: "CloudKit runtime is still disabled",
                    detail: "The active persistence controller still mounts the local primary store with CloudKit disabled."
                )
            )
        }

        if selectedMode != .localOnly {
            blockers.append(
                PersistenceRuntimeBlocker(
                    id: "stored-mode-blocked",
                    title: "Stored non-local mode cannot be activated yet",
                    detail: "The selected storage mode is \(selectedMode.rawValue), but runtime activation stays blocked until cutover infrastructure is implemented."
                )
            )
        }

        blockers.append(
            PersistenceRuntimeBlocker(
                id: "model-compatibility",
                title: "SwiftData model compatibility blockers remain open",
                detail: "CloudKit-safe schema validation still requires model and migration follow-up before runtime activation."
            )
        )
        blockers.append(
            PersistenceRuntimeBlocker(
                id: "container-validation",
                title: "CloudKit development-container validation is incomplete",
                detail: "Schema deployment and development-container validation must pass before CloudKit activation is allowed."
            )
        )
        blockers.append(
            PersistenceRuntimeBlocker(
                id: "local-migration-path",
                title: "Local-store migration path is not implemented",
                detail: "Existing local data still needs a verified migration path into the future cloud primary store without loss."
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

    @Published private(set) var snapshot: PersistenceRuntimeSnapshot
    let activeContainer: ModelContainer

    private let storageModeRegistry: StorageModeRegistry
    private let stackFactory: PersistenceStackFactory
    private let activeMode: AppStorageMode = .localOnly

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
        self.activeContainer = try! stackFactory.makeContainer(for: .localOnly)
        self.snapshot = stackFactory.runtimeSnapshot(
            activeMode: .localOnly,
            selectedMode: storageModeRegistry.currentMode,
            lastModeUpdatedAt: storageModeRegistry.lastUpdatedAt
        )
    }

    func refresh() {
        snapshot = stackFactory.runtimeSnapshot(
            activeMode: activeMode,
            selectedMode: storageModeRegistry.currentMode,
            lastModeUpdatedAt: storageModeRegistry.lastUpdatedAt
        )
    }

    func activate(mode: AppStorageMode) throws {
        guard mode == .localOnly else {
            let blockers = stackFactory
                .migrationBlockers(activeMode: activeMode, selectedMode: mode)
                .map(\.detail)
            throw PersistenceControllerError.activationBlocked(mode, blockers)
        }

        refresh()
    }
}
