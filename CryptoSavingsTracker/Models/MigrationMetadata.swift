//
//  MigrationMetadata.swift
//  CryptoSavingsTracker
//
//  Created for v2.0 - Migration tracking
//

import SwiftData
import Foundation

@Model
final class MigrationMetadata {
    @Attribute(.unique) var id: UUID
    var version: String
    var migratedAt: Date
    var status: MigrationStatus
    var errorMessage: String?
    var itemsProcessed: Int
    var itemsFailed: Int

    init(version: String) {
        self.id = UUID()
        self.version = version
        self.migratedAt = Date()
        self.status = .notStarted
        self.errorMessage = nil
        self.itemsProcessed = 0
        self.itemsFailed = 0
    }

    /// Mark migration as in progress
    func markInProgress() {
        self.status = .inProgress
    }

    /// Mark migration as completed successfully
    func markCompleted(itemsProcessed: Int = 0) {
        self.status = .completed
        self.itemsProcessed = itemsProcessed
        self.migratedAt = Date()
    }

    /// Mark migration as failed with error message
    func markFailed(error: String, itemsProcessed: Int = 0, itemsFailed: Int = 0) {
        self.status = .failed
        self.errorMessage = error
        self.itemsProcessed = itemsProcessed
        self.itemsFailed = itemsFailed
        self.migratedAt = Date()
    }
}

/// Migration status enumeration
enum MigrationStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed

    var displayName: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    var systemImageName: String {
        switch self {
        case .notStarted:
            return "circle"
        case .inProgress:
            return "arrow.clockwise.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
}