//
//  BudgetSummaryCard.swift
//  CryptoSavingsTracker
//
//  Unified budget health widgets for monthly planning.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private enum BudgetHealthTone {
    case neutral
    case success
    case info
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return AccessibleColors.success
        case .info:
            return AccessibleColors.primaryInteractive
        case .warning:
            return AccessibleColors.warning
        case .danger:
            return AccessibleColors.error
        }
    }

    var accentStroke: Color? {
        switch self {
        case .warning:
            return AccessibleColors.warning.opacity(0.35)
        case .danger:
            return AccessibleColors.error.opacity(0.40)
        default:
            return nil
        }
    }
}

private enum BudgetHealthCardStyle {
    static let cornerRadius: CGFloat = 12

    static var baselineStroke: Color {
        #if os(iOS)
        return Color(UIColor.separator).opacity(0.55)
        #elseif os(macOS)
        return Color(NSColor.separatorColor).opacity(0.55)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }
}

enum BudgetHealthState: Equatable {
    case noBudget
    case healthy
    case notApplied
    case needsRecalculation
    case atRisk(shortfall: Double, goalsAtRisk: Int)
    case severeRisk(shortfall: Double, goalsAtRisk: Int)
    case staleFX(lastUpdated: Date?, affectedCurrencies: [String])
}

extension BudgetHealthState {
    fileprivate var tone: BudgetHealthTone {
        switch self {
        case .noBudget:
            return .neutral
        case .healthy:
            return .success
        case .notApplied:
            return .info
        case .needsRecalculation:
            return .warning
        case .atRisk:
            return .warning
        case .severeRisk:
            return .danger
        case .staleFX:
            return .warning
        }
    }

    var iconName: String {
        switch self {
        case .noBudget:
            return "wallet.pass"
        case .healthy:
            return "checkmark.circle.fill"
        case .notApplied:
            return "arrow.clockwise.circle.fill"
        case .needsRecalculation:
            return "slider.horizontal.3"
        case .atRisk:
            return "exclamationmark.triangle.fill"
        case .severeRisk:
            return "xmark.circle.fill"
        case .staleFX:
            return "clock.arrow.circlepath"
        }
    }

    var statusText: String {
        switch self {
        case .noBudget:
            return "No budget set"
        case .healthy:
            return "All deadlines achievable"
        case .notApplied:
            return "Budget saved, not applied this month"
        case .needsRecalculation:
            return "Your goals or month changed"
        case .atRisk(_, let goalsAtRisk):
            return goalsAtRisk == 1 ? "1 goal at risk" : "\(goalsAtRisk) goals at risk"
        case .severeRisk(_, let goalsAtRisk):
            return goalsAtRisk == 1 ? "1 goal at high risk" : "\(goalsAtRisk) goals at high risk"
        case .staleFX:
            return "FX rates are outdated"
        }
    }

    var isRiskState: Bool {
        switch self {
        case .atRisk, .severeRisk:
            return true
        default:
            return false
        }
    }

    var isSevereRisk: Bool {
        if case .severeRisk = self {
            return true
        }
        return false
    }

    var shortfallAmount: Double? {
        switch self {
        case .atRisk(let shortfall, _), .severeRisk(let shortfall, _):
            return shortfall
        default:
            return nil
        }
    }

    var goalsAtRiskCount: Int? {
        switch self {
        case .atRisk(_, let goalsAtRisk), .severeRisk(_, let goalsAtRisk):
            return goalsAtRisk
        default:
            return nil
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .noBudget:
            return "Set Budget"
        case .healthy:
            return "Edit Budget"
        case .notApplied:
            return "Apply Budget"
        case .needsRecalculation:
            return "Recalculate"
        case .atRisk, .severeRisk:
            return "Fix Budget Shortfall"
        case .staleFX:
            return "Refresh Rates"
        }
    }

    var showsPrimaryCTA: Bool {
        self != .healthy
    }

    var primaryActionTint: Color {
        switch self {
        case .atRisk, .needsRecalculation, .staleFX:
            return AccessibleColors.warning.opacity(0.80)
        case .severeRisk:
            return AccessibleColors.error.opacity(0.80)
        case .noBudget, .notApplied, .healthy:
            return AccessibleColors.primaryInteractive.opacity(0.84)
        }
    }

    var collapsedActionTint: Color {
        switch self {
        case .atRisk, .needsRecalculation, .staleFX:
            return AccessibleColors.warning.opacity(0.80)
        case .severeRisk:
            return AccessibleColors.error.opacity(0.80)
        case .noBudget, .notApplied, .healthy:
            return AccessibleColors.primaryInteractive.opacity(0.84)
        }
    }

    var collapsedActionTitle: String {
        switch self {
        case .noBudget:
            return "Set"
        case .healthy:
            return "Edit"
        case .notApplied:
            return "Apply"
        case .needsRecalculation:
            return "Review"
        case .atRisk, .severeRisk:
            return "Fix"
        case .staleFX:
            return "Refresh"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .noBudget:
            return "No monthly budget configured"
        case .healthy:
            return "Budget is on track"
        case .notApplied:
            return "Budget is not applied for this month"
        case .needsRecalculation:
            return "Budget requires recalculation"
        case .atRisk:
            return "Budget is at risk"
        case .severeRisk:
            return "Budget has severe risk"
        case .staleFX:
            return "Budget conversion rates are outdated"
        }
    }

    func insightText(
        currency: String,
        conversionContext: String?
    ) -> String? {
        switch self {
        case .noBudget:
            return "Set a monthly amount to optimize contributions."
        case .healthy:
            return conversionContext
        case .notApplied:
            return "Apply this budget to activate monthly allocations."
        case .needsRecalculation:
            return "Recalculate allocations to reflect current goals."
        case .atRisk(let shortfall, _), .severeRisk(let shortfall, _):
            let shortText = CurrencyFormatter.format(amount: shortfall, currency: currency, maximumFractionDigits: 2)
            if let conversionContext {
                return "Short by \(shortText) this month. \(conversionContext)"
            }
            return "Short by \(shortText) this month"
        case .staleFX(let lastUpdated, let affectedCurrencies):
            let updateText: String
            if let lastUpdated {
                updateText = "as of \(BudgetHealthCard.dateTimeFormatter.string(from: lastUpdated))"
            } else {
                updateText = ""
            }
            if affectedCurrencies.isEmpty {
                return "Refresh conversion rates \(updateText).".trimmingCharacters(in: .whitespaces)
            }
            return "Missing rates for \(affectedCurrencies.joined(separator: ", ")) \(updateText).".trimmingCharacters(in: .whitespaces)
        }
    }

    func collapsedStatusText(currency: String) -> String {
        switch self {
        case .noBudget:
            return "No budget set"
        case .healthy:
            return "On track"
        case .notApplied:
            return "Budget not applied"
        case .needsRecalculation:
            return "Needs review"
        case .atRisk(let shortfall, _), .severeRisk(let shortfall, _):
            let shortText = CurrencyFormatter.format(amount: shortfall, currency: currency, maximumFractionDigits: 0)
            return "Short by \(shortText)"
        case .staleFX:
            return "Rates outdated"
        }
    }

    var collapsedRiskCountText: String? {
        switch self {
        case .atRisk(_, let goalsAtRisk):
            return goalsAtRisk > 0 ? "\(goalsAtRisk) at risk" : nil
        case .severeRisk(_, let goalsAtRisk):
            return goalsAtRisk > 0 ? "\(goalsAtRisk) high risk" : nil
        default:
            return nil
        }
    }

    func accessibilityValueText(currency: String, minimumRequired: Double?) -> String {
        switch self {
        case .atRisk(let shortfall, let goalsAtRisk), .severeRisk(let shortfall, let goalsAtRisk):
            let shortfallText = CurrencyFormatter.format(amount: shortfall, currency: currency, maximumFractionDigits: 2)
            if let minimumRequired {
                let minimumText = CurrencyFormatter.format(amount: minimumRequired, currency: currency, maximumFractionDigits: 2)
                return "Shortfall \(shortfallText). \(goalsAtRisk) goals at risk. Minimum required \(minimumText)."
            }
            return "Shortfall \(shortfallText). \(goalsAtRisk) goals at risk."
        case .staleFX(_, let affectedCurrencies):
            guard !affectedCurrencies.isEmpty else { return "Refresh rates required" }
            return "Unavailable for \(affectedCurrencies.joined(separator: ", "))"
        default:
            return statusText
        }
    }
}

struct BudgetHealthCard: View {
    let state: BudgetHealthState
    let budgetAmount: Double?
    let budgetCurrency: String
    let minimumRequired: Double?
    let nextConstrainedGoal: String?
    let nextDeadline: Date?
    let conversionContext: String?
    let onPrimaryAction: () -> Void
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedBudget: String {
        guard let budgetAmount else { return "Not set" }
        return CurrencyFormatter.format(amount: budgetAmount, currency: budgetCurrency, maximumFractionDigits: 2)
    }

    private var canEditBudget: Bool {
        budgetAmount != nil
    }

    private var insightText: String? {
        if dynamicTypeSize.isAccessibilitySize, conversionContext != nil {
            // At accessibility sizes, show core insight only; FX context goes into disclosure
            return state.insightText(currency: budgetCurrency, conversionContext: nil)
        }
        return state.insightText(currency: budgetCurrency, conversionContext: conversionContext)
    }

    private var fxDetailText: String? {
        guard dynamicTypeSize.isAccessibilitySize else { return nil }
        return conversionContext
    }

    private var focusGoalText: String? {
        guard let nextConstrainedGoal else { return nil }
        guard let nextDeadline else {
            return "Next: \(nextConstrainedGoal)"
        }
        return "Next: \(nextConstrainedGoal) (until \(Self.dateFormatter.string(from: nextDeadline)))"
    }

    private var minimumText: String? {
        guard state.isRiskState, let minimumRequired else { return nil }
        let minimumValue = CurrencyFormatter.format(amount: minimumRequired, currency: budgetCurrency, maximumFractionDigits: 2)
        return "Minimum required: \(minimumValue)"
    }

    private var shouldShowSecondaryText: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    private var primaryActionIdentifier: String {
        switch state {
        case .noBudget:
            return "setBudgetButton"
        case .atRisk, .severeRisk:
            return "budgetSummaryFixButton"
        case .notApplied:
            return "applyBudgetButton"
        case .needsRecalculation:
            return "recalculateBudgetButton"
        case .staleFX:
            return "refreshBudgetRatesButton"
        case .healthy:
            return "editBudgetPrimaryButton"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Monthly Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                if canEditBudget {
                    Button("Edit") {
                        BudgetHealthAnalytics.logEditTap()
                        onEdit()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("editBudgetButton")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(formattedBudget)
                    .font(.title3)
                    .fontWeight(budgetAmount == nil ? .regular : .semibold)
                    .foregroundStyle(budgetAmount == nil ? .tertiary : .primary)
                    .contentTransition(.numericText())

                HStack(spacing: 8) {
                    Image(systemName: state.iconName)
                        .foregroundStyle(state.tone.color)
                    Text(state.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("budgetSummaryStatusRow")

                if let insightText {
                    Text(insightText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(state.tone.color)
                        .lineLimit(2)
                        .accessibilityIdentifier(state.isRiskState ? "budgetSummaryShortfallText" : "budgetSummaryInsightText")
                }

                if let fxDetailText {
                    DisclosureGroup("Rate details") {
                        Text(fxDetailText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("budgetSummaryFXDisclosure")
                }

                if shouldShowSecondaryText, let focusGoalText, state.isRiskState {
                    Text(focusGoalText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if shouldShowSecondaryText, let minimumText {
                    Text(minimumText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("budgetSummaryMinimumText")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Monthly Budget, \(state.accessibilityDescription)")
            .accessibilityValue(state.accessibilityValueText(currency: budgetCurrency, minimumRequired: minimumRequired))
            .accessibilityHint("Double tap to \(state.primaryActionTitle)")

            if state.showsPrimaryCTA {
                Button {
                    BudgetHealthAnalytics.logPrimaryCTATap(state: state)
                    onPrimaryAction()
                } label: {
                    Label(state.primaryActionTitle, systemImage: state.iconName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.primaryActionTint)
                .accessibilityIdentifier(primaryActionIdentifier)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BudgetHealthCardStyle.cornerRadius)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BudgetHealthCardStyle.cornerRadius)
                .stroke(state.tone.accentStroke ?? BudgetHealthCardStyle.baselineStroke, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: BudgetHealthCardStyle.cornerRadius)
                .fill(state.tone.color)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: BudgetHealthCardStyle.cornerRadius))
        .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.98)
        .opacity(reduceMotion || hasAppeared ? 1 : 0)
        .onAppear {
            BudgetHealthAnalytics.logImpression(state: state)
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    hasAppeared = true
                }
            }
        }
        .onChange(of: state) { oldState, newState in
            guard oldState != newState else { return }
            BudgetHealthAnalytics.logStateChanged(from: oldState, to: newState)
            #if os(iOS)
            if oldState.isRiskState && newState == .healthy {
                HapticManager.shared.notification(.success)
            } else if !oldState.isSevereRisk && newState.isSevereRisk {
                HapticManager.shared.notification(.warning)
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.35), value: state)
        .accessibilityIdentifier(state == .noBudget ? "budgetEntryCard" : "budgetSummaryCard")
    }
}

struct BudgetHealthCollapsedStrip: View {
    let state: BudgetHealthState
    let budgetCurrency: String
    let onPrimaryAction: () -> Void

    private var compactStatusText: String {
        state.collapsedStatusText(currency: budgetCurrency)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: state.iconName)
                    .font(.caption)
                    .foregroundStyle(state.tone.color)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(compactStatusText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let collapsedRiskCountText = state.collapsedRiskCountText {
                            Text(collapsedRiskCountText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(compactStatusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Monthly Budget, \(state.accessibilityDescription)")
            .accessibilityHint("Double tap to \(state.primaryActionTitle)")

            Spacer(minLength: 6)

            Button(state.collapsedActionTitle) {
                BudgetHealthAnalytics.logCollapsedStripTap(state: state)
                onPrimaryAction()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .buttonStyle(.bordered)
            .tint(state.collapsedActionTint)
            .accessibilityIdentifier("budgetHealthCollapsedCTA")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BudgetHealthCardStyle.baselineStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("budgetHealthCollapsedStrip")
    }
}

// MARK: - Light Mode Previews

#Preview("1 No Budget") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .noBudget, budgetAmount: nil, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .noBudget, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("2 Healthy") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .healthy, budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .healthy, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("3 Not Applied") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .notApplied, budgetAmount: 2500, budgetCurrency: "EUR",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .notApplied, budgetCurrency: "EUR", onPrimaryAction: {})
    }.padding()
}

#Preview("4 Needs Recalculation") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .needsRecalculation, budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 3200, nextConstrainedGoal: "Vacation Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 4, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .needsRecalculation, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("5 At Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .atRisk(shortfall: 4399, goalsAtRisk: 18),
            budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: 9399, nextConstrainedGoal: "Emergency Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 2, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .atRisk(shortfall: 4399, goalsAtRisk: 18), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("6 Severe Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .severeRisk(shortfall: 12500, goalsAtRisk: 8),
            budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 15500, nextConstrainedGoal: "Bitcoin DCA",
            nextDeadline: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .severeRisk(shortfall: 12500, goalsAtRisk: 8), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("7 Stale FX") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]),
            budgetAmount: 4000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: "Converted from BTC/ETH holdings at current rates.",
            onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

// MARK: - Dark Mode Previews

#Preview("Dark: No Budget") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .noBudget, budgetAmount: nil, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .noBudget, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Healthy") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .healthy, budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .healthy, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Not Applied") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .notApplied, budgetAmount: 2500, budgetCurrency: "EUR",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .notApplied, budgetCurrency: "EUR", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Needs Recalculation") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .needsRecalculation, budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 3200, nextConstrainedGoal: "Vacation Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 4, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .needsRecalculation, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: At Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .atRisk(shortfall: 4399, goalsAtRisk: 18),
            budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: 9399, nextConstrainedGoal: "Emergency Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 2, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .atRisk(shortfall: 4399, goalsAtRisk: 18), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Severe Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .severeRisk(shortfall: 12500, goalsAtRisk: 8),
            budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 15500, nextConstrainedGoal: "Bitcoin DCA",
            nextDeadline: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .severeRisk(shortfall: 12500, goalsAtRisk: 8), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Stale FX") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]),
            budgetAmount: 4000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: "Converted from BTC/ETH holdings at current rates.",
            onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}
