//
//  MonthlyCycleActionGate.swift
//  CryptoSavingsTracker
//
//  Canonical action matrix: UiCycleState x Action -> allow/block + copy key.
//

import Foundation

enum MonthlyCycleAction {
    case startTracking
    case finishMonth
    case undoStart
    case undoCompletion
}

enum MonthlyCycleBlockedCopyKey {
    case startBlockedAlreadyExecuting
    case startBlockedClosedMonth
    case finishBlockedNoExecuting
    case undoStartExpired
    case undoCompletionExpired
    case recordConflict
}

struct MonthlyCycleActionDecision {
    let allowed: Bool
    let blockedCopyKey: MonthlyCycleBlockedCopyKey?
    let blockedMessage: String?

    static let allowedDecision = MonthlyCycleActionDecision(
        allowed: true,
        blockedCopyKey: nil,
        blockedMessage: nil
    )
}

enum MonthlyCycleActionGate {
    static func evaluate(state: UiCycleState, action: MonthlyCycleAction) -> MonthlyCycleActionDecision {
        switch state {
        case .planning(let month, _):
            switch action {
            case .startTracking:
                return .allowedDecision
            case .finishMonth:
                return blocked(.finishBlockedNoExecuting, MonthlyCycleCopyCatalog.finishBlockedNoExecuting())
            case .undoStart:
                return blocked(.undoStartExpired, MonthlyCycleCopyCatalog.undoStartExpired(month: month))
            case .undoCompletion:
                return blocked(.undoCompletionExpired, MonthlyCycleCopyCatalog.undoCompletionExpired(month: month))
            }

        case .executing(let month, _, let canUndoStart):
            switch action {
            case .startTracking:
                return blocked(.startBlockedAlreadyExecuting, MonthlyCycleCopyCatalog.startBlockedAlreadyExecuting(month: month))
            case .finishMonth:
                return .allowedDecision
            case .undoStart:
                return canUndoStart
                    ? .allowedDecision
                    : blocked(.undoStartExpired, MonthlyCycleCopyCatalog.undoStartExpired(month: month))
            case .undoCompletion:
                return blocked(.undoCompletionExpired, MonthlyCycleCopyCatalog.undoCompletionExpired(month: month))
            }

        case .closed(let month, let canUndoCompletion):
            switch action {
            case .startTracking:
                return blocked(.startBlockedClosedMonth, MonthlyCycleCopyCatalog.startBlockedClosedMonth())
            case .finishMonth:
                return blocked(.finishBlockedNoExecuting, MonthlyCycleCopyCatalog.finishBlockedNoExecuting())
            case .undoStart:
                return blocked(.undoStartExpired, MonthlyCycleCopyCatalog.undoStartExpired(month: month))
            case .undoCompletion:
                return canUndoCompletion
                    ? .allowedDecision
                    : blocked(.undoCompletionExpired, MonthlyCycleCopyCatalog.undoCompletionExpired(month: month))
            }

        case .conflict:
            return blocked(.recordConflict, MonthlyCycleCopyCatalog.recordConflict())
        }
    }

    private static func blocked(
        _ key: MonthlyCycleBlockedCopyKey,
        _ message: String
    ) -> MonthlyCycleActionDecision {
        MonthlyCycleActionDecision(
            allowed: false,
            blockedCopyKey: key,
            blockedMessage: message
        )
    }
}
