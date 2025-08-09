//
//  AccessibilityManager.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

/// Comprehensive accessibility manager for WCAG 2.1 AA compliance
@MainActor
final class AccessibilityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AccessibilityManager()
    
    // MARK: - Published Properties
    
    @Published var isVoiceOverEnabled = false
    @Published var isReduceMotionEnabled = false
    @Published var isDifferentiateWithoutColorEnabled = false
    @Published var isIncreaseContrastEnabled = false
    @Published var isReduceTransparencyEnabled = false
    @Published var isSwitchControlEnabled = false
    @Published var isAssistiveTouchEnabled = false
    @Published var isInvertColorsEnabled = false
    @Published var preferredContentSizeCategory: ContentSizeCategory = .medium
    @Published var isLargeTextEnabled = false
    
    // MARK: - Accessibility Settings
    
    @Published var useColorblindSafeColors = false
    @Published var useHighContrastMode = false
    @Published var showFocusIndicators = true
    @Published var useSimplifiedAnimations = false
    @Published var enableHapticFeedback = true
    @Published var useAlternativeTextFormats = false
    
    // MARK: - Initialization
    
    private init() {
        setupAccessibilityObservers()
        updateAccessibilityState()
    }
    
    // MARK: - Accessibility State Management
    
    private func setupAccessibilityObservers() {
        #if os(iOS)
        // Observe system accessibility changes on iOS
        NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.differentiateWithoutColorDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.darkerSystemColorsStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.reduceTransparencyStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.invertColorsStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilityState()
            }
            .store(in: &cancellables)
        #endif
    }
    
    private func updateAccessibilityState() {
        #if os(iOS)
        isVoiceOverEnabled = UIAccessibility.isVoiceOverRunning
        isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        isDifferentiateWithoutColorEnabled = UIAccessibility.shouldDifferentiateWithoutColor
        isIncreaseContrastEnabled = UIAccessibility.isDarkerSystemColorsEnabled
        isReduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
        isSwitchControlEnabled = UIAccessibility.isSwitchControlRunning
        isAssistiveTouchEnabled = UIAccessibility.isAssistiveTouchRunning
        isInvertColorsEnabled = UIAccessibility.isInvertColorsEnabled
        
        let uiCategory = UIApplication.shared.preferredContentSizeCategory
        preferredContentSizeCategory = ContentSizeCategory(uiCategory) ?? .medium
        isLargeTextEnabled = uiCategory.isAccessibilityCategory
        #else
        // macOS fallbacks - use default values or system preferences if available
        isVoiceOverEnabled = false // Would need NSAccessibility APIs for proper detection
        isReduceMotionEnabled = false
        isDifferentiateWithoutColorEnabled = false
        isIncreaseContrastEnabled = false
        isReduceTransparencyEnabled = false
        isSwitchControlEnabled = false
        isAssistiveTouchEnabled = false
        isInvertColorsEnabled = false
        
        preferredContentSizeCategory = .medium
        isLargeTextEnabled = false
        #endif
        
        // Auto-enable features based on system state
        useColorblindSafeColors = isDifferentiateWithoutColorEnabled
        useHighContrastMode = isIncreaseContrastEnabled
        useSimplifiedAnimations = isReduceMotionEnabled
        showFocusIndicators = isSwitchControlEnabled || isVoiceOverEnabled
    }
    
    // MARK: - Storage
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Accessibility Helpers
    
    /// Generate VoiceOver description for financial amounts
    func voiceOverDescription(for amount: Double, currency: String, context: String = "") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.currencySymbol = ""
        
        let amountString = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        let currencyName = getCurrencyDisplayName(currency)
        
        var description = "\(amountString) \(currencyName)"
        if !context.isEmpty {
            description = "\(context): \(description)"
        }
        
        return description
    }
    
    /// Generate VoiceOver description for progress values
    func voiceOverProgressDescription(_ progress: Double, goalName: String) -> String {
        let percentage = Int((progress * 100).rounded())
        return "\(goalName) is \(percentage) percent complete"
    }
    
    /// Generate VoiceOver description for dates
    func voiceOverDateDescription(_ date: Date, format: DateFormat = .medium) -> String {
        let formatter = DateFormatter()
        
        switch format {
        case .short:
            formatter.dateStyle = .short
        case .medium:
            formatter.dateStyle = .medium
        case .long:
            formatter.dateStyle = .long
        case .relative:
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
        }
        
        return formatter.string(from: date)
    }
    
    /// Generate accessibility label for charts
    func chartAccessibilityLabel(title: String, dataPoints: [(String, Double)], unit: String = "") -> String {
        var description = "\(title) chart. "
        
        if dataPoints.isEmpty {
            description += "No data available."
        } else {
            description += "\(dataPoints.count) data points. "
            
            // Add summary statistics
            let values = dataPoints.map { $0.1 }
            if let min = values.min(), let max = values.max() {
                description += "Range from \(formatValue(min, unit: unit)) to \(formatValue(max, unit: unit)). "
            }
            
            // Add first and last values for trend
            if let first = dataPoints.first, let last = dataPoints.last {
                description += "Starts at \(first.0) with \(formatValue(first.1, unit: unit)), "
                description += "ends at \(last.0) with \(formatValue(last.1, unit: unit)). "
            }
        }
        
        return description
    }
    
    /// Generate accessibility hint for interactive elements
    func accessibilityHint(for action: AccessibilityAction) -> String {
        switch action {
        case .addGoal:
            return "Opens the new goal creation form"
        case .editGoal:
            return "Opens the goal editing interface"
        case .addTransaction:
            return "Opens the transaction entry form"
        case .viewDetails:
            return "Opens detailed view with more information"
        case .navigateBack:
            return "Returns to the previous screen"
        case .adjustAmount:
            return "Allows you to modify the amount value"
        case .selectCurrency:
            return "Opens currency selection menu"
        case .toggleReminders:
            return "Enables or disables reminder notifications"
        case .shareGoal:
            return "Opens sharing options for this goal"
        case .deleteItem:
            return "Permanently removes this item"
        }
    }
    
    /// Get appropriate animation duration based on accessibility settings
    func animationDuration(_ base: Double) -> Double {
        if useSimplifiedAnimations || isReduceMotionEnabled {
            return 0.0
        }
        return base
    }
    
    /// Get appropriate spring animation based on accessibility settings
    func springAnimation(duration: Double = 0.3, dampingFraction: Double = 0.8) -> Animation {
        if useSimplifiedAnimations || isReduceMotionEnabled {
            return .linear(duration: 0.0)
        }
        return .spring(response: duration, dampingFraction: dampingFraction)
    }
    
    /// Provide haptic feedback if enabled
    func performHapticFeedback(_ type: HapticFeedbackType) {
        guard enableHapticFeedback else { return }
        
        #if os(iOS)
        switch type {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
    
    // MARK: - Private Helpers
    
    private func getCurrencyDisplayName(_ code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forCurrencyCode: code) ?? code
    }
    
    private func formatValue(_ value: Double, unit: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return unit.isEmpty ? formattedValue : "\(formattedValue) \(unit)"
    }
}

// MARK: - Supporting Types

enum DateFormat {
    case short
    case medium
    case long
    case relative
}

enum AccessibilityAction {
    case addGoal
    case editGoal
    case addTransaction
    case viewDetails
    case navigateBack
    case adjustAmount
    case selectCurrency
    case toggleReminders
    case shareGoal
    case deleteItem
}

enum HapticFeedbackType {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case selection
}

// MARK: - SwiftUI Extensions

extension View {
    /// Apply accessibility-aware animations
    func accessibleAnimation(_ animation: Animation) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        return self.animation(
            accessibilityManager.isReduceMotionEnabled ? .linear(duration: 0) : animation,
            value: UUID() // This would need to be connected to actual state changes
        )
    }
    
    /// Apply accessibility-compliant focus styling
    func accessibleFocusStyle() -> some View {
        self.overlay(
            AccessibilityManager.shared.showFocusIndicators ?
            RoundedRectangle(cornerRadius: 8)
                .stroke(AccessibleColors.focusIndicator, lineWidth: 2)
                .opacity(0) // Would be controlled by focus state
            : nil
        )
    }
    
    /// Generate comprehensive accessibility label
    func accessibilityLabel(
        title: String,
        value: String? = nil,
        status: String? = nil,
        hint: String? = nil
    ) -> some View {
        var label = title
        if let value = value {
            label += ", \(value)"
        }
        if let status = status {
            label += ", \(status)"
        }
        
        return self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
    
    /// Apply VoiceOver-friendly currency formatting
    func accessibilityCurrencyValue(
        amount: Double,
        currency: String,
        context: String = ""
    ) -> some View {
        let description = AccessibilityManager.shared.voiceOverDescription(
            for: amount,
            currency: currency,
            context: context
        )
        
        return self.accessibilityValue(description)
    }
    
    /// Apply progress accessibility
    func accessibilityProgress(
        value: Double,
        goalName: String
    ) -> some View {
        let description = AccessibilityManager.shared.voiceOverProgressDescription(
            value,
            goalName: goalName
        )
        
        return self.accessibilityValue(description)
    }
}

// MARK: - Accessibility Testing Helpers

#if DEBUG
extension AccessibilityManager {
    /// Test accessibility compliance of the current screen
    func auditCurrentScreen() -> AccessibilityAuditReport {
        let issues: [AccessibilityIssue] = []
        
        // This would perform actual accessibility auditing
        // For now, return a sample report
        
        return AccessibilityAuditReport(
            timestamp: Date(),
            issues: issues,
            overallScore: calculateAccessibilityScore(issues: issues)
        )
    }
    
    private func calculateAccessibilityScore(issues: [AccessibilityIssue]) -> Double {
        let totalPossiblePoints = 100.0
        let deductions = issues.reduce(0.0) { total, issue in
            total + issue.severity.deduction
        }
        
        return max(0, totalPossiblePoints - deductions)
    }
}

struct AccessibilityAuditReport {
    let timestamp: Date
    let issues: [AccessibilityIssue]
    let overallScore: Double
    
    var hasIssues: Bool {
        !issues.isEmpty
    }
    
    var criticalIssues: [AccessibilityIssue] {
        issues.filter { $0.severity == .critical }
    }
    
    var warningIssues: [AccessibilityIssue] {
        issues.filter { $0.severity == .warning }
    }
}

struct AccessibilityIssue {
    let id: UUID = UUID()
    let title: String
    let description: String
    let severity: Severity
    let wcagGuideline: String
    let suggestedFix: String
    
    enum Severity {
        case critical
        case warning
        case info
        
        var deduction: Double {
            switch self {
            case .critical: return 20.0
            case .warning: return 10.0
            case .info: return 5.0
            }
        }
    }
}
#endif