//
//  FlexAdjustmentSlider.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI
import SwiftData
import Combine

/// Interactive slider component for flex adjustments with live preview and debouncing
struct FlexAdjustmentSlider: View {
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    @State private var tempAdjustment: Double
    @State private var isAdjusting = false
    @State private var showPreview = false
    @State private var previewRequirements: [AdjustedRequirement] = []
    @State private var flexService: FlexAdjustmentService?
    @Environment(\.modelContext) private var modelContext
    
    // Debouncing
    @State private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.3
    
    // Animation
    @State private var sliderScale: CGFloat = 1.0
    @State private var impactHaptic = false
    
    init(viewModel: MonthlyPlanningViewModel) {
        self.viewModel = viewModel
        self._tempAdjustment = State(initialValue: viewModel.flexAdjustment)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with current adjustment
            headerSection
            
            // Main slider with real-time feedback
            sliderSection
            
            // Quick preset buttons
            presetButtonsSection
            
            // Live preview section
            if showPreview && !previewRequirements.isEmpty {
                previewSection
                    .transition(.opacity.combined(with: .slide))
            }
            
            // Impact summary
            impactSummarySection
        }
        .onAppear {
            setupFlexService()
        }
        .onChange(of: tempAdjustment) { _, newValue in
            handleAdjustmentChange(newValue)
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: impactHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flexible payment adjustment controls")
        .accessibilityHint("Adjust monthly payments across all flexible goals. Use preset buttons or slider to modify amounts")
        .accessibilityValue("\(Int(tempAdjustment * 100)) percent of original amounts")
    }
    
    // MARK: - Header Section
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Flex Adjustment")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Adjust payments across all flexible goals")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Current adjustment display
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(tempAdjustment * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(adjustmentColor)
                    .contentTransition(.numericText())
                
                if isAdjusting {
                    Text("Previewing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.8)
                } else if tempAdjustment != viewModel.flexAdjustment {
                    Text("Tap to apply")
                        .font(.caption2)
                        .foregroundColor(AccessibleColors.primaryInteractive)
                }
            }
        }
    }
    
    // MARK: - Slider Section
    
    @ViewBuilder
    private var sliderSection: some View {
        VStack(spacing: 16) {
            // Custom slider with enhanced visual feedback
            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 16)
                
                // Active track
                GeometryReader { geometry in
                    let trackWidth = geometry.size.width
                    let fillWidth = trackWidth * min(tempAdjustment / 2.0, 1.0) // Scale to 200% max
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [adjustmentColor.opacity(0.6), adjustmentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 16)
                        .animation(.easeInOut(duration: 0.2), value: tempAdjustment)
                }
                .frame(height: 16)
                
                // Slider thumb
                HStack {
                    Spacer()
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .scaleEffect(sliderScale)
                        .offset(x: sliderThumbOffset)
                }
            }
            .frame(height: 24)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleSliderDrag(value)
                    }
                    .onEnded { _ in
                        handleSliderDragEnd()
                    }
            )
            
            // Range labels
            HStack {
                Text("0%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("100%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("200%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Preset Buttons Section
    
    @ViewBuilder
    private var presetButtonsSection: some View {
        HStack(spacing: 12) {
            presetButton(title: "Skip", value: 0.0, systemImage: "pause.fill")
            presetButton(title: "Quarter", value: 0.25, systemImage: "25.circle")
            presetButton(title: "Half", value: 0.5, systemImage: "50.percent")
            presetButton(title: "Full", value: 1.0, systemImage: "checkmark.circle")
            presetButton(title: "Extra", value: 1.25, systemImage: "plus.circle")
        }
    }
    
    @ViewBuilder
    private func presetButton(title: String, value: Double, systemImage: String) -> some View {
        Button(action: {
            let animationDuration = AccessibilityManager.shared.animationDuration(0.4)
            withAnimation(.spring(response: animationDuration, dampingFraction: 0.8)) {
                tempAdjustment = value
                impactHaptic.toggle()
            }
            AccessibilityManager.shared.performHapticFeedback(.selection)
        }) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(tempAdjustment == value ? .white : AccessibleColors.primaryInteractive)
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tempAdjustment == value ? AccessibleColors.primaryInteractive : AccessibleColors.primaryInteractiveBackground)
            )
        }
        .accessibleButton(
            title: "Set to \(title.lowercased()) payments",
            hint: "Sets adjustment to \(Int(value * 100)) percent of original amounts",
            isEnabled: true,
            importance: .normal
        )
        .buttonStyle(.plain)
        .scaleEffect(tempAdjustment == value ? 1.05 : 1.0)
        .animation(AccessibilityManager.shared.springAnimation(duration: 0.3, dampingFraction: 0.7), value: tempAdjustment)
    }
    
    // MARK: - Preview Section
    
    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Preview")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        showPreview.toggle()
                    }
                }) {
                    Image(systemName: showPreview ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundColor(AccessibleColors.secondaryInteractive)
                }
            }
            
            if showPreview {
                LazyVStack(spacing: 8) {
                    ForEach(previewRequirements.prefix(3)) { adjusted in
                        previewRequirementRow(adjusted)
                    }
                    
                    if previewRequirements.count > 3 {
                        Text("+ \(previewRequirements.count - 3) more goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func previewRequirementRow(_ adjusted: AdjustedRequirement) -> some View {
        HStack(spacing: 12) {
            // Goal name and current vs adjusted
            VStack(alignment: .leading, spacing: 2) {
                Text(adjusted.requirement.goalName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(adjusted.requirement.formattedRequiredMonthly())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .strikethrough(adjusted.adjustedAmount != adjusted.requirement.requiredMonthly)
                    
                    if adjusted.adjustedAmount != adjusted.requirement.requiredMonthly {
                        Text("→")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatAmount(adjusted.adjustedAmount, currency: adjusted.requirement.currency))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(adjustmentChangeColor(adjusted))
                    }
                }
            }
            
            Spacer()
            
            // Change indicator
            if abs(adjusted.adjustedAmount - adjusted.requirement.requiredMonthly) > 0.01 {
                let change = adjusted.adjustedAmount - adjusted.requirement.requiredMonthly
                let changePercentage = (change / adjusted.requirement.requiredMonthly) * 100
                
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                        .foregroundColor(adjustmentChangeColor(adjusted))
                    
                    Text("\(abs(changePercentage), specifier: "%.0f")%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(adjustmentChangeColor(adjusted))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(adjustmentChangeColor(adjusted).opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Impact Summary Section
    
    @ViewBuilder
    private var impactSummarySection: some View {
        if !previewRequirements.isEmpty {
            HStack(spacing: 16) {
                impactStat(
                    title: "Total",
                    value: formatAmount(previewRequirements.reduce(0) { $0 + $1.adjustedAmount }, currency: viewModel.displayCurrency),
                    change: calculateTotalChange()
                )
                
                Divider()
                    .frame(height: 30)
                
                impactStat(
                    title: "Savings",
                    value: formatAmount(abs(calculateTotalSavings()), currency: viewModel.displayCurrency),
                    change: calculateTotalSavings() < 0 ? .reduced : .increased
                )
                
                Divider()
                    .frame(height: 30)
                
                impactStat(
                    title: "Goals",
                    value: "\(previewRequirements.count)",
                    change: .neutral
                )
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    @ViewBuilder
    private func impactStat(title: String, value: String, change: ChangeType) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(change == .neutral ? .primary : (change == .increased ? AccessibleColors.success : AccessibleColors.warning))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func setupFlexService() {
        flexService = DIContainer.shared.makeFlexAdjustmentService(modelContext: modelContext)
    }
    
    private func handleAdjustmentChange(_ newValue: Double) {
        isAdjusting = true
        
        // Cancel existing timer
        debounceTimer?.invalidate()
        
        // Start new debounced preview
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { _ in
            Task { @MainActor in
                await updatePreview(adjustment: newValue)
                isAdjusting = false
            }
        }
    }
    
    private func handleSliderDrag(_ value: DragGesture.Value) {
        isAdjusting = true
        
        // Convert drag to slider value (0.0 to 2.0)
        let dragPercentage = max(0, min(1, value.location.x / max(1, value.startLocation.x * 2)))
        tempAdjustment = dragPercentage * 2.0
        
        // Scale effect for thumb
        withAnimation(.easeOut(duration: 0.1)) {
            sliderScale = 1.2
        }
    }
    
    private func handleSliderDragEnd() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            sliderScale = 1.0
        }
    }
    
    @MainActor
    private func updatePreview(adjustment: Double) async {
        guard let flexService = flexService,
              !viewModel.monthlyRequirements.isEmpty else { return }
        
        do {
            let adjustedRequirements = await flexService.applyFlexAdjustment(
                requirements: viewModel.monthlyRequirements,
                adjustment: adjustment,
                protectedGoalIds: viewModel.protectedGoalIds,
                skippedGoalIds: viewModel.skippedGoalIds,
                strategy: .balanced
            )
            
            previewRequirements = adjustedRequirements
            showPreview = !adjustedRequirements.isEmpty
        }
    }
    
    private var sliderThumbOffset: CGFloat {
        let progress = min(tempAdjustment / 2.0, 1.0)
        return -12 + (progress * 24) // Adjust for thumb size
    }
    
    private var adjustmentColor: Color {
        if tempAdjustment < 0.5 {
            return AccessibleColors.warning
        } else if tempAdjustment > 1.5 {
            return AccessibleColors.primaryInteractive
        } else {
            return AccessibleColors.success
        }
    }
    
    private func adjustmentChangeColor(_ adjusted: AdjustedRequirement) -> Color {
        let change = adjusted.adjustedAmount - adjusted.requirement.requiredMonthly
        if change > 0 {
            return AccessibleColors.success
        } else if change < 0 {
            return AccessibleColors.warning
        } else {
            return .secondary
        }
    }
    
    private func calculateTotalChange() -> ChangeType {
        let originalTotal = viewModel.monthlyRequirements.reduce(0) { $0 + $1.requiredMonthly }
        let adjustedTotal = previewRequirements.reduce(0) { $0 + $1.adjustedAmount }
        
        if adjustedTotal > originalTotal {
            return .increased
        } else if adjustedTotal < originalTotal {
            return .reduced
        } else {
            return .neutral
        }
    }
    
    private func calculateTotalSavings() -> Double {
        let originalTotal = viewModel.monthlyRequirements.reduce(0) { $0 + $1.requiredMonthly }
        let adjustedTotal = previewRequirements.reduce(0) { $0 + $1.adjustedAmount }
        return originalTotal - adjustedTotal
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Supporting Types

enum ChangeType {
    case increased
    case reduced
    case neutral
}

// MARK: - Preview

#Preview("Flex Slider") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self, configurations: config)
    let context = container.mainContext
    
    let viewModel = MonthlyPlanningViewModel(modelContext: context)
    
    ScrollView {
        VStack(spacing: 20) {
            FlexAdjustmentSlider(viewModel: viewModel)
            
            // Demo content
            Rectangle()
                .fill(.secondary.opacity(0.1))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Text("Other Planning Controls")
                        .foregroundColor(.secondary)
                )
        }
        .padding()
    }
    .modelContainer(container)
}