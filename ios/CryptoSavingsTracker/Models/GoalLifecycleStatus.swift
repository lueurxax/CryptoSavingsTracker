//
//  GoalLifecycleStatus.swift
//  CryptoSavingsTracker
//
//  Goal lifecycle state used for soft-delete/cancel/finish semantics.
//

import Foundation

enum GoalLifecycleStatus: String, Codable, Sendable, CaseIterable {
    case active
    case cancelled
    case finished
    case deleted

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .cancelled:
            return "Cancelled"
        case .finished:
            return "Finished"
        case .deleted:
            return "Deleted"
        }
    }
}

