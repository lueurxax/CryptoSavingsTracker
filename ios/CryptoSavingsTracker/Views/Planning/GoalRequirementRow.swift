//
//  GoalRequirementRow.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI

/// Row component displaying monthly requirement for a single goal
struct GoalRequirementRow: View {
    let requirement: MonthlyRequirement
    let flexState: MonthlyPlan.FlexState
    let adjustedAmount: Double?
    let onToggleProtection: () -> Void
    let onToggleSkip: () -> Void
    let onSetCustomAmount: ((Double?) -> Void)?
    let showBudgetIndicator: Bool

    @State private var showDetails = false
    @State private var showCustomAmountSheet = false
    @State private var customAmountText = ""

    init(
        requirement: MonthlyRequirement,
        flexState: MonthlyPlan.FlexState,
        adjustedAmount: Double?,
        showBudgetIndicator: Bool = false,
        onToggleProtection: @escaping () -> Void,
        onToggleSkip: @escaping () -> Void,
        onSetCustomAmount: ((Double?) -> Void)? = nil
    ) {
        self.requirement = requirement
        self.flexState = flexState
        self.adjustedAmount = adjustedAmount
        self.showBudgetIndicator = showBudgetIndicator
        self.onToggleProtection = onToggleProtection
        self.onToggleSkip = onToggleSkip
        self.onSetCustomAmount = onSetCustomAmount
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row content
            mainRowContent

            // Expanded details (if shown)
            if showDetails {
                detailsContent
                    .transition(.opacity.combined(with: .slide))
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .sheet(isPresented: $showCustomAmountSheet) {
            CustomAmountSheet(
                goalName: requirement.goalName,
                currency: requirement.currency,
                requiredAmount: requirement.requiredMonthly,
                currentCustomAmount: adjustedAmount,
                onSave: { amount in
                    onSetCustomAmount?(amount)
                    showCustomAmountSheet = false
                },
                onCancel: {
                    showCustomAmountSheet = false
                }
            )
        }
    }

    // MARK: - Main Row Content

    @ViewBuilder
    private var mainRowContent: some View {
        // Vertical layout to prevent cramping and truncation
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Status + Goal name + Flex chip
            HStack(spacing: 12) {
                // Status indicator with icon for accessibility
                statusIndicatorWithIcon

                // Goal name
                Text(requirement.goalName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // Flex state chip
                flexStateChip

                // Details toggle
                detailsToggle
            }

            // Middle row: Amount + Timeline
            HStack(alignment: .center, spacing: 16) {
                // Monthly amount (primary info)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    amountDisplay

                    if showBudgetIndicator {
                        Text("From budget")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 80, alignment: .leading)

                Spacer()

                // Progress
                VStack(alignment: .center, spacing: 2) {
                    Text("Progress")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(Int(requirement.progress * 100))%")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                // Months remaining
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Deadline")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(monthsRemainingText)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(requirement.monthsRemaining <= 2 ? AccessibleColors.warning : .primary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            // Progress bar
            ProgressView(value: min(max(requirement.progress, 0), 1))
                .tint(statusColor)
                .accessibilityHidden(true)
        }
        .padding()
        .contentShape(Rectangle())
    }

    // MARK: - Amount Display (prevents truncation)

    @ViewBuilder
    private var amountDisplay: some View {
        if let adjusted = adjustedAmount, adjusted != requirement.requiredMonthly {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatAmount(adjusted, currency: requirement.currency))
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(AccessibleColors.primaryInteractive)
                    .fixedSize(horizontal: true, vertical: false)

                Text(requirement.formattedRequiredMonthly())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .strikethrough(true, color: .secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            Text(requirement.formattedRequiredMonthly())
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Months Remaining Text

    private var monthsRemainingText: String {
        if requirement.monthsRemaining == 1 {
            return "1 month"
        } else {
            return "\(requirement.monthsRemaining) months"
        }
    }
    
    // MARK: - Status Indicator with Icon (Accessibility)

    @ViewBuilder
    private var statusIndicatorWithIcon: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(statusColor)

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var statusIcon: String {
        switch requirement.status {
        case .completed: return "checkmark.circle.fill"
        case .onTrack: return "checkmark"
        case .attention: return "exclamationmark"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
    
    // MARK: - Flex State Chip

    @ViewBuilder
    private var flexStateChip: some View {
        Menu {
            // Set Custom Amount option
            if onSetCustomAmount != nil {
                Button(action: { showCustomAmountSheet = true }) {
                    Label(
                        adjustedAmount != nil ? "Edit Custom Amount" : "Set Custom Amount",
                        systemImage: "dollarsign.circle"
                    )
                }

                if adjustedAmount != nil {
                    Button(role: .destructive, action: { onSetCustomAmount?(nil) }) {
                        Label("Clear Custom Amount", systemImage: "xmark.circle")
                    }
                }

                Divider()
            }

            Button(action: onToggleProtection) {
                Label(
                    flexState == .protected ? "Unlock Amount" : "Lock This Amount",
                    systemImage: flexState == .protected ? "lock.open" : "lock"
                )
            }

            Button(action: onToggleSkip) {
                Label(
                    flexState == .skipped ? "Include This Month" : "Skip This Month",
                    systemImage: flexState == .skipped ? "play.fill" : "forward.fill"
                )
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: flexState.systemImageName)
                    .font(.subheadline)

                #if os(macOS)
                Text(flexState.displayName)
                    .font(.caption)
                #endif
            }
            .foregroundColor(flexStateColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(flexStateColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(minWidth: 44, minHeight: 44) // Apple HIG touch target
        .help(flexState.displayName)
    }

    // MARK: - Details Toggle

    @ViewBuilder
    private var detailsToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetails.toggle()
            }
        }) {
            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                .font(.subheadline)
                .foregroundColor(AccessibleColors.secondaryInteractive)
                .frame(width: 32, height: 32)
                .background(.quaternary)
                .clipShape(Circle())
        }
        .frame(minWidth: 44, minHeight: 44) // Apple HIG touch target
        .buttonStyle(.plain)
        .accessibilityLabel(showDetails ? "Hide details" : "Show details")
    }

    // MARK: - Accessibility Description

    private var accessibilityDescription: String {
        var description = "\(requirement.goalName), \(statusAccessibilityLabel)"
        description += ". \(requirement.formattedRequiredMonthly()) per month"
        description += ". \(Int(requirement.progress * 100)) percent complete"
        description += ". \(monthsRemainingText) remaining"
        description += ". \(flexState.displayName)"
        return description
    }

    private var statusAccessibilityLabel: String {
        switch requirement.status {
        case .completed: return "completed"
        case .onTrack: return "on track"
        case .attention: return "needs attention"
        case .critical: return "critical, requires immediate action"
        }
    }
    
    // MARK: - Details Content
    
    @ViewBuilder
    private var detailsContent: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Progress breakdown
                progressBreakdown
                
                // Timeline information
                timelineInformation
                
                // Impact analysis (if adjusted)
                if let adjusted = adjustedAmount, adjusted != requirement.requiredMonthly {
                    impactAnalysis(adjustedAmount: adjusted)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    // MARK: - Progress Breakdown
    
    @ViewBuilder
    private var progressBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress Breakdown")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatAmount(requirement.currentTotal, currency: requirement.currency))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Progress")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(requirement.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatAmount(requirement.targetAmount, currency: requirement.currency))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Timeline Information
    
    @ViewBuilder
    private var timelineInformation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deadline")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(requirement.deadline, format: .dateTime.month().day().year())
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Months Left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(requirement.monthsRemaining)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(requirement.monthsRemaining <= 2 ? AccessibleColors.warning : .primary)
                }
            }
        }
        .padding(12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Impact Analysis
    
    @ViewBuilder
    private func impactAnalysis(adjustedAmount: Double) -> some View {
        let difference = adjustedAmount - requirement.requiredMonthly
        let percentChange = requirement.requiredMonthly > 0 ? (difference / requirement.requiredMonthly) * 100 : 0
        let impactColor: Color = difference > 0 ? AccessibleColors.success : AccessibleColors.warning
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Impact of Adjustment")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            VStack(spacing: 6) {
                HStack {
                    Text("Payment Change")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: difference > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(impactColor)
                        
                        Text(formatAmount(abs(difference), currency: requirement.currency))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(impactColor)
                        
                        Text("(\(difference > 0 ? "+" : "")\(String(format: "%.1f", percentChange))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if difference < 0 {
                    let shortfall = abs(difference)
                    let delayMonths = Int(ceil(shortfall / max(1, requirement.requiredMonthly - abs(difference))))
                    
                    if delayMonths > 0 {
                        HStack {
                            Text("Estimated Delay")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(delayMonths) month\(delayMonths == 1 ? "" : "s")")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(AccessibleColors.warning)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(impactColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(impactColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch requirement.status {
        case .completed: return AccessibleColors.success
        case .onTrack: return AccessibleColors.success
        case .attention: return AccessibleColors.warning
        case .critical: return AccessibleColors.error
        }
    }
    
    private var flexStateColor: Color {
        switch flexState {
        case .protected: return AccessibleColors.primaryInteractive
        case .flexible: return AccessibleColors.secondaryInteractive
        case .skipped: return AccessibleColors.warning
        }
    }
    
    private var statusMessage: String {
        switch requirement.status {
        case .critical: return "Requires immediate attention"
        case .attention: return "Higher than average requirement"
        case .onTrack: return "On track to meet deadline"
        case .completed: return "Goal completed"
        }
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Custom Amount Sheet

struct CustomAmountSheet: View {
    let goalName: String
    let currency: String
    let requiredAmount: Double
    let currentCustomAmount: Double?
    let onSave: (Double?) -> Void
    let onCancel: () -> Void

    @State private var amountText: String = ""
    @FocusState private var isAmountFocused: Bool

    init(
        goalName: String,
        currency: String,
        requiredAmount: Double,
        currentCustomAmount: Double?,
        onSave: @escaping (Double?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.goalName = goalName
        self.currency = currency
        self.requiredAmount = requiredAmount
        self.currentCustomAmount = currentCustomAmount
        self.onSave = onSave
        self.onCancel = onCancel
        // Initialize with current custom amount or empty
        _amountText = State(initialValue: currentCustomAmount.map { String(format: "%.2f", $0) } ?? "")
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var isValidAmount: Bool {
        guard let amount = parsedAmount else { return false }
        return amount >= 0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header info
                VStack(spacing: 8) {
                    Text(goalName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Required: \(formatAmount(requiredAmount, currency: currency))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Amount input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Amount (\(currency))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(currencySymbol)
                            .font(.title2)
                            .foregroundColor(.secondary)

                        #if os(iOS)
                        TextField("0.00", text: $amountText)
                            .font(.title)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .multilineTextAlignment(.leading)
                        #else
                        TextField("0.00", text: $amountText)
                            .font(.title)
                            .focused($isAmountFocused)
                            .multilineTextAlignment(.leading)
                        #endif
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Quick amount buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Select")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            quickAmountButton(multiplier: 0.5, label: "50%")
                            quickAmountButton(multiplier: 0.75, label: "75%")
                            quickAmountButton(multiplier: 1.0, label: "100%")
                            quickAmountButton(multiplier: 1.25, label: "125%")
                            quickAmountButton(multiplier: 1.5, label: "150%")
                            quickAmountButton(multiplier: 2.0, label: "200%")
                        }
                        .padding(.horizontal)
                    }
                }

                // Impact preview
                if let amount = parsedAmount, amount > 0 {
                    impactPreview(amount: amount)
                        .padding(.horizontal)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        if let amount = parsedAmount, amount > 0 {
                            onSave(amount)
                        }
                    }) {
                        Text("Save Custom Amount")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidAmount && (parsedAmount ?? 0) > 0 ? AccessibleColors.primaryInteractive : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!isValidAmount || (parsedAmount ?? 0) <= 0)

                    if currentCustomAmount != nil {
                        Button(role: .destructive, action: { onSave(nil) }) {
                            Text("Clear Custom Amount")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Set Amount")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    @ViewBuilder
    private func quickAmountButton(multiplier: Double, label: String) -> some View {
        let amount = requiredAmount * multiplier
        Button(action: {
            amountText = String(format: "%.2f", amount)
        }) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(formatAmount(amount, currency: currency))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func impactPreview(amount: Double) -> some View {
        let difference = amount - requiredAmount
        let percentChange = requiredAmount > 0 ? (difference / requiredAmount) * 100 : 0
        let isIncrease = difference >= 0

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compared to required")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: isIncrease ? "arrow.up" : "arrow.down")
                        .font(.caption)
                    Text("\(isIncrease ? "+" : "")\(formatAmount(difference, currency: currency))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("(\(isIncrease ? "+" : "")\(String(format: "%.0f", percentChange))%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(isIncrease ? AccessibleColors.success : AccessibleColors.warning)
            }

            Spacer()
        }
        .padding()
        .background((isIncrease ? AccessibleColors.success : AccessibleColors.warning).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.currencySymbol ?? currency
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Preview

#Preview("Normal Goal") {
    let requirement = MonthlyRequirement(
        goalId: UUID(),
        goalName: "Bitcoin Savings",
        currency: "USD",
        targetAmount: 10000,
        currentTotal: 3500,
        remainingAmount: 6500,
        monthsRemaining: 8,
        requiredMonthly: 812.50,
        progress: 0.35,
        deadline: Calendar.current.date(byAdding: .month, value: 8, to: Date())!,
        status: .onTrack
    )
    
    VStack(spacing: 16) {
        GoalRequirementRow(
            requirement: requirement,
            flexState: .flexible,
            adjustedAmount: nil,
            onToggleProtection: {},
            onToggleSkip: {}
        )
        
        GoalRequirementRow(
            requirement: requirement,
            flexState: .protected,
            adjustedAmount: 600.0, // Adjusted down
            onToggleProtection: {},
            onToggleSkip: {}
        )
    }
    .padding()
    .background(.regularMaterial)
}

#Preview("Critical Goal") {
    let requirement = MonthlyRequirement(
        goalId: UUID(),
        goalName: "Emergency Fund",
        currency: "EUR",
        targetAmount: 15000,
        currentTotal: 2000,
        remainingAmount: 13000,
        monthsRemaining: 1,
        requiredMonthly: 13000,
        progress: 0.13,
        deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        status: .critical
    )
    
    GoalRequirementRow(
        requirement: requirement,
        flexState: .flexible,
        adjustedAmount: nil,
        onToggleProtection: {},
        onToggleSkip: {}
    )
    .padding()
    .background(.regularMaterial)
}
