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
    
    private var cancelButtonPlacement: ToolbarItemPlacement {
#if os(iOS)
        .navigationBarLeading
#else
        .cancellationAction
#endif
    }
    
    private var saveButtonPlacement: ToolbarItemPlacement {
#if os(iOS)
        .navigationBarTrailing
#else
        .primaryAction
#endif
    }
    
    var body: some View {
        NavigationStack {
            
            ScrollView {
                LazyVStack(spacing: 24, pinnedViews: []) {
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
                    
                    // Basic Information Section
                    FormSection(
                        title: "Basic Information",
                        icon: "info.circle"
                    ) {
                        // Goal Name
                        FormField(label: "Goal Name") {
                            TextField("Enter goal name", text: $viewModel.goal.name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Goal name")
                                .accessibilityHint("Enter a descriptive name for your savings goal")
                        }
                        
                        // Target Amount
                        FormField(label: "Target Amount") {
                            HStack(spacing: 12) {
                                Text(viewModel.goal.currency)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AccessibleColors.lightBackground)
                                    .cornerRadius(8)
                                    .font(.body.monospaced())
                                
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
                        
                    // Timeline Section
                    FormSection(
                        title: "Timeline",
                        icon: "calendar"
                    ) {
                        // Start Date
                        FormField(label: "Start Date") {
                            VStack(spacing: 8) {
                                if !viewModel.goal.assets.isEmpty {
                                    HStack {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(AccessibleColors.warning)
                                            .font(.caption)
                                        Text("Cannot change start date when transactions exist")
                                            .font(.caption)
                                            .foregroundColor(.accessibleSecondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(AccessibleColors.warning.opacity(0.1))
                                    .cornerRadius(6)
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
                        }
                        
                        // Deadline
                        FormField(label: "Target Date") {
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
                                .font(.callout)
                                .foregroundColor(.accessibleSecondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                        
                    // Reminders Section
                    FormSection(
                        title: "Reminders",
                        icon: "bell"
                    ) {
                        ReminderConfigurationView(
                            isEnabled: Binding(
                                get: { viewModel.goal.isReminderEnabled },
                                set: { newValue in
                                    print("🔔 EditGoalView: Setting reminder enabled to \(newValue)")
                                    if newValue {
                                        // Enable reminders
                                        if viewModel.goal.reminderFrequency == nil {
                                            viewModel.goal.reminderFrequency = ReminderFrequency.weekly.rawValue
                                            print("🔔 EditGoalView: Set reminderFrequency to weekly")
                                        }
                                        if viewModel.goal.reminderTime == nil {
                                            viewModel.goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
                                            print("🔔 EditGoalView: Set reminderTime to 9:00 AM")
                                        }
                                    } else {
                                        // Disable reminders
                                        viewModel.goal.reminderFrequency = nil
                                        viewModel.goal.reminderTime = nil
                                        viewModel.goal.firstReminderDate = nil
                                        print("🔔 EditGoalView: Disabled reminders, cleared all reminder data")
                                    }
                                    print("🔔 EditGoalView: isReminderEnabled is now \(viewModel.goal.isReminderEnabled)")
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
                        
                    // Validation Errors
                    if viewModel.hasValidationErrors {
                        ValidationErrorsView(errors: viewModel.validationErrors)
                    }
                    
                    // Archive Section (if not archived)
                    if !viewModel.goal.isArchived {
                        ArchiveSection(onArchive: { showingArchiveConfirmation = true })
                    }
                    
                    // Bottom padding for safe area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 16)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Goal")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: cancelButtonPlacement) {
                    Button("Cancel") {
                        if viewModel.isDirty {
                            viewModel.cancel()
                        }
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: saveButtonPlacement) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                dismiss()
                            } catch {
                                print("Save failed: \(error)")
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(viewModel.canSave ? .semibold : .regular)
                    .foregroundColor(viewModel.canSave ? .blue : .gray)
                }
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
struct FormSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accessiblePrimary)
                    .font(.title3)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Section Content
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(.vertical, 8)
    }
}

struct FormField<Content: View>: View {
    let label: String
    let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            content
        }
    }
}

struct ValidationErrorsView: View {
    let errors: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AccessibleColors.error)
                    .font(.title3)
                
                Text("Please fix the following issues:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AccessibleColors.error)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(errors, id: \.self) { error in
                    HStack(alignment: .top) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(AccessibleColors.error)
                            .font(.caption)
                            .padding(.top, 2)
                        
                        Text(error)
                            .font(.callout)
                            .foregroundColor(AccessibleColors.error)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(AccessibleColors.error.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ArchiveSection: View {
    let onArchive: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "archivebox")
                    .foregroundColor(AccessibleColors.warning)
                    .font(.title3)
                
                Text("Archive Goal")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            Text("Archive this goal to remove it from your active goals list. You can restore it anytime from the archived goals section.")
                .font(.callout)
                .foregroundColor(.accessibleSecondary)
                .multilineTextAlignment(.leading)
            
            Button("Archive Goal") {
                onArchive()
            }
            .foregroundColor(AccessibleColors.warning)
            .font(.callout.weight(.medium))
            .accessibilityLabel("Archive this goal")
            .accessibilityHint("Removes goal from active list but keeps all data")
        }
        .padding(16)
        .background(AccessibleColors.warning.opacity(0.1))
        .cornerRadius(12)
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