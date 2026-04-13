//
//  GoalEditViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class GoalEditViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var goal: Goal
    @Published var isDirty: Bool = false
    @Published var validationErrors: [String] = []
    @Published var fieldErrors: [GoalValidationField: String] = [:]
    @Published var isSaving: Bool = false
    @Published var showingImpactPreview: Bool = false
    @Published var showingEmojiPicker: Bool = false
    
    // MARK: - Private Properties
    private let originalSnapshot: GoalSnapshot
    private let goalMutationService: GoalMutationServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var hasValidationErrors: Bool {
        !fieldErrors.isEmpty
    }
    
    var canSave: Bool {
        !hasValidationErrors && !isSaving
    }

    var firstInvalidField: GoalValidationField? {
        GoalValidationField.allCases.first { fieldErrors[$0] != nil }
    }
    
    var impactSummary: GoalImpact {
        goal.calculateImpact(from: originalSnapshot)
    }
    
    var hasSignificantChanges: Bool {
        impactSummary.significantChange
    }
    
    // MARK: - Initialization
    init(goal: Goal, modelContext: ModelContext) {
        self.goal = goal
        self.originalSnapshot = goal.createSnapshot()
        self.goalMutationService = DIContainer.shared.makeGoalMutationService(modelContext: modelContext)
        
        setupChangeDetection()
        validateImmediately()
    }
    
    // MARK: - Private Methods
    private func setupChangeDetection() {
        // Monitor goal changes to update dirty flag
        $goal
            .dropFirst() // Skip initial value
            .sink { [weak self] _ in
                self?.updateDirtyState()
                self?.validateWithDelay()
            }
            .store(in: &cancellables)
    }
    
    // Manual change detection trigger for SwiftData properties
    func triggerChangeDetection() {
        updateDirtyState()
        validateWithDelay()
    }
    
    private func updateDirtyState() {
        let wasDeep = isDirty
        isDirty = goal.hasChanges(from: originalSnapshot)
        showingImpactPreview = isDirty && hasSignificantChanges
        
        if isDirty != wasDeep {
        }
    }
    
    private func validateWithDelay() {
        // Debounce validation to avoid constant validation during typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.validate()
        }
    }
    
    private func validateImmediately() {
        validate()
    }
    
    // MARK: - Public Methods
    func validate() {
        fieldErrors = goal.validationErrorsByField()
        validationErrors = GoalValidationField.allCases.compactMap { fieldErrors[$0] }
    }
    
    func save() async throws {
        guard !isSaving else {
            throw GoalEditError.cannotSave("Goal save is already in progress")
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Final validation
            validate()
            guard !hasValidationErrors else {
                throw GoalEditError.validationFailed(validationErrors)
            }

            if !isDirty {
                return
            }

            if UITestFlags.consumeSimulatedGoalSaveFailureIfNeeded() {
                throw GoalEditError.cannotSave("Simulated UI test save failure")
            }

            clearReminderState()

            // Update modification timestamp
            goal.lastModifiedDate = Date()

            // Log goal save attempt with detailed field values

            try await goalMutationService.saveGoal(goal)

            // Verify data was saved by re-reading from context
            AppLog.info("✅ Goal '\(goal.name)' saved successfully", category: .goalEdit)

        } catch {
            AppLog.error("Failed to save goal: \(error)", category: .goalEdit)
            throw error
        }
    }
    
    func cancel() {
        // Revert all changes by copying values from snapshot
        goal.name = originalSnapshot.name
        goal.targetAmount = originalSnapshot.targetAmount
        goal.deadline = originalSnapshot.deadline
        goal.startDate = originalSnapshot.startDate
        goal.clearRetiredReminderState()
        goal.emoji = originalSnapshot.emoji
        goal.goalDescription = originalSnapshot.goalDescription
        goal.link = originalSnapshot.link
        
        // Reset state
        isDirty = false
        validationErrors.removeAll()
        showingImpactPreview = false
        
    }
    
    func resetToOriginal() {
        cancel() // Same behavior for now
    }
    
    // MARK: - URL Validation
    func isValidURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty else { return false }
        
        // Add https:// if no scheme is present
        var urlToValidate = urlString
        if !urlString.contains("://") {
            urlToValidate = "https://\(urlString)"
        }
        
        guard let url = URL(string: urlToValidate) else { return false }
        
        // Check if URL has valid scheme and host
        return url.scheme != nil && url.host != nil
    }
    
    // MARK: - Archive Operations
    func archiveGoal() async throws {
        guard !goal.isArchived else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await goalMutationService.archiveGoal(goal)
            
            AppLog.info("Goal '\(goal.name)' archived successfully", category: .goalEdit)
            
        } catch {
            AppLog.error("Failed to archive goal: \(error)", category: .goalEdit)
            throw GoalEditError.archiveFailed(error.localizedDescription)
        }
    }
    
    func restoreGoal() async throws {
        guard goal.isArchived else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await goalMutationService.restoreGoal(goal)
            
            AppLog.info("Goal '\(goal.name)' restored successfully", category: .goalEdit)
            
        } catch {
            AppLog.error("Failed to restore goal: \(error)", category: .goalEdit)
            throw GoalEditError.restoreFailed(error.localizedDescription)
        }
    }
    
    private func clearReminderState() {
        goal.clearRetiredReminderState()
    }
}

// MARK: - Goal Edit Errors
enum GoalEditError: LocalizedError {
    case cannotSave(String)
    case validationFailed([String])
    case archiveFailed(String)
    case restoreFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotSave(let reason):
            return "Cannot save goal: \(reason)"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.joined(separator: ", "))"
        case .archiveFailed(let reason):
            return "Failed to archive goal: \(reason)"
        case .restoreFailed(let reason):
            return "Failed to restore goal: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .cannotSave:
            return "Please fix validation errors and try again"
        case .validationFailed:
            return "Correct the highlighted fields and try again"
        case .archiveFailed, .restoreFailed:
            return "Try again or contact support if the issue persists"
        }
    }
}
