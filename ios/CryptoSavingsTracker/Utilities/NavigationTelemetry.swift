import Foundation

enum NavigationTelemetryEvent: String, CaseIterable {
    case flowStarted = "nav_flow_started"
    case flowCompleted = "nav_flow_completed"
    case cancelled = "nav_cancelled"
    case discardConfirmed = "nav_discard_confirmed"
    case recoveryCompleted = "nav_recovery_completed"
}

enum NavigationJourney {
    static let goalCreateEdit = "goal-create-edit"
    static let monthlyBudgetAdjust = "monthly-budget-adjust"
    static let destructiveDeleteConfirmation = "destructive-delete-confirmation"
    static let goalContributionEditCancel = "goal-contribution-edit-cancel"
    static let planningFlowCancelRecovery = "planning-flow-cancel-recovery"

    static let top5: [String] = [
        goalCreateEdit,
        monthlyBudgetAdjust,
        destructiveDeleteConfirmation,
        goalContributionEditCancel,
        planningFlowCancelRecovery
    ]
}

struct NavigationTelemetryPayload {
    let event: NavigationTelemetryEvent
    let journeyID: String
    let platform: String
    let entryPoint: String?
    let durationMs: Int?
    let result: String?
    let isDirty: Bool?
    let cancelStage: String?
    let formType: String?
    let recoveryPath: String?
    let success: Bool?

    var properties: [String: String] {
        var values: [String: String] = [
            "journey_id": journeyID,
            "platform": platform
        ]

        if let entryPoint { values["entry_point"] = entryPoint }
        if let durationMs { values["duration_ms"] = String(durationMs) }
        if let result { values["result"] = result }
        if let isDirty { values["is_dirty"] = isDirty ? "true" : "false" }
        if let cancelStage { values["cancel_stage"] = cancelStage }
        if let formType { values["form_type"] = formType }
        if let recoveryPath { values["recovery_path"] = recoveryPath }
        if let success { values["success"] = success ? "true" : "false" }

        return values
    }

    func requiredFieldViolations() -> [String] {
        switch event {
        case .flowStarted:
            return missing(["journey_id", "platform", "entry_point"])
        case .flowCompleted:
            return missing(["journey_id", "platform", "duration_ms", "result"])
        case .cancelled:
            return missing(["journey_id", "platform", "is_dirty", "cancel_stage"])
        case .discardConfirmed:
            return missing(["journey_id", "platform", "form_type"])
        case .recoveryCompleted:
            return missing(["journey_id", "platform", "recovery_path", "success"])
        }
    }

    private func missing(_ required: [String]) -> [String] {
        let values = properties
        return required.filter { key in
            guard let value = values[key] else {
                return true
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

protocol NavigationTelemetryProvider {
    func track(_ payload: NavigationTelemetryPayload)
}

struct AppLogNavigationTelemetryProvider: NavigationTelemetryProvider {
    func track(_ payload: NavigationTelemetryPayload) {
        let ordered = payload.properties
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")

        let violations = payload.requiredFieldViolations()
        if !violations.isEmpty {
            AppLog.warning(
                "[\(payload.event.rawValue)] schema_violation=\(violations.joined(separator: "|")) \(ordered)",
                category: .ui
            )
        }

        AppLog.info("[\(payload.event.rawValue)] \(ordered)", category: .ui)
    }
}

@MainActor
final class NavigationTelemetryTracker {
    private let provider: NavigationTelemetryProvider
    private let clock: () -> Date
    private let dedupeWindowMs: Int

    private var flowStartDates: [String: Date] = [:]
    private var lastEventByFingerprint: [String: Date] = [:]

    init(
        provider: NavigationTelemetryProvider,
        clock: @escaping () -> Date = { Date() },
        dedupeWindowMs: Int = 800
    ) {
        self.provider = provider
        self.clock = clock
        self.dedupeWindowMs = dedupeWindowMs
    }

    func flowStarted(journeyID: String, entryPoint: String) {
        flowStartDates[journeyID] = clock()
        emit(
            NavigationTelemetryPayload(
                event: .flowStarted,
                journeyID: journeyID,
                platform: "ios",
                entryPoint: entryPoint,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil
            )
        )
    }

    func flowCompleted(journeyID: String, result: String = "success") {
        let now = clock()
        let startedAt = flowStartDates[journeyID] ?? now
        let durationMs = max(0, Int(now.timeIntervalSince(startedAt) * 1000))
        flowStartDates.removeValue(forKey: journeyID)

        emit(
            NavigationTelemetryPayload(
                event: .flowCompleted,
                journeyID: journeyID,
                platform: "ios",
                entryPoint: nil,
                durationMs: durationMs,
                result: result,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil
            )
        )
    }

    func cancelled(journeyID: String, isDirty: Bool, cancelStage: String) {
        emit(
            NavigationTelemetryPayload(
                event: .cancelled,
                journeyID: journeyID,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: isDirty,
                cancelStage: cancelStage,
                formType: nil,
                recoveryPath: nil,
                success: nil
            )
        )
    }

    func discardConfirmed(journeyID: String, formType: String) {
        emit(
            NavigationTelemetryPayload(
                event: .discardConfirmed,
                journeyID: journeyID,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: formType,
                recoveryPath: nil,
                success: nil
            )
        )
    }

    func recoveryCompleted(journeyID: String, recoveryPath: String, success: Bool) {
        emit(
            NavigationTelemetryPayload(
                event: .recoveryCompleted,
                journeyID: journeyID,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: recoveryPath,
                success: success
            )
        )
    }

    private func emit(_ payload: NavigationTelemetryPayload) {
        let fingerprint = [payload.event.rawValue] + payload.properties.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
        let key = fingerprint.joined(separator: "|")
        let now = clock()

        if let last = lastEventByFingerprint[key] {
            let deltaMs = Int(now.timeIntervalSince(last) * 1000)
            if deltaMs < dedupeWindowMs {
                return
            }
        }

        lastEventByFingerprint[key] = now
        provider.track(payload)
    }
}
