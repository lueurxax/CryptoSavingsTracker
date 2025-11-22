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
    
    @State private var showDetails = false
    
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
    }
    
    // MARK: - Main Row Content
    
    @ViewBuilder
    private var mainRowContent: some View {
        HStack(spacing: 16) {
            // Status indicator and progress
            VStack(spacing: 8) {
                statusIndicator
                progressRing
            }
            .frame(width: 60)
            
            // Goal information
            goalInformation
            
            Spacer()
            
            // Amount and controls
            amountSection
            
            // Flex state chip
            flexStateChip
            
            // Details toggle
            detailsToggle
        }
        .padding()
    }
    
    // MARK: - Status Indicator
    
    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(.white, lineWidth: 2)
            )
    }
    
    // MARK: - Progress Ring
    
    @ViewBuilder
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: requirement.progress)
                .stroke(statusColor, lineWidth: 3)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: requirement.progress)
            
            Text("\(Int(requirement.progress * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(width: 36, height: 36)
    }
    
    // MARK: - Goal Information
    
    @ViewBuilder
    private var goalInformation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(requirement.goalName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 8) {
                Text(requirement.timeRemainingDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Target: \(formatAmount(requirement.targetAmount, currency: requirement.currency))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if requirement.status == .critical || requirement.status == .attention {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Amount Section
    
    @ViewBuilder
    private var amountSection: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Current amount (with adjustment preview)
            if let adjusted = adjustedAmount, adjusted != requirement.requiredMonthly {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatAmount(adjusted, currency: requirement.currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AccessibleColors.primaryInteractive)
                    
                    Text(requirement.formattedRequiredMonthly())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .strikethrough(true, color: .secondary)
                }
            } else {
                Text(requirement.formattedRequiredMonthly())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            // Remaining amount
            Text("of \(requirement.formattedRemainingAmount()) remaining")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Flex State Chip
    
    @ViewBuilder
    private var flexStateChip: some View {
        Menu {
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
                    .font(.caption)
                
                #if os(macOS)
                Text(flexState.displayName)
                    .font(.caption2)
                #endif
            }
            .foregroundColor(flexStateColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(flexStateColor.opacity(0.1))
            .clipShape(Capsule())
        }
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
                .font(.caption)
                .foregroundColor(AccessibleColors.secondaryInteractive)
                .frame(width: 24, height: 24)
                .background(.quaternary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showDetails ? "Hide details" : "Show details")
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