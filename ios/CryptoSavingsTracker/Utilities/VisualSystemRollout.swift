import Foundation

enum VisualSystemFlow: String, CaseIterable {
    case planning
    case dashboard
    case settings

    var waveKey: String {
        switch self {
        case .planning:
            return VisualSystemRollout.flagWave1Planning
        case .dashboard:
            return VisualSystemRollout.flagWave2Dashboard
        case .settings:
            return VisualSystemRollout.flagWave3Settings
        }
    }

    var waveName: String {
        switch self {
        case .planning:
            return "wave1"
        case .dashboard:
            return "wave2"
        case .settings:
            return "wave3"
        }
    }
}

protocol VisualSystemRemoteConfigProviding {
    func boolValue(for key: String) -> Bool?
}

struct NullVisualSystemRemoteConfigProvider: VisualSystemRemoteConfigProviding {
    func boolValue(for key: String) -> Bool? { nil }
}

protocol VisualSystemTelemetryProviding {
    func track(event: String, payload: [String: String])
}

struct AppLogVisualSystemTelemetryProvider: VisualSystemTelemetryProviding {
    func track(event: String, payload: [String: String]) {
        let ordered = payload
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        AppLog.info("[\(event)] \(ordered)", category: .ui)
    }
}

final class VisualSystemRollout {
    static let flagWave1Planning = "visual_system.wave1_planning"
    static let flagWave2Dashboard = "visual_system.wave2_dashboard"
    static let flagWave3Settings = "visual_system.wave3_settings"

    private enum Source: String {
        case releaseDefault = "release_default"
        case remoteConfig = "remote_config"
        case debugOverride = "debug_override"
    }

    static let shared = VisualSystemRollout(
        remoteConfigProvider: NullVisualSystemRemoteConfigProvider(),
        telemetryProvider: AppLogVisualSystemTelemetryProvider()
    )

    private let remoteConfigProvider: VisualSystemRemoteConfigProviding
    private let telemetryProvider: VisualSystemTelemetryProviding
    private let userDefaults: UserDefaults
    private let nowProvider: () -> Date
    private var lastEvaluatedValues: [VisualSystemFlow: Bool] = [:]

    init(
        remoteConfigProvider: VisualSystemRemoteConfigProviding,
        telemetryProvider: VisualSystemTelemetryProviding,
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.remoteConfigProvider = remoteConfigProvider
        self.telemetryProvider = telemetryProvider
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
    }

    func isEnabled(flow: VisualSystemFlow) -> Bool {
        let (value, source) = resolvedValue(for: flow)
        emit(
            event: "vsu_flag_evaluated",
            flow: flow,
            source: source
        )

        let previous = lastEvaluatedValues[flow]
        if previous == true, value == false {
            emit(
                event: "vsu_wave_rollback_triggered",
                flow: flow,
                source: source
            )
            emit(
                event: "vsu_wave_rollback_completed",
                flow: flow,
                source: source
            )
        }
        lastEvaluatedValues[flow] = value
        return value
    }

    func setDebugOverride(_ value: Bool?, for flow: VisualSystemFlow) {
        let key = debugOverrideKey(for: flow)
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func resolvedValue(for flow: VisualSystemFlow) -> (Bool, Source) {
        let releaseDefault = false
        var value = releaseDefault
        var source: Source = .releaseDefault

        if let remoteValue = remoteConfigProvider.boolValue(for: flow.waveKey) {
            value = remoteValue
            source = .remoteConfig
        }

        if let debugValue = userDefaults.object(forKey: debugOverrideKey(for: flow)) as? Bool {
            value = debugValue
            source = .debugOverride
        }

        return (value, source)
    }

    private func debugOverrideKey(for flow: VisualSystemFlow) -> String {
        "visual_system.debug_override.\(flow.waveKey)"
    }

    private func emit(event: String, flow: VisualSystemFlow, source: Source) {
        let timestamp = ISO8601DateFormatter().string(from: nowProvider())
        telemetryProvider.track(
            event: event,
            payload: [
                "wave": flow.waveName,
                "flow": flow.rawValue,
                "source": source.rawValue,
                "timestamp": timestamp
            ]
        )
    }
}
