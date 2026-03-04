import Foundation

enum NavigationTelemetryEvent: String, CaseIterable {
    case flowStarted = "nav_flow_started"
    case flowCompleted = "nav_flow_completed"
    case cancelled = "nav_cancelled"
    case discardConfirmed = "nav_discard_confirmed"
    case recoveryCompleted = "nav_recovery_completed"
    case goalDashboardOpened = "goal_dashboard_opened"
    case goalDashboardPrimaryCtaShown = "goal_dashboard_primary_cta_shown"
    case goalDashboardPrimaryCtaTapped = "goal_dashboard_primary_cta_tapped"
}

enum NavigationJourney {
    static let goalCreateEdit = "goal-create-edit"
    static let monthlyBudgetAdjust = "monthly-budget-adjust"
    static let destructiveDeleteConfirmation = "destructive-delete-confirmation"
    static let goalContributionEditCancel = "goal-contribution-edit-cancel"
    static let planningFlowCancelRecovery = "planning-flow-cancel-recovery"
    static let goalDashboard = "goal-dashboard"

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
    let goalID: String?
    let resolverState: String?
    let ctaID: String?

    init(
        event: NavigationTelemetryEvent,
        journeyID: String,
        platform: String,
        entryPoint: String?,
        durationMs: Int?,
        result: String?,
        isDirty: Bool?,
        cancelStage: String?,
        formType: String?,
        recoveryPath: String?,
        success: Bool?,
        goalID: String? = nil,
        resolverState: String? = nil,
        ctaID: String? = nil
    ) {
        self.event = event
        self.journeyID = journeyID
        self.platform = platform
        self.entryPoint = entryPoint
        self.durationMs = durationMs
        self.result = result
        self.isDirty = isDirty
        self.cancelStage = cancelStage
        self.formType = formType
        self.recoveryPath = recoveryPath
        self.success = success
        self.goalID = goalID
        self.resolverState = resolverState
        self.ctaID = ctaID
    }

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
        if let goalID { values["goal_id"] = goalID }
        if let resolverState { values["resolver_state"] = resolverState }
        if let ctaID { values["cta_id"] = ctaID }

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
        case .goalDashboardOpened:
            return missing(["journey_id", "platform", "goal_id", "entry_point"])
        case .goalDashboardPrimaryCtaShown, .goalDashboardPrimaryCtaTapped:
            return missing(["journey_id", "platform", "goal_id", "resolver_state", "cta_id"])
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
                success: nil,
                goalID: nil,
                resolverState: nil,
                ctaID: nil
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
                success: nil,
                goalID: nil,
                resolverState: nil,
                ctaID: nil
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
                success: nil,
                goalID: nil,
                resolverState: nil,
                ctaID: nil
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
                success: nil,
                goalID: nil,
                resolverState: nil,
                ctaID: nil
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
                success: success,
                goalID: nil,
                resolverState: nil,
                ctaID: nil
            )
        )
    }

    func goalDashboardOpened(goalID: String, entryPoint: String) {
        emit(
            NavigationTelemetryPayload(
                event: .goalDashboardOpened,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: entryPoint,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: goalID,
                resolverState: nil,
                ctaID: nil
            )
        )
    }

    func goalDashboardPrimaryCtaShown(goalID: String, resolverState: String, ctaID: String) {
        emit(
            NavigationTelemetryPayload(
                event: .goalDashboardPrimaryCtaShown,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: goalID,
                resolverState: resolverState,
                ctaID: ctaID
            )
        )
    }

    func goalDashboardPrimaryCtaTapped(goalID: String, resolverState: String, ctaID: String) {
        emit(
            NavigationTelemetryPayload(
                event: .goalDashboardPrimaryCtaTapped,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: goalID,
                resolverState: resolverState,
                ctaID: ctaID
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
