//
//  ExecutionContributionCalculator.swift
//  CryptoSavingsTracker
//
//  Calculates remaining contribution amounts for execution tracking.
//

import Foundation

@MainActor
final class ExecutionContributionCalculator {
    private let exchangeRateService: ExchangeRateServiceProtocol

    init(exchangeRateService: ExchangeRateServiceProtocol) {
        self.exchangeRateService = exchangeRateService
    }

    func remainingToClose(goalSnapshot: ExecutionGoalSnapshot, contributed: Double) -> Double {
        max(0, goalSnapshot.plannedAmount - contributed)
    }

    func remainingToClose(
        goalSnapshot: ExecutionGoalSnapshot,
        contributed: Double,
        in currency: String
    ) async -> Double? {
        let remaining = remainingToClose(goalSnapshot: goalSnapshot, contributed: contributed)
        guard remaining > 0 else { return 0 }
        let goalCurrency = goalSnapshot.currency
        if goalCurrency.uppercased() == currency.uppercased() {
            return remaining
        }

        do {
            let rate = try await exchangeRateService.fetchRate(from: goalCurrency, to: currency)
            return remaining * rate
        } catch {
            AppLog.warning("Execution conversion failed \(goalCurrency)->\(currency): \(error)", category: .exchangeRate)
            return nil
        }
    }

    func convertAmount(_ amount: Double, from: String, to: String) async -> Double? {
        guard amount > 0 else { return 0 }
        if from.uppercased() == to.uppercased() {
            return amount
        }
        do {
            let rate = try await exchangeRateService.fetchRate(from: from, to: to)
            return amount * rate
        } catch {
            AppLog.warning("Execution conversion failed \(from)->\(to): \(error)", category: .exchangeRate)
            return nil
        }
    }
}
