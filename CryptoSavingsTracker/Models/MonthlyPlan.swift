//
//  MonthlyPlan.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation
import SwiftData

/// SwiftData model for persisting monthly planning calculations and user preferences
@Model
final class MonthlyPlan: @unchecked Sendable {
    
    // MARK: - Primary Properties
    @Attribute(.unique) var id: UUID
    var goalId: UUID
    var requiredMonthly: Double
    var remainingAmount: Double
    var monthsRemaining: Int
    var currency: String
    var statusRawValue: String
    var lastCalculated: Date
    
    // MARK: - User Preferences  
    var flexStateRawValue: String = "flexible"
    var customAmount: Double? // User override amount
    var isProtected: Bool = false // Protected from flex adjustments
    var isSkipped: Bool = false // Temporarily skip this month
    
    // MARK: - Metadata
    var createdDate: Date
    var lastModifiedDate: Date
    var version: Int = 1 // For future model migrations
    
    // MARK: - Computed Properties
    
    /// Requirement status enum wrapper
    var status: RequirementStatus {
        get {
            RequirementStatus(rawValue: statusRawValue) ?? .onTrack
        }
        set {
            statusRawValue = newValue.rawValue
            lastModifiedDate = Date()
        }
    }
    
    /// Flex state enum wrapper
    var flexState: FlexState {
        get {
            FlexState(rawValue: flexStateRawValue) ?? .flexible
        }
        set {
            flexStateRawValue = newValue.rawValue
            lastModifiedDate = Date()
        }
    }
    
    /// Effective amount considering user preferences
    var effectiveAmount: Double {
        if isSkipped {
            return 0
        }
        return customAmount ?? requiredMonthly
    }
    
    /// Whether this plan needs recalculation
    var needsRecalculation: Bool {
        let maxAge: TimeInterval = 3600 // 1 hour
        return Date().timeIntervalSince(lastCalculated) > maxAge
    }
    
    /// Human-readable description of flex state
    var flexStateDescription: String {
        switch flexState {
        case .protected:
            return "Protected from adjustments"
        case .flexible:
            return "Can be adjusted"
        case .skipped:
            return "Skipped this month"
        }
    }
    
    // MARK: - Initialization
    
    init(
        goalId: UUID,
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        currency: String,
        status: RequirementStatus = .onTrack,
        flexState: FlexState = .flexible
    ) {
        self.id = UUID()
        self.goalId = goalId
        self.requiredMonthly = requiredMonthly
        self.remainingAmount = remainingAmount
        self.monthsRemaining = monthsRemaining
        self.currency = currency
        self.statusRawValue = status.rawValue
        self.lastCalculated = Date()
        self.flexStateRawValue = flexState.rawValue
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
    
    // MARK: - Business Logic
    
    /// Update calculation results while preserving user preferences
    func updateCalculation(
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        status: RequirementStatus
    ) {
        self.requiredMonthly = requiredMonthly
        self.remainingAmount = remainingAmount
        self.monthsRemaining = monthsRemaining
        self.status = status
        self.lastCalculated = Date()
        self.lastModifiedDate = Date()
    }
    
    /// Set custom amount override
    func setCustomAmount(_ amount: Double?) {
        self.customAmount = amount
        self.lastModifiedDate = Date()
    }
    
    /// Toggle protection status
    func toggleProtection() {
        self.isProtected.toggle()
        self.flexState = isProtected ? .protected : .flexible
        self.lastModifiedDate = Date()
    }
    
    /// Skip this month's payment
    func skipThisMonth(_ skip: Bool = true) {
        self.isSkipped = skip
        self.flexState = skip ? .skipped : .flexible
        self.lastModifiedDate = Date()
    }
    
    /// Reset to default state
    func resetToDefaults() {
        self.customAmount = nil
        self.isProtected = false
        self.isSkipped = false
        self.flexState = .flexible
        self.lastModifiedDate = Date()
    }
    
    /// Apply flex adjustment percentage
    func applyFlexAdjustment(_ percentage: Double) {
        guard flexState == .flexible else { return }
        
        let adjustedAmount = requiredMonthly * percentage
        setCustomAmount(adjustedAmount)
    }
    
    /// Check if plan is valid and actionable
    var isActionable: Bool {
        return !isSkipped && remainingAmount > 0 && effectiveAmount > 0
    }
    
    /// Format effective amount for display
    func formattedEffectiveAmount() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: effectiveAmount)) ?? 
               "\(currency) \(String(format: "%.2f", effectiveAmount))"
    }
}

// MARK: - Flex State Enum

extension MonthlyPlan {
    enum FlexState: String, Codable, CaseIterable, Sendable {
        case protected = "protected"   // Cannot be reduced in flex adjustments
        case flexible = "flexible"     // Can be adjusted up or down
        case skipped = "skipped"      // Temporarily excluded from payments
        
        var displayName: String {
            switch self {
            case .protected: return "Protected"
            case .flexible: return "Flexible"
            case .skipped: return "Skipped"
            }
        }
        
        var systemImageName: String {
            switch self {
            case .protected: return "lock.fill"
            case .flexible: return "slider.horizontal.3"
            case .skipped: return "forward.fill"
            }
        }
        
        var color: String {
            switch self {
            case .protected: return "systemBlue"
            case .flexible: return "systemGray"
            case .skipped: return "systemGray2"
            }
        }
        
        /// Whether this state allows amount modifications
        var allowsModification: Bool {
            switch self {
            case .protected: return false
            case .flexible: return true
            case .skipped: return false
            }
        }
    }
}

// MARK: - Validation

extension MonthlyPlan {
    
    /// Validate the monthly plan data
    func validate() -> [String] {
        var errors: [String] = []
        
        if requiredMonthly < 0 {
            errors.append("Required monthly amount cannot be negative")
        }
        
        if remainingAmount < 0 {
            errors.append("Remaining amount cannot be negative")
        }
        
        if monthsRemaining <= 0 {
            errors.append("Months remaining must be greater than zero")
        }
        
        if currency.isEmpty {
            errors.append("Currency is required")
        }
        
        if let custom = customAmount, custom < 0 {
            errors.append("Custom amount cannot be negative")
        }
        
        // Validate that custom amount isn't impossibly high
        if let custom = customAmount, custom > requiredMonthly * 10 {
            errors.append("Custom amount seems unreasonably high")
        }
        
        return errors
    }
    
    /// Check if the plan is internally consistent
    var isConsistent: Bool {
        validate().isEmpty
    }
}

// MARK: - Queries and Predicates

extension MonthlyPlan {
    
    /// Predicate for plans that need recalculation
    static var needsRecalculationPredicate: Predicate<MonthlyPlan> {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return #Predicate<MonthlyPlan> { plan in
            plan.lastCalculated < oneHourAgo
        }
    }
    
    /// Predicate for actionable plans (not skipped, has remaining amount)
    static var actionablePredicate: Predicate<MonthlyPlan> {
        #Predicate<MonthlyPlan> { plan in
            !plan.isSkipped && plan.remainingAmount > 0
        }
    }
    
    /// Predicate for plans by goal ID
    static func planForGoal(_ goalId: UUID) -> Predicate<MonthlyPlan> {
        #Predicate<MonthlyPlan> { plan in
            plan.goalId == goalId
        }
    }
    
    /// Predicate for flexible plans (can be adjusted)
    static var flexiblePredicate: Predicate<MonthlyPlan> {
        #Predicate<MonthlyPlan> { plan in
            plan.flexStateRawValue == "flexible"
        }
    }
    
    /// Predicate for protected plans
    static var protectedPredicate: Predicate<MonthlyPlan> {
        #Predicate<MonthlyPlan> { plan in
            plan.flexStateRawValue == "protected"
        }
    }
}

// MARK: - Convenience Extensions

extension MonthlyPlan {
    
    /// Create a monthly plan from calculation results
    static func fromCalculation(
        goalId: UUID,
        targetAmount: Double,
        currentTotal: Double,
        deadline: Date,
        currency: String
    ) -> MonthlyPlan {
        let remaining = max(0, targetAmount - currentTotal)
        let monthsLeft = max(1, Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 1)
        let required = remaining / Double(monthsLeft)
        
        let status: RequirementStatus
        if remaining <= 0 {
            status = .completed
        } else if required > 10000 {
            status = .critical
        } else if required > 5000 || monthsLeft <= 1 {
            status = .attention
        } else {
            status = .onTrack
        }
        
        return MonthlyPlan(
            goalId: goalId,
            requiredMonthly: required,
            remainingAmount: remaining,
            monthsRemaining: monthsLeft,
            currency: currency,
            status: status
        )
    }
}