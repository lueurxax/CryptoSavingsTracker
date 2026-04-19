//
//  CloudKitHealthMonitor.swift
//  CryptoSavingsTracker
//
//  Monitors iCloud account status and CloudKit sync health
//  for the CloudKit-backed persistence runtime.
//

import CloudKit
import Combine
import Foundation
import os

@MainActor
final class CloudKitHealthMonitor: ObservableObject {

    // MARK: - Types

    enum AccountHealth: String, Equatable, Sendable {
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case unknown
    }

    enum SyncHealth: String, Equatable, Sendable {
        case idle
        case syncing
        case error
        case networkUnavailable
        case unknown
    }

    // MARK: - Published State

    @Published private(set) var accountHealth: AccountHealth = .unknown
    @Published private(set) var syncHealth: SyncHealth = .unknown
    @Published private(set) var lastSyncError: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "cloudkit-health")
    private var accountObserver: NSObjectProtocol?
    private var syncEventObserver: NSObjectProtocol?
    private var isMonitoring = false

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !shouldSkipCloudKitAccess else { return }
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Starting CloudKit health monitoring")

        // Check account status immediately
        Task {
            await refreshAccountStatus()
        }

        // Observe account changes
        accountObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAccountStatus()
            }
        }

        // Observe CloudKit sync events (Core Data bridge)
        // NSPersistentCloudKitContainer posts these when sync events occur
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainerEventChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleSyncEvent(notification)
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let observer = accountObserver {
            NotificationCenter.default.removeObserver(observer)
            accountObserver = nil
        }
        if let observer = syncEventObserver {
            NotificationCenter.default.removeObserver(observer)
            syncEventObserver = nil
        }

        logger.info("Stopped CloudKit health monitoring")
    }

    deinit {
        if let observer = accountObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = syncEventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Account Status

    func refreshAccountStatus() async {
        guard !shouldSkipCloudKitAccess else { return }

        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                accountHealth = .available
            case .noAccount:
                accountHealth = .noAccount
                logger.warning("No iCloud account signed in")
            case .restricted:
                accountHealth = .restricted
                logger.warning("iCloud account is restricted")
            case .temporarilyUnavailable:
                accountHealth = .temporarilyUnavailable
                logger.info("iCloud temporarily unavailable")
            case .couldNotDetermine:
                accountHealth = .unknown
            @unknown default:
                accountHealth = .unknown
            }
        } catch {
            accountHealth = .unknown
            logger.error("Failed to check account status: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync Events

    private func handleSyncEvent(_ notification: Notification) {
        // The notification userInfo contains the sync event type and any errors.
        // We use a best-effort approach since the exact API depends on the Core Data bridge.
        if let userInfo = notification.userInfo,
           let errorValue = userInfo["error"] {
            let errorString = String(describing: errorValue)
            syncHealth = .error
            lastSyncError = errorString
            logger.error("CloudKit sync error: \(errorString)")
        } else {
            let previousHealth = syncHealth
            syncHealth = .idle
            lastSyncError = nil

            // After a successful sync import, run deduplication to clean up
            // any conflicts CloudKit may have introduced.
            if previousHealth == .syncing || previousHealth == .unknown {
                triggerPostSyncDeduplication()
            }
        }
    }

    private func triggerPostSyncDeduplication() {
        Task { @MainActor in
            do {
                let context = PersistenceController.shared.activeMainContext
                try await DIContainer.shared.deduplicationService.runFullDeduplication(in: context)
                logger.info("Post-sync deduplication completed")
            } catch {
                logger.error("Post-sync deduplication failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Convenience

    var isCloudKitAvailable: Bool {
        accountHealth == .available
    }

    private var shouldSkipCloudKitAccess: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return Self.shouldSkipCloudKitAccess(for: .current())
        #endif
    }

    static func shouldSkipCloudKitAccess(for launchContext: BootstrapLaunchContext) -> Bool {
        launchContext.skipsStartupThrottle
    }

    var statusSummary: String {
        switch accountHealth {
        case .available:
            switch syncHealth {
            case .idle: return "iCloud Sync: Active"
            case .syncing: return "Syncing..."
            case .error: return "Sync Error"
            case .networkUnavailable: return "Offline"
            case .unknown: return "iCloud Sync: Active"
            }
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .temporarilyUnavailable:
            return "iCloud Temporarily Unavailable"
        case .unknown:
            return "Checking iCloud..."
        }
    }
}
