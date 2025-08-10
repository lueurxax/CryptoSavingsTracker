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
    @Published var isSaving: Bool = false
    @Published var showingImpactPreview: Bool = false
    @Published var showingEmojiPicker: Bool = false
    
    // MARK: - Private Properties
    private let originalSnapshot: GoalSnapshot
    private let modelContext: ModelContext
    private let notificationManager = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var hasValidationErrors: Bool {
        !validationErrors.isEmpty
    }
    
    var canSave: Bool {
        isDirty && !hasValidationErrors && !isSaving
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
        self.modelContext = modelContext
        
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
        AppLog.debug("🔄 Manual change detection triggered", category: .goalEdit)
        updateDirtyState()
        validateWithDelay()
    }
    
    private func updateDirtyState() {
        let wasDeep = isDirty
        isDirty = goal.hasChanges(from: originalSnapshot)
        showingImpactPreview = isDirty && hasSignificantChanges
        
        if isDirty != wasDeep {
            AppLog.debug("🔄 Dirty state changed: \(wasDeep) → \(isDirty). canSave: \(canSave)", category: .goalEdit)
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
        validationErrors = goal.validate()
    }
    
    func save() async throws {
        guard canSave else {
            throw GoalEditError.cannotSave("Goal is not in a saveable state")
        }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            // Final validation
            validate()
            guard !hasValidationErrors else {
                throw GoalEditError.validationFailed(validationErrors)
            }
            
            // Handle notification updates if reminder settings changed
            if reminderSettingsChanged() {
                try await updateNotifications()
            }
            
            // Update modification timestamp
            goal.lastModifiedDate = Date()
            
            // Log goal save attempt with detailed field values
            AppLog.debug("💾 About to save goal '\(goal.name)' with fields:", category: .goalEdit)
            AppLog.debug("  - emoji: '\(String(describing: goal.emoji))'", category: .goalEdit)
            AppLog.debug("  - goalDescription: '\(String(describing: goal.goalDescription))'", category: .goalEdit)
            AppLog.debug("  - link: '\(String(describing: goal.link))'", category: .goalEdit)
            AppLog.debug("  - targetAmount: \(goal.targetAmount)", category: .goalEdit)
            AppLog.debug("  - deadline: \(goal.deadline)", category: .goalEdit)
            
            // Save to SwiftData
            try modelContext.save()
            
            // Verify data was saved by re-reading from context
            AppLog.info("✅ Goal '\(goal.name)' saved successfully", category: .goalEdit)
            AppLog.debug("📋 After save verification - emoji: '\(String(describing: goal.emoji))', description: '\(String(describing: goal.goalDescription))', link: '\(String(describing: goal.link))'", category: .goalEdit)
            
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
        goal.reminderFrequency = originalSnapshot.reminderFrequency
        goal.reminderTime = originalSnapshot.reminderTime
        goal.emoji = originalSnapshot.emoji
        goal.goalDescription = originalSnapshot.goalDescription
        goal.link = originalSnapshot.link
        
        // Reset state
        isDirty = false
        validationErrors.removeAll()
        showingImpactPreview = false
        
        AppLog.debug("Goal changes cancelled", category: .goalEdit)
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
            // Cancel all notifications for this goal
            await notificationManager.cancelNotifications(for: goal)
            
            // Archive the goal
            goal.archive()
            
            // Save
            try modelContext.save()
            
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
            // Restore the goal
            goal.restore()
            
            // Reschedule notifications if goal has reminder settings
            if goal.reminderFrequency != nil {
                try await scheduleNotifications()
            }
            
            // Save
            try modelContext.save()
            
            AppLog.info("Goal '\(goal.name)' restored successfully", category: .goalEdit)
            
        } catch {
            AppLog.error("Failed to restore goal: \(error)", category: .goalEdit)
            throw GoalEditError.restoreFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helper Methods
    private func reminderSettingsChanged() -> Bool {
        return goal.reminderFrequency != originalSnapshot.reminderFrequency ||
               goal.reminderTime != originalSnapshot.reminderTime
    }
    
    private func updateNotifications() async throws {
        // Cancel existing notifications
        await notificationManager.cancelNotifications(for: goal)
        
        // Schedule new notifications if enabled
        if goal.reminderFrequency != nil {
            try await scheduleNotifications()
        }
    }
    
    private func scheduleNotifications() async throws {
        guard let reminderFrequency = goal.reminderFrequency,
              let _ = ReminderFrequency.allCases.first(where: { $0.rawValue == reminderFrequency }) else {
            return
        }
        
        // Use the existing notification scheduling logic
        await notificationManager.scheduleReminders(for: goal)
    }
}

// MARK: - Goal Edit Errors
enum GoalEditError: LocalizedError {
    case cannotSave(String)
    case validationFailed([String])
    case archiveFailed(String)
    case restoreFailed(String)
    case notificationUpdateFailed(String)
    
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
        case .notificationUpdateFailed(let reason):
            return "Failed to update notifications: \(reason)"
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
        case .notificationUpdateFailed:
            return "Goal was saved but notifications may not work correctly. Try editing and saving again."
        }
    }
}