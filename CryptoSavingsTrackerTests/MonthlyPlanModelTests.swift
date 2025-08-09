//
//  MonthlyPlanModelTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by Claude on 09/08/2025.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

struct MonthlyPlanModelTests {
    
    var modelContainer: ModelContainer
    
    init() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: MonthlyPlan.self,
            configurations: config
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test("Create monthly plan with basic parameters")
    func testBasicInitialization() async throws {
        // Given
        let goalId = UUID()
        let requiredMonthly = 1500.0
        let remainingAmount = 6000.0
        let monthsRemaining = 4
        let currency = "USD"
        
        // When
        let plan = MonthlyPlan(
            goalId: goalId,
            requiredMonthly: requiredMonthly,
            remainingAmount: remainingAmount,
            monthsRemaining: monthsRemaining,
            currency: currency
        )
        
        // Then
        #expect(plan.goalId == goalId)
        #expect(plan.requiredMonthly == requiredMonthly)
        #expect(plan.remainingAmount == remainingAmount)
        #expect(plan.monthsRemaining == monthsRemaining)
        #expect(plan.currency == currency)
        #expect(plan.status == .onTrack)
        #expect(plan.flexState == .flexible)
        #expect(plan.customAmount == nil)
        #expect(plan.isProtected == false)
        #expect(plan.isSkipped == false)
    }
    
    @Test("Create plan from calculation")
    func testFromCalculation() async throws {
        // Given
        let goalId = UUID()
        let targetAmount = 10000.0
        let currentTotal = 2500.0
        let deadline = Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        let currency = "EUR"
        
        // When
        let plan = MonthlyPlan.fromCalculation(
            goalId: goalId,
            targetAmount: targetAmount,
            currentTotal: currentTotal,
            deadline: deadline,
            currency: currency
        )
        
        // Then
        #expect(plan.goalId == goalId)
        #expect(plan.remainingAmount == 7500.0) // 10000 - 2500
        #expect(plan.monthsRemaining == 5)
        #expect(plan.requiredMonthly == 1500.0) // 7500 / 5
        #expect(plan.currency == currency)
        #expect(plan.status == .onTrack)
    }
    
    // MARK: - Status Tests
    
    @Test("Status determination from calculation")
    func testStatusDeterminationCompleted() async throws {
        // Given - completed goal
        let plan = MonthlyPlan.fromCalculation(
            goalId: UUID(),
            targetAmount: 5000,
            currentTotal: 6000, // Over target
            deadline: Date().addingTimeInterval(86400 * 30),
            currency: "USD"
        )
        
        // Then
        #expect(plan.status == .completed)
        #expect(plan.remainingAmount == 0)
        #expect(plan.requiredMonthly == 0)
    }
    
    @Test("Status determination critical")
    func testStatusDeterminationCritical() async throws {
        // Given - critical requirement (over 10k monthly)
        let plan = MonthlyPlan.fromCalculation(
            goalId: UUID(),
            targetAmount: 25000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
            currency: "USD"
        )
        
        // Then
        #expect(plan.status == .critical)
        #expect(plan.requiredMonthly == 20000) // (25000-5000)/1
    }
    
    @Test("Status determination attention")
    func testStatusDeterminationAttention() async throws {
        // Given - attention status (over 5k monthly)
        let plan = MonthlyPlan.fromCalculation(
            goalId: UUID(),
            targetAmount: 18000,
            currentTotal: 6000,
            deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!,
            currency: "USD"
        )
        
        // Then
        #expect(plan.status == .attention)
        #expect(plan.requiredMonthly == 6000) // (18000-6000)/2
    }
    
    // MARK: - Flex State Tests
    
    @Test("Flex state management")
    func testFlexStateManagement() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1000,
            remainingAmount: 5000,
            monthsRemaining: 5,
            currency: "USD"
        )
        
        // When - toggle protection
        plan.toggleProtection()
        
        // Then
        #expect(plan.isProtected == true)
        #expect(plan.flexState == .protected)
        
        // When - toggle back
        plan.toggleProtection()
        
        // Then
        #expect(plan.isProtected == false)
        #expect(plan.flexState == .flexible)
    }
    
    @Test("Skip month functionality")
    func testSkipMonth() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 800,
            remainingAmount: 3200,
            monthsRemaining: 4,
            currency: "GBP"
        )
        
        // When
        plan.skipThisMonth(true)
        
        // Then
        #expect(plan.isSkipped == true)
        #expect(plan.flexState == .skipped)
        #expect(plan.effectiveAmount == 0)
        
        // When - unskip
        plan.skipThisMonth(false)
        
        // Then
        #expect(plan.isSkipped == false)
        #expect(plan.flexState == .flexible)
        #expect(plan.effectiveAmount == 800)
    }
    
    // MARK: - Custom Amount Tests
    
    @Test("Custom amount override")
    func testCustomAmountOverride() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1000,
            remainingAmount: 4000,
            monthsRemaining: 4,
            currency: "USD"
        )
        
        // When
        plan.setCustomAmount(750)
        
        // Then
        #expect(plan.customAmount == 750)
        #expect(plan.effectiveAmount == 750)
        
        // When - clear custom amount
        plan.setCustomAmount(nil)
        
        // Then
        #expect(plan.customAmount == nil)
        #expect(plan.effectiveAmount == 1000) // Back to required amount
    }
    
    @Test("Flex adjustment calculation")
    func testFlexAdjustment() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 2000,
            remainingAmount: 8000,
            monthsRemaining: 4,
            currency: "USD"
        )
        
        // When - apply 75% adjustment
        plan.applyFlexAdjustment(0.75)
        
        // Then
        #expect(plan.customAmount == 1500) // 2000 * 0.75
        #expect(plan.effectiveAmount == 1500)
        
        // When - protect and try to adjust
        plan.toggleProtection()
        plan.applyFlexAdjustment(0.5) // Should have no effect
        
        // Then
        #expect(plan.customAmount == 1500) // Unchanged
        #expect(plan.flexState == .protected)
    }
    
    // MARK: - Validation Tests
    
    @Test("Plan validation success")
    func testValidPlan() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 500,
            remainingAmount: 2000,
            monthsRemaining: 4,
            currency: "EUR"
        )
        
        // When
        let errors = plan.validate()
        
        // Then
        #expect(errors.isEmpty)
        #expect(plan.isConsistent == true)
    }
    
    @Test("Plan validation failures")
    func testInvalidPlan() async throws {
        // Given - invalid plan
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: -100, // Invalid negative
            remainingAmount: -500, // Invalid negative
            monthsRemaining: 0, // Invalid zero
            currency: "" // Invalid empty
        )
        
        plan.setCustomAmount(-250) // Invalid negative custom amount
        
        // When
        let errors = plan.validate()
        
        // Then
        #expect(errors.count >= 4) // Should have multiple validation errors
        #expect(plan.isConsistent == false)
        
        let errorMessages = errors.joined(separator: ", ")
        #expect(errorMessages.contains("negative"))
        #expect(errorMessages.contains("Currency is required"))
        #expect(errorMessages.contains("greater than zero"))
    }
    
    @Test("Unreasonably high custom amount")
    func testUnreasonablyHighCustomAmount() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1000,
            remainingAmount: 5000,
            monthsRemaining: 5,
            currency: "USD"
        )
        
        // When - set unreasonably high custom amount
        plan.setCustomAmount(15000) // 15x the required amount
        
        // Then
        let errors = plan.validate()
        #expect(errors.contains { $0.contains("unreasonably high") })
    }
    
    // MARK: - Business Logic Tests
    
    @Test("Actionable plan determination")
    func testActionablePlans() async throws {
        // Given - actionable plan
        let actionablePlan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 500,
            remainingAmount: 2000,
            monthsRemaining: 4,
            currency: "USD"
        )
        
        // Given - skipped plan
        let skippedPlan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 300,
            remainingAmount: 1200,
            monthsRemaining: 4,
            currency: "USD"
        )
        skippedPlan.skipThisMonth()
        
        // Given - completed plan
        let completedPlan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 0,
            remainingAmount: 0,
            monthsRemaining: 3,
            currency: "USD"
        )
        
        // Then
        #expect(actionablePlan.isActionable == true)
        #expect(skippedPlan.isActionable == false)
        #expect(completedPlan.isActionable == false)
    }
    
    @Test("Reset to defaults")
    func testResetToDefaults() async throws {
        // Given - modified plan
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1200,
            remainingAmount: 6000,
            monthsRemaining: 5,
            currency: "EUR"
        )
        
        plan.setCustomAmount(800)
        plan.toggleProtection()
        plan.skipThisMonth()
        
        // When
        plan.resetToDefaults()
        
        // Then
        #expect(plan.customAmount == nil)
        #expect(plan.isProtected == false)
        #expect(plan.isSkipped == false)
        #expect(plan.flexState == .flexible)
        #expect(plan.effectiveAmount == 1200)
    }
    
    // MARK: - Formatting Tests
    
    @Test("Amount formatting")
    func testAmountFormatting() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1234.56,
            remainingAmount: 5432.10,
            monthsRemaining: 4,
            currency: "USD"
        )
        
        // When
        let formatted = plan.formattedEffectiveAmount()
        
        // Then
        #expect(formatted.contains("1234.56") || formatted.contains("1,234.56"))
        #expect(formatted.contains("USD") || formatted.contains("$"))
    }
    
    // MARK: - Update Calculation Tests
    
    @Test("Update calculation preserves user preferences")
    func testUpdateCalculationPreservesPreferences() async throws {
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 1000,
            remainingAmount: 5000,
            monthsRemaining: 5,
            currency: "USD"
        )
        
        // Set user preferences
        plan.setCustomAmount(750)
        plan.toggleProtection()
        let originalCustomAmount = plan.customAmount
        let originalFlexState = plan.flexState
        
        // When - update calculation
        plan.updateCalculation(
            requiredMonthly: 1200, // New calculated amount
            remainingAmount: 4800,
            monthsRemaining: 4,
            status: .attention
        )
        
        // Then - calculation updated but preferences preserved
        #expect(plan.requiredMonthly == 1200)
        #expect(plan.remainingAmount == 4800)
        #expect(plan.monthsRemaining == 4)
        #expect(plan.status == .attention)
        
        // User preferences preserved
        #expect(plan.customAmount == originalCustomAmount)
        #expect(plan.flexState == originalFlexState)
        #expect(plan.effectiveAmount == 750) // Still using custom amount
    }
    
    // MARK: - Needs Recalculation Tests
    
    @Test("Needs recalculation determination")
    func testNeedsRecalculation() async throws {
        // Given - fresh plan
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 500,
            remainingAmount: 2000,
            monthsRemaining: 4,
            currency: "USD"
        )
        
        // Then - fresh plan doesn't need recalculation
        #expect(plan.needsRecalculation == false)
        
        // When - simulate old calculation
        let oldDate = Date().addingTimeInterval(-7200) // 2 hours ago
        plan.lastCalculated = oldDate
        
        // Then - old plan needs recalculation
        #expect(plan.needsRecalculation == true)
    }
    
    // MARK: - SwiftData Persistence Tests
    
    @Test("SwiftData persistence")
    func testSwiftDataPersistence() async throws {
        let context = modelContainer.mainContext
        
        // Given
        let plan = MonthlyPlan(
            goalId: UUID(),
            requiredMonthly: 800,
            remainingAmount: 3200,
            monthsRemaining: 4,
            currency: "GBP"
        )
        
        plan.setCustomAmount(600)
        plan.toggleProtection()
        
        // When - save to SwiftData
        context.insert(plan)
        try context.save()
        
        // Clear memory
        let planId = plan.id
        context.delete(plan)
        
        // Fetch from database
        let descriptor = FetchDescriptor<MonthlyPlan>(
            predicate: #Predicate { $0.id == planId }
        )
        let fetchedPlans = try context.fetch(descriptor)
        
        // Then
        #expect(fetchedPlans.count == 1)
        let fetchedPlan = fetchedPlans.first!
        
        #expect(fetchedPlan.requiredMonthly == 800)
        #expect(fetchedPlan.customAmount == 600)
        #expect(fetchedPlan.isProtected == true)
        #expect(fetchedPlan.flexState == .protected)
        #expect(fetchedPlan.currency == "GBP")
    }
}