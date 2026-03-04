//
//  BudgetSnapshotIdentity.swift
//  CryptoSavingsTracker
//
//  Deterministic request identity helpers for budget snapshot computations.
//

import Foundation
import CryptoKit

enum BudgetSnapshotIdentity {
    static func goalsSignature(goals: [Goal], skippedGoalIds: Set<UUID>) -> String {
        let formatter = ISO8601DateFormatter()
        let canonical = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { goal in
                let deadline = formatter.string(from: goal.deadline)
                let target = canonicalDecimal(Decimal(goal.targetAmount), scale: 6)
                let isSkipped = skippedGoalIds.contains(goal.id) ? "1" : "0"
                return "\(goal.id.uuidString)|\(goal.currency.uppercased())|\(target)|\(deadline)|\(isSkipped)"
            }
            .joined(separator: ";")
        return sha256(canonical)
    }

    static func rateSnapshotId(fromRates rates: [RateSnapshotEntry]) -> String {
        let canonical = rates
            .sorted { lhs, rhs in
                if lhs.from == rhs.from {
                    if lhs.to == rhs.to {
                        return lhs.timestampISO8601 < rhs.timestampISO8601
                    }
                    return lhs.to < rhs.to
                }
                return lhs.from < rhs.from
            }
            .map { entry in
                let rate = canonicalDecimal(entry.rate, scale: 12)
                return "\(entry.from.uppercased())->\(entry.to.uppercased())=\(rate)@\(entry.timestampISO8601)"
            }
            .joined(separator: ";")
        return sha256(canonical)
    }

    static func rateSnapshotId(forPairs pairs: [(from: String, to: String)]) -> String {
        let canonical = pairs
            .map { ($0.from.uppercased(), $0.to.uppercased()) }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
            .map { "\($0)->\($1)" }
            .joined(separator: ";")
        return sha256(canonical)
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalDecimal(_ value: Decimal, scale: Int) -> String {
        var working = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &working, scale, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}

struct RateSnapshotEntry: Equatable {
    let from: String
    let to: String
    let rate: Decimal
    let timestampISO8601: String
}
