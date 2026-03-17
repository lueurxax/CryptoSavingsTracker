//
//  FamilyShareRollout.swift
//  CryptoSavingsTracker
//

import Foundation

protocol FamilyShareRemoteConfigProviding {
    nonisolated func boolValue(for key: String) -> Bool?
}

struct NullFamilyShareRemoteConfigProvider: FamilyShareRemoteConfigProviding, Sendable {
    nonisolated init() {}
    nonisolated func boolValue(for key: String) -> Bool? { nil }
}

protocol FamilyShareTelemetryProviding {
    nonisolated func track(event: String, payload: [String: String])
}

struct AppLogFamilyShareTelemetryProvider: FamilyShareTelemetryProviding, Sendable {
    nonisolated init() {}

    nonisolated func track(event: String, payload: [String: String]) {
        let ordered = payload
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        AppLog.info("[\(event)] \(ordered)", category: .ui)
    }
}

enum FamilyShareTelemetryEvent: String {
    case flagEvaluated = "family_share_flag_evaluated"
    case shareRequested = "family_share_requested"
    case sharePublished = "family_share_published"
    case sharePublishFailed = "family_share_publish_failed"
    case sharePrepareStarted = "family_share_prepare_started"
    case sharePrepared = "family_share_prepared"
    case sharePrepareFailed = "family_share_prepare_failed"
    case accepted = "family_share_accepted"
    case acceptFailed = "family_share_accept_failed"
    case revoked = "family_share_revoked"
    case refreshRequested = "family_share_refresh_requested"
    case refreshSucceeded = "family_share_refresh_succeeded"
    case refreshFailed = "family_share_refresh_failed"
    case migrationFailed = "family_share_namespace_migration_failed"
    case rebuildStarted = "family_share_namespace_rebuild_started"
    case rebuildSucceeded = "family_share_namespace_rebuild_succeeded"
}

protocol FamilyShareTelemetryTracking {
    nonisolated func track(_ event: FamilyShareTelemetryEvent, payload: [String: String])
}

struct FamilyShareTelemetryTracker: FamilyShareTelemetryTracking, Sendable {
    nonisolated(unsafe) private let provider: any FamilyShareTelemetryProviding

    nonisolated init(provider: FamilyShareTelemetryProviding = AppLogFamilyShareTelemetryProvider()) {
        self.provider = provider
    }

    nonisolated func track(_ event: FamilyShareTelemetryEvent, payload: [String: String] = [:]) {
        provider.track(event: event.rawValue, payload: payload)
    }
}

final class FamilyShareRollout: @unchecked Sendable {
    nonisolated static let flagEnabled = "family_readonly_sharing_enabled"

    private enum Source: String {
        case releaseDefault = "release_default"
        case remoteConfig = "remote_config"
        case debugOverride = "debug_override"
    }

    nonisolated static let shared = FamilyShareRollout(
        remoteConfigProvider: NullFamilyShareRemoteConfigProvider(),
        telemetryProvider: AppLogFamilyShareTelemetryProvider()
    )

    nonisolated(unsafe) private let remoteConfigProvider: any FamilyShareRemoteConfigProviding
    nonisolated(unsafe) private let telemetryProvider: any FamilyShareTelemetryProviding
    nonisolated(unsafe) private let userDefaults: UserDefaults
    nonisolated(unsafe) private let nowProvider: () -> Date

    nonisolated init(
        remoteConfigProvider: FamilyShareRemoteConfigProviding,
        telemetryProvider: FamilyShareTelemetryProviding,
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.remoteConfigProvider = remoteConfigProvider
        self.telemetryProvider = telemetryProvider
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
    }

    nonisolated func isEnabled() -> Bool {
        let (value, source) = resolvedValue()
        telemetryProvider.track(
            event: FamilyShareTelemetryEvent.flagEvaluated.rawValue,
            payload: [
                "enabled": value ? "true" : "false",
                "source": source.rawValue,
                "timestamp": ISO8601DateFormatter().string(from: nowProvider())
            ]
        )
        return value
    }

    nonisolated func setDebugOverride(_ value: Bool?) {
        let key = Self.flagEnabled + ".debug_override"
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    nonisolated private func resolvedValue() -> (Bool, Source) {
        var value = true
        var source: Source = .releaseDefault

        if let remoteValue = remoteConfigProvider.boolValue(for: Self.flagEnabled) {
            value = remoteValue
            source = .remoteConfig
        }

        let key = Self.flagEnabled + ".debug_override"
        if let debugValue = userDefaults.object(forKey: key) as? Bool {
            value = debugValue
            source = .debugOverride
        }

        return (value, source)
    }
}
