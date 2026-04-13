//
//  DashboardAccessibilityCopy.swift
//  CryptoSavingsTracker
//

import Foundation

enum DashboardQuickAction {
    case addAsset
    case addTransaction
    case editGoal
}

enum DashboardAccessibilityCopy {
    static func transactionRecoveryTitle(hasAssets: Bool) -> String {
        hasAssets ? "Choose an Asset First" : "Add an Asset First"
    }

    static func transactionRecoveryMessage(goalName: String, hasAssets: Bool) -> String {
        if hasAssets {
            return "Pick the asset you want to use for \(goalName) before logging this transaction."
        }

        return "Add an asset to \(goalName) before logging a transaction so the contribution has somewhere to go."
    }

    static func transactionRecoveryPrimaryActionHint(hasAssets: Bool) -> String {
        if hasAssets {
            return "Double tap to choose the asset you want to use before recording this transaction."
        }

        return "Double tap to add an asset for this goal before recording a transaction."
    }

    static func transactionRecoveryDismissHint(hasAssets: Bool) -> String {
        if hasAssets {
            return "Double tap to close this message and continue reviewing the dashboard until you are ready to choose an asset."
        }

        return "Double tap to close this message and continue reviewing the dashboard until you are ready to add an asset."
    }

    static func transactionRecoveryFooter(hasAssets: Bool) -> String {
        if hasAssets {
            return "You can come back after linking the right asset."
        }

        return "You can come back after linking an asset to this goal."
    }

    static func whatIfStatusValue(onTrack: Bool) -> String {
        if onTrack {
            return "On track. Projected contributions reach the goal by the deadline."
        }

        return "Behind. Projected contributions still fall short of the goal by the deadline."
    }

    static func whatIfStatusHint(onTrack: Bool) -> String {
        if onTrack {
            return "Review the scenario details to see how the projection reaches the target."
        }

        return "Increase the one-time or monthly contribution to close the remaining gap."
    }

    static func overlayToggleHint(isEnabled: Bool) -> String {
        if isEnabled {
            return "Double tap to hide the what-if projection on the forecast chart."
        }

        return "Double tap to show the what-if projection on the forecast chart."
    }

    static func projectedOutcomeValue(projectedTotal: Double, currency: String, daysRemaining: Int, onTrack: Bool) -> String {
        let projectedAmount = CurrencyFormatter.accessibilityFormat(amount: projectedTotal, currency: currency)
        let dayText = remainingDaysValue(daysRemaining)
        return "Projected total \(projectedAmount). \(dayText). \(whatIfStatusValue(onTrack: onTrack))"
    }

    static func contributionValue(amount: Double, currency: String, kind: String) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 0
        let numericAmount = numberFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
        let spokenCurrency = spokenCurrencyName(for: currency, amount: amount)
        return "\(kind) \(numericAmount) \(spokenCurrency)"
    }

    private static func spokenCurrencyName(for currency: String, amount: Double) -> String {
        switch currency.uppercased() {
        case "USD":
            return abs(amount) == 1 ? "US dollar" : "US dollars"
        case "EUR":
            return abs(amount) == 1 ? "euro" : "euros"
        case "GBP":
            return abs(amount) == 1 ? "British pound" : "British pounds"
        default:
            let localized = Locale.current.localizedString(forCurrencyCode: currency)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let localized, !localized.isEmpty else {
                return currency.uppercased()
            }

            if abs(amount) == 1 {
                return localized
            }

            if localized.hasSuffix("s") {
                return localized
            }

            return localized + "s"
        }
    }

    static func remainingDaysValue(_ daysRemaining: Int) -> String {
        daysRemaining == 1 ? "1 day remaining" : "\(daysRemaining) days remaining"
    }

    static func quickActionHint(action: DashboardQuickAction, hasAssets: Bool) -> String {
        switch action {
        case .addAsset:
            return "Double tap to link another asset to this goal."
        case .addTransaction:
            if hasAssets {
                return "Double tap to choose an asset and log a transaction for this goal."
            }
            return "Add an asset to this goal before logging a transaction."
        case .editGoal:
            return "Double tap to review and update this goal."
        }
    }

    static func metricSummary(title: String, value: String, subtitle: String, trend: String? = nil, urgency: Bool = false) -> String {
        var parts = [title, value, subtitle]
        if let trend, !trend.isEmpty {
            parts.append(trend)
        }
        if urgency {
            parts.append("Needs attention soon")
        }
        return parts.joined(separator: ", ")
    }

    static func metricHint(isUrgent: Bool) -> String {
        isUrgent
            ? "Review this metric soon because the deadline is approaching."
            : "Swipe right for the next dashboard metric."
    }

    static func assetSelectionLabel(currency: String, address: String?) -> String {
        guard let address, !address.isEmpty else {
            return "\(currency) asset"
        }
        return "\(currency) asset, address \(address)"
    }

    static func assetSelectionHint(currency: String) -> String {
        "Double tap to continue with the \(currency) asset."
    }

    static let assetPickerDismissHint = "Double tap to close asset selection and return to the dashboard."

    static func recentActivityLabel(currency: String, note: String?, amountText: String, dateText: String) -> String {
        var parts = ["\(currency) transaction", amountText, dateText]
        if let note, !note.isEmpty {
            parts.insert(note, at: 1)
        }
        return parts.joined(separator: ", ")
    }
}
