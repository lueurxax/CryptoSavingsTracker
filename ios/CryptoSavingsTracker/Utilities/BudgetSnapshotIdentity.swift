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

    /// Canonical identity of every source dimension used to calculate a budget preview.
    ///
    /// The ordinary goals signature intentionally describes static goal inputs only.
    /// Apply needs a stronger identity that also includes the balance-derived remaining
    /// amount so an allocation or balance edit cannot reuse an obsolete preview.
    static func sourceStateSignature(
        goals: [Goal],
        remainingByGoal: [UUID: Double]
    ) -> String {
        let canonical = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { goal in
                let target = canonicalDecimal(Decimal(goal.targetAmount), scale: 6)
                let remaining = remainingByGoal[goal.id].map {
                    canonicalDecimal(Decimal($0), scale: 6)
                } ?? "missing"
                let deadline = String(goal.deadline.timeIntervalSinceReferenceDate.bitPattern)
                return [
                    goal.id.uuidString,
                    goal.currency.uppercased(),
                    target,
                    deadline,
                    remaining
                ].joined(separator: "|")
            }
            .joined(separator: ";")
        return sha256(canonical)
    }

    /// Identity persisted after Apply. It binds the source state to the exact
    /// canonical amount, persisted plan outputs, payment configuration, and
    /// allocation inputs the user applied.
    static func appliedBudgetSignature(
        amount: MoneyAmount,
        sourceStateSignature: String,
        monthlyPlans: [MonthlyPlan],
        paymentDay: Int,
        budgetPlan: BudgetCalculatorPlan
    ) -> String {
        let persistedOutputs = monthlyPlans
            .sorted { lhs, rhs in
                if lhs.goalId == rhs.goalId {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.goalId.uuidString < rhs.goalId.uuidString
            }
            .map { plan in
                let currency = plan.currency.uppercased()
                let customAmount = plan.customAmount.map {
                    String(MoneyQuantizer.minorUnitValue(for: Decimal($0), currency: currency))
                } ?? "nil"
                return [
                    plan.goalId.uuidString,
                    plan.monthLabel,
                    currency,
                    String(MoneyQuantizer.minorUnitValue(
                        for: Decimal(plan.requiredMonthly),
                        currency: currency
                    )),
                    String(MoneyQuantizer.minorUnitValue(
                        for: Decimal(plan.remainingAmount),
                        currency: currency
                    )),
                    String(plan.monthsRemaining),
                    plan.statusRawValue,
                    plan.stateRawValue,
                    customAmount,
                    String(MoneyQuantizer.minorUnitValue(
                        for: Decimal(plan.effectiveAmount),
                        currency: currency
                    )),
                    plan.flexStateRawValue,
                    plan.isProtected ? "1" : "0",
                    plan.isSkipped ? "1" : "0"
                ].joined(separator: "|")
            }
            .joined(separator: ";")

        let appliedRates = budgetPlan.applicationRatesByPair
            .map { pair, rate in
                "\(pair.uppercased())=\(canonicalDecimal(Decimal(rate), scale: 12))"
            }
            .sorted()
            .joined(separator: ";")

        let firstPayment: String
        if let payment = budgetPlan.schedule.first {
            let contributions = payment.contributions
                .sorted { lhs, rhs in
                    if lhs.goalId == rhs.goalId {
                        return lhs.amount < rhs.amount
                    }
                    return lhs.goalId.uuidString < rhs.goalId.uuidString
                }
                .map { contribution in
                    [
                        contribution.goalId.uuidString,
                        String(MoneyQuantizer.minorUnitValue(
                            for: Decimal(contribution.amount),
                            currency: amount.currency
                        )),
                        String(MoneyQuantizer.minorUnitValue(
                            for: Decimal(contribution.runningTotal),
                            currency: amount.currency
                        )),
                        contribution.isGoalStart ? "1" : "0",
                        contribution.isGoalComplete ? "1" : "0"
                    ].joined(separator: "|")
                }
                .joined(separator: ";")
            firstPayment = [
                String(payment.paymentNumber),
                String(payment.paymentDate.timeIntervalSinceReferenceDate.bitPattern),
                contributions
            ].joined(separator: "|")
        } else {
            firstPayment = "none"
        }

        let goalRemaining = budgetPlan.goalRemainingById
            .map { goalID, remaining in
                [
                    goalID.uuidString,
                    String(MoneyQuantizer.minorUnitValue(
                        for: Decimal(remaining),
                        currency: amount.currency
                    ))
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: ";")

        let minimumRequired = MoneyQuantizer.minorUnitValue(
            for: Decimal(budgetPlan.minimumRequired),
            currency: amount.currency
        )
        let leveled = budgetPlan.isLeveled ? "1" : "0"

        return sha256(
            [
                amount.currency.uppercased(),
                String(amount.minorUnitValue),
                sourceStateSignature,
                "paymentDay=\(paymentDay)",
                "minimum=\(minimumRequired)",
                "leveled=\(leveled)",
                "remaining=\(goalRemaining)",
                "rates=\(appliedRates)",
                "first=\(firstPayment)",
                "outputs=\(persistedOutputs)"
            ].joined(separator: "|")
        )
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
