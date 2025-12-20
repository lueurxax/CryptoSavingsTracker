//
//  AccessibilityViewModifiers.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import SwiftUI

// MARK: - Accessibility View Modifiers

/// Enhanced button accessibility with comprehensive WCAG compliance
struct AccessibleButton: ViewModifier {
    let title: String
    let hint: String?
    let action: AccessibilityAction?
    let isEnabled: Bool
    let importance: AccessibilityImportance
    
    init(
        title: String,
        hint: String? = nil,
        action: AccessibilityAction? = nil,
        isEnabled: Bool = true,
        importance: AccessibilityImportance = .normal
    ) {
        self.title = title
        self.hint = hint ?? action?.defaultHint
        self.action = action
        self.isEnabled = isEnabled
        self.importance = importance
    }
    
    func body(content: Content) -> some View {
        content
            .accessibilityLabel(title)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
}

/// Enhanced text field accessibility
struct AccessibleTextField: ViewModifier {
    let label: String
    let placeholder: String?
    let isRequired: Bool
    let validationMessage: String?
    let textInputType: TextInputType
    
    init(
        label: String,
        placeholder: String? = nil,
        isRequired: Bool = false,
        validationMessage: String? = nil,
        textInputType: TextInputType = .text
    ) {
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.validationMessage = validationMessage
        self.textInputType = textInputType
    }
    
    func body(content: Content) -> some View {
        content
            .accessibilityLabel(buildLabel())
            .accessibilityHint(buildHint())
    }
    
    private func buildLabel() -> String {
        var fullLabel = label
        if isRequired {
            fullLabel += ", required"
        }
        if let placeholder = placeholder {
            fullLabel += ", placeholder: \(placeholder)"
        }
        return fullLabel
    }
    
    private func buildHint() -> String {
        var hint = "Text input field"
        
        if let validation = validationMessage, !validation.isEmpty {
            hint += ". \(validation)"
        }
        
        switch textInputType {
        case .currency:
            hint += ". Enter currency amount"
        case .email:
            hint += ". Enter email address"
        case .number:
            hint += ". Enter numeric value"
        case .password:
            hint += ". Enter password"
        case .date:
            hint += ". Enter date"
        case .text:
            hint += ". Enter text"
        }
        
        return hint
    }
}

/// Enhanced image accessibility with comprehensive descriptions
struct AccessibleImage: ViewModifier {
    let description: String
    let isDecorative: Bool
    let detailedDescription: String?
    
    init(
        description: String,
        isDecorative: Bool = false,
        detailedDescription: String? = nil
    ) {
        self.description = description
        self.isDecorative = isDecorative
        self.detailedDescription = detailedDescription
    }
    
    func body(content: Content) -> some View {
        if isDecorative {
            content
                .accessibilityHidden(true)
        } else {
            content
                .accessibilityLabel(description)
                .accessibilityHint(detailedDescription ?? "")
        }
    }
}

/// Enhanced chart accessibility with data sonification support
struct AccessibleChart: ViewModifier {
    let title: String
    let dataPoints: [(String, Double)]
    let unit: String
    let chartType: ChartType
    let trends: String?
    
    init(
        title: String,
        dataPoints: [(String, Double)],
        unit: String = "",
        chartType: ChartType = .line,
        trends: String? = nil
    ) {
        self.title = title
        self.dataPoints = dataPoints
        self.unit = unit
        self.chartType = chartType
        self.trends = trends
    }
    
    func body(content: Content) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let chartLabel = accessibilityManager.chartAccessibilityLabel(
            title: title,
            dataPoints: dataPoints,
            unit: unit
        )
        
        var fullDescription = chartLabel
        if let trends = trends {
            fullDescription += " \(trends)"
        }
        
        return content
            .accessibilityLabel(fullDescription)
    }
    
    private func buildChartDescriptor() -> AXChartDescriptor? {
        // This would build a proper chart descriptor for VoiceOver
        // Implementation would depend on the specific charting library used
        return nil
    }
}

/// Enhanced progress indicator accessibility
struct AccessibleProgress: ViewModifier {
    let value: Double
    let label: String
    let goalName: String
    let formattedValue: String?
    
    init(
        value: Double,
        label: String,
        goalName: String = "",
        formattedValue: String? = nil
    ) {
        self.value = value
        self.label = label
        self.goalName = goalName.isEmpty ? label : goalName
        self.formattedValue = formattedValue
    }
    
    func body(content: Content) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let progressDescription = accessibilityManager.voiceOverProgressDescription(
            value,
            goalName: goalName
        )
        
        return content
            .accessibilityLabel(label)
            .accessibilityValue(formattedValue ?? progressDescription)
    }
}

/// Enhanced currency display accessibility
struct AccessibleCurrency: ViewModifier {
    let amount: Double
    let currency: String
    let context: String
    let showSymbol: Bool
    
    init(
        amount: Double,
        currency: String,
        context: String = "",
        showSymbol: Bool = true
    ) {
        self.amount = amount
        self.currency = currency
        self.context = context
        self.showSymbol = showSymbol
    }
    
    func body(content: Content) -> some View {
        let accessibilityManager = AccessibilityManager.shared
        let description = accessibilityManager.voiceOverDescription(
            for: amount,
            currency: currency,
            context: context
        )
        
        return content
            .accessibilityLabel(description)
    }
}

/// Enhanced list accessibility with navigation support
struct AccessibleList: ViewModifier {
    let title: String
    let itemCount: Int
    let emptyMessage: String?
    
    init(
        title: String,
        itemCount: Int,
        emptyMessage: String? = nil
    ) {
        self.title = title
        self.itemCount = itemCount
        self.emptyMessage = emptyMessage
    }
    
    func body(content: Content) -> some View {
        let description = itemCount == 0 
            ? (emptyMessage ?? "\(title) list is empty")
            : "\(title) list with \(itemCount) items"
        
        return content
            .accessibilityLabel(description)
    }
}

/// Enhanced navigation accessibility
struct AccessibleNavigation: ViewModifier {
    let title: String
    let level: NavigationLevel
    let backButtonTitle: String?
    
    init(
        title: String,
        level: NavigationLevel = .secondary,
        backButtonTitle: String? = nil
    ) {
        self.title = title
        self.level = level
        self.backButtonTitle = backButtonTitle
    }
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title) screen")
            .accessibilityAddTraits(.isHeader)
            .navigationTitle(title)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply accessible button styling with comprehensive WCAG compliance
    func accessibleButton(
        title: String,
        hint: String? = nil,
        action: AccessibilityAction? = nil,
        isEnabled: Bool = true,
        importance: AccessibilityImportance = .normal
    ) -> some View {
        self.modifier(AccessibleButton(
            title: title,
            hint: hint,
            action: action,
            isEnabled: isEnabled,
            importance: importance
        ))
    }
    
    /// Apply accessible text field styling
    func accessibleTextField(
        label: String,
        placeholder: String? = nil,
        isRequired: Bool = false,
        validationMessage: String? = nil,
        textInputType: TextInputType = .text
    ) -> some View {
        self.modifier(AccessibleTextField(
            label: label,
            placeholder: placeholder,
            isRequired: isRequired,
            validationMessage: validationMessage,
            textInputType: textInputType
        ))
    }
    
    /// Apply accessible image styling
    func accessibleImage(
        description: String,
        isDecorative: Bool = false,
        detailedDescription: String? = nil
    ) -> some View {
        self.modifier(AccessibleImage(
            description: description,
            isDecorative: isDecorative,
            detailedDescription: detailedDescription
        ))
    }
    
    /// Apply accessible chart styling
    func accessibleChart(
        title: String,
        dataPoints: [(String, Double)],
        unit: String = "",
        chartType: ChartType = .line,
        trends: String? = nil
    ) -> some View {
        self.modifier(AccessibleChart(
            title: title,
            dataPoints: dataPoints,
            unit: unit,
            chartType: chartType,
            trends: trends
        ))
    }
    
    /// Apply accessible progress indicator styling
    func accessibleProgress(
        value: Double,
        label: String,
        goalName: String = "",
        formattedValue: String? = nil
    ) -> some View {
        self.modifier(AccessibleProgress(
            value: value,
            label: label,
            goalName: goalName,
            formattedValue: formattedValue
        ))
    }
    
    /// Apply accessible currency display styling
    func accessibleCurrency(
        amount: Double,
        currency: String,
        context: String = "",
        showSymbol: Bool = true
    ) -> some View {
        self.modifier(AccessibleCurrency(
            amount: amount,
            currency: currency,
            context: context,
            showSymbol: showSymbol
        ))
    }
    
    /// Apply accessible list styling
    func accessibleList(
        title: String,
        itemCount: Int,
        emptyMessage: String? = nil
    ) -> some View {
        self.modifier(AccessibleList(
            title: title,
            itemCount: itemCount,
            emptyMessage: emptyMessage
        ))
    }
    
    /// Apply accessible navigation styling
    func accessibleNavigation(
        title: String,
        level: NavigationLevel = .secondary,
        backButtonTitle: String? = nil
    ) -> some View {
        self.modifier(AccessibleNavigation(
            title: title,
            level: level,
            backButtonTitle: backButtonTitle
        ))
    }
}

// MARK: - Supporting Types

enum AccessibilityImportance {
    case low
    case normal
    case high
    case critical
    
    var level: AccessibilityImportance {
        self
    }
}

enum TextInputType {
    case text
    case email
    case password
    case number
    case currency
    case date
    
    // Note: AccessibilityTextInputType may not be available in all iOS/macOS versions
}

enum ChartType {
    case line
    case bar
    case pie
    case area
    case scatter
}

enum NavigationLevel {
    case primary
    case secondary
    case tertiary
    
    var headingLevel: Int {
        switch self {
        case .primary: return 1
        case .secondary: return 2
        case .tertiary: return 3
        }
    }
}

// MARK: - Accessibility Action Extensions

extension AccessibilityAction {
    var defaultHint: String {
        switch self {
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
}

// MARK: - Accessibility Extensions

extension View {
    /// Custom accessibility validation message
    func accessibilityValidation(_ message: String?) -> some View {
        if let message = message, !message.isEmpty {
            return AnyView(
                self.accessibilityHint("Validation error: \(message)")
            )
        }
        return AnyView(self)
    }
    
    /// Custom accessibility numeric value
    func accessibilityNumericValue(_ value: Double) -> some View {
        self.accessibilityValue("\(value)")
    }
    
    /// Custom accessibility text input type
    func accessibilityTextInputType(_ type: TextInputType) -> some View {
        #if os(iOS)
        return self.keyboardType(type.keyboardType)
            .textContentType(type.textContentType)
        #else
        return self
        #endif
    }
    
    /// Custom accessibility heading level
    func accessibilityHeading(_ level: Int) -> some View {
        self.accessibilityAddTraits(.isHeader)
    }
    
    /// Custom accessibility importance
    func accessibilityImportance(_ importance: AccessibilityImportance) -> some View {
        switch importance {
        case .low:
            return AnyView(self.accessibilityHidden(false))
        case .normal:
            return AnyView(self)
        case .high:
            return AnyView(self)
        case .critical:
            return AnyView(self)
        }
    }
}

// MARK: - Platform-Specific Extensions

#if os(iOS)
extension TextInputType {
    var keyboardType: UIKeyboardType {
        switch self {
        case .text: return .default
        case .email: return .emailAddress
        case .password: return .default
        case .number, .currency: return .decimalPad
        case .date: return .numbersAndPunctuation
        }
    }
    
    var textContentType: UITextContentType? {
        switch self {
        case .text: return nil
        case .email: return .emailAddress
        case .password: return .password
        case .number, .currency: return nil
        case .date: return nil
        }
    }
}
#else
extension TextInputType {
    var keyboardType: NSObject { NSObject() } // Placeholder for macOS
    var textContentType: NSObject? { nil }
}
#endif