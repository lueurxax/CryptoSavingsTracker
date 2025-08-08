//
//  EditGoalView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData
import Foundation

struct EditGoalView: View {
    @StateObject private var viewModel: GoalEditViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingDeleteConfirmation = false
    @State private var showingArchiveConfirmation = false
    
    init(goal: Goal, modelContext: ModelContext) {
        self._viewModel = StateObject(wrappedValue: GoalEditViewModel(goal: goal, modelContext: modelContext))
    }
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Impact Preview (if changes detected)
                    if viewModel.showingImpactPreview {
                        VStack(spacing: 16) {
                            ImpactPreviewCard(
                                impact: viewModel.impactSummary,
                                currency: viewModel.goal.currency
                            )
                            .padding(.horizontal)
                            
                            Divider()
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // Form Content
                    VStack(spacing: 24) {
                        // Basic Information Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Basic Information", icon: "info.circle")
                            
                            VStack(spacing: 12) {
                                // Goal Name
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Goal Name")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    TextField("Enter goal name", text: $viewModel.goal.name)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel("Goal name")
                                        .accessibilityHint("Enter a descriptive name for your savings goal")
                                }
                                
                                // Target Amount
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Target Amount")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    HStack {
                                        Text(viewModel.goal.currency)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(AccessibleColors.lightBackground)
                                            .cornerRadius(6)
                                        
                                        TextField(
                                            "0.00",
                                            value: $viewModel.goal.targetAmount,
                                            format: .number.precision(.fractionLength(2))
                                        )
                                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                                        .keyboardType(.decimalPad)
#endif
                                        .accessibilityLabel("Target amount in \(viewModel.goal.currency)")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Timeline Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Timeline", icon: "calendar")
                            
                            VStack(spacing: 12) {
                                // Start Date
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Start Date")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Spacer()
                                        
                                        if !viewModel.goal.assets.isEmpty {
                                            HStack {
                                                Image(systemName: "info.circle.fill")
                                                    .foregroundColor(AccessibleColors.warning)
                                                    .font(.caption)
                                                Text("Has transactions")
                                                    .font(.caption2)
                                                    .foregroundColor(.accessibleSecondary)
                                            }
                                        }
                                    }
                                    
                                    DatePicker(
                                        "Start Date",
                                        selection: $viewModel.goal.startDate,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(.compact)
                                    .disabled(!viewModel.goal.assets.isEmpty)
                                    .accessibilityLabel("Goal start date")
                                    .accessibilityHint(!viewModel.goal.assets.isEmpty ? "Cannot change start date when transactions exist" : "Select when you want to start this goal")
                                }
                                
                                // Deadline
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Deadline")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    DatePicker(
                                        "Deadline",
                                        selection: $viewModel.goal.deadline,
                                        in: Date()...,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(.compact)
                                    .accessibilityLabel("Goal deadline")
                                    .accessibilityHint("Select when you want to complete this goal")
                                }
                                
                                // Days Remaining Display
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(.accessibleSecondary)
                                    Text("\(viewModel.goal.daysRemaining) days remaining")
                                        .font(.caption)
                                        .foregroundColor(.accessibleSecondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Reminders Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Reminders", icon: "bell")
                            
                            ReminderConfigurationView(
                                isEnabled: Binding(
                                    get: { viewModel.goal.isReminderEnabled },
                                    set: { newValue in
                                        if newValue && viewModel.goal.reminderTime == nil {
                                            viewModel.goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
                                        } else if !newValue {
                                            viewModel.goal.reminderFrequency = nil
                                            viewModel.goal.reminderTime = nil
                                            viewModel.goal.firstReminderDate = nil
                                        }
                                    }
                                ),
                                frequency: Binding(
                                    get: { viewModel.goal.frequency },
                                    set: { viewModel.goal.frequency = $0 }
                                ),
                                reminderTime: Binding(
                                    get: { viewModel.goal.reminderTime },
                                    set: { viewModel.goal.reminderTime = $0 }
                                ),
                                firstReminderDate: Binding(
                                    get: { viewModel.goal.firstReminderDate },
                                    set: { viewModel.goal.firstReminderDate = $0 }
                                ),
                                startDate: viewModel.goal.startDate,
                                deadline: viewModel.goal.deadline,
                                showAdvancedOptions: true
                            )
                        }
                        .padding(.horizontal)
                        
                        // Validation Errors
                        if viewModel.hasValidationErrors {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AccessibleColors.error)
                                    Text("Please fix the following issues:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(AccessibleColors.error)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(viewModel.validationErrors, id: \.self) { error in
                                        HStack {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(AccessibleColors.error)
                                                .font(.caption)
                                            Text(error)
                                                .font(.caption)
                                                .foregroundColor(AccessibleColors.error)
                                            Spacer()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Archive Section (if not archived)
                        if !viewModel.goal.isArchived {
                            VStack(spacing: 12) {
                                Divider()
                                
                                HStack {
                                    Text("Archive Goal")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Archive this goal to remove it from your active goals list. You can restore it anytime.")
                                        .font(.caption)
                                        .foregroundColor(.accessibleSecondary)
                                    
                                    Button("Archive Goal") {
                                        showingArchiveConfirmation = true
                                    }
                                    .foregroundColor(AccessibleColors.warning)
                                    .accessibilityLabel("Archive this goal")
                                    .accessibilityHint("Removes goal from active list but keeps all data")
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Spacing for bottom toolbar
                        if isCompact {
                            Spacer(minLength: 80)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Edit Goal")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if viewModel.isDirty {
                            viewModel.cancel()
                        }
                        dismiss()
                    }
                    .accessibilityLabel("Cancel editing")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                dismiss()
                            } catch {
                                // Handle error - could show alert
                                print("Save failed: \(error)")
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(viewModel.canSave ? .semibold : .regular)
                    .accessibilityLabel(viewModel.canSave ? "Save changes" : "Cannot save")
                    .accessibilityHint(viewModel.canSave ? "" : "Fix validation errors to enable saving")
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.isDirty {
                            viewModel.cancel()
                        }
                        dismiss()
                    }
                    .accessibilityLabel("Cancel editing")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                dismiss()
                            } catch {
                                // Handle error - could show alert
                                print("Save failed: \(error)")
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(viewModel.canSave ? .semibold : .regular)
                    .accessibilityLabel(viewModel.canSave ? "Save changes" : "Cannot save")
                    .accessibilityHint(viewModel.canSave ? "" : "Fix validation errors to enable saving")
                }
#endif
            }
        }
        .confirmationDialog(
            "Archive Goal",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task {
                    try? await viewModel.archiveGoal()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This goal will be moved to your archived goals. You can restore it anytime from the archived goals list.")
        }
    }
    
}

// MARK: - Supporting Views
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accessiblePrimary)
                .font(.title3)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(
        name: "Emergency Fund",
        currency: "USD", 
        targetAmount: 5000.0,
        deadline: Date().addingTimeInterval(86400 * 180) // 6 months
    )
    goal.reminderFrequency = ReminderFrequency.weekly.rawValue
    goal.reminderTime = Date()
    
    container.mainContext.insert(goal)
    
    return EditGoalView(goal: goal, modelContext: container.mainContext)
}