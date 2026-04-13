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
    @State private var showingDiscardConfirmation = false
    @State private var hasStartedTelemetryFlow = false
    @State private var hasAttemptedSubmit = false
    @State private var saveErrorMessage: String?
    @State private var accessErrorMessage: String?
    @FocusState private var focusedField: GoalValidationField?

    struct PreviewState {
        var goalName: String? = nil
        var targetAmount: Double? = nil
        var deadline: Date? = nil
        var startDate: Date? = nil
        var hasAttemptedSubmit: Bool = false
        var saveErrorMessage: String? = nil
    }
    
    init(goal: Goal, modelContext: ModelContext, previewState: PreviewState = PreviewState()) {
        if let goalName = previewState.goalName {
            goal.name = goalName
        }
        if let targetAmount = previewState.targetAmount {
            goal.targetAmount = targetAmount
        }
        if let deadline = previewState.deadline {
            goal.deadline = deadline
        }
        if let startDate = previewState.startDate {
            goal.startDate = startDate
        }

        self._viewModel = StateObject(wrappedValue: GoalEditViewModel(goal: goal, modelContext: modelContext))
        self._hasAttemptedSubmit = State(initialValue: previewState.hasAttemptedSubmit)
        self._saveErrorMessage = State(initialValue: previewState.saveErrorMessage)
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

    private var goalNameBinding: Binding<String> {
        Binding(
            get: { viewModel.goal.name },
            set: { newValue in
                viewModel.goal.name = newValue
                handleFormChange()
            }
        )
    }

    private var targetAmountBinding: Binding<Double> {
        Binding(
            get: { viewModel.goal.targetAmount },
            set: { newValue in
                viewModel.goal.targetAmount = newValue
                handleFormChange()
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.goal.startDate },
            set: { newValue in
                viewModel.goal.startDate = newValue
                handleFormChange()
            }
        )
    }

    private var deadlineBinding: Binding<Date> {
        Binding(
            get: { viewModel.goal.deadline },
            set: { newValue in
                viewModel.goal.deadline = newValue
                handleFormChange()
            }
        )
    }

    private var shouldShowValidationFeedback: Bool {
        hasAttemptedSubmit || viewModel.hasValidationErrors
    }

    private var focusedFieldIdentifier: String? {
        focusedField?.rawValue
    }
    
    var body: some View {
        Group {
            if let accessErrorMessage {
                NavigationStack {
                    ContentUnavailableView(
                        "Read-Only Shared Goal",
                        systemImage: "hand.raised.fill",
                        description: Text(accessErrorMessage)
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", action: dismiss.callAsFunction)
                        }
                    }
                }
            } else {
        NavigationStack {
            ScrollViewReader { scrollProxy in
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
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Enter goal name", text: goalNameBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Goal name")
                                    .accessibilityHint("Enter a descriptive name for your savings goal")
                                    .focused($focusedField, equals: .name)

                                if shouldShowValidationFeedback, let error = viewModel.fieldErrors[.name] {
                                    GoalFormInlineError(message: error)
                                }
                            }
                            .id(GoalValidationField.name)
                        }
                        
                        // Target Amount
                        FormField(label: "Target Amount") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    Text(viewModel.goal.currency)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AccessibleColors.lightBackground)
                                        .cornerRadius(8)
                                        .font(.body.monospaced())
                                    
                                    TextField(
                                        "0.00",
                                        value: targetAmountBinding,
                                        format: .number.precision(.fractionLength(2))
                                    )
                                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                                    .keyboardType(.decimalPad)
#endif
                                    .accessibilityLabel("Target amount in \(viewModel.goal.currency)")
                                    .focused($focusedField, equals: .targetAmount)
                                }

                                if shouldShowValidationFeedback, let error = viewModel.fieldErrors[.targetAmount] {
                                    GoalFormInlineError(message: error)
                                }
                            }
                            .id(GoalValidationField.targetAmount)
                        }
                    }
                    
                    // Visual & Metadata Section
                    CustomizationSection(viewModel: viewModel)
                        
                    // Timeline Section
                    FormSection(
                        title: "Timeline",
                        icon: "calendar"
                    ) {
                        // Start Date
                        FormField(label: "Start Date") {
                            VStack(spacing: 8) {
                                if !viewModel.goal.allocatedAssets.isEmpty {
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
                                    selection: startDateBinding,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .disabled(!viewModel.goal.allocatedAssets.isEmpty)
                                .accessibilityLabel("Goal start date")
                                .accessibilityHint(!viewModel.goal.allocatedAssets.isEmpty ? "Cannot change start date when transactions exist" : "Select when you want to start this goal")

                                if shouldShowValidationFeedback, let error = viewModel.fieldErrors[.startDate] {
                                    GoalFormInlineError(message: error)
                                }
                            }
                            .id(GoalValidationField.startDate)
                        }
                        
                        // Deadline
                        FormField(label: "Target Date") {
                            VStack(alignment: .leading, spacing: 6) {
                                DatePicker(
                                    "Deadline",
                                    selection: deadlineBinding,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .accessibilityLabel("Goal deadline")
                                .accessibilityHint("Select when you want to complete this goal")

                                if shouldShowValidationFeedback, let error = viewModel.fieldErrors[.deadline] {
                                    GoalFormInlineError(message: error)
                                }
                            }
                            .id(GoalValidationField.deadline)
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
                            DIContainer.shared.navigationTelemetryTracker.cancelled(
                                journeyID: NavigationJourney.goalCreateEdit,
                                isDirty: true,
                                cancelStage: "toolbar_cancel"
                            )
                            showingDiscardConfirmation = true
                            return
                        }
                        if viewModel.isDirty {
                            viewModel.cancel()
                        }
                        DIContainer.shared.navigationTelemetryTracker.cancelled(
                            journeyID: NavigationJourney.goalCreateEdit,
                            isDirty: viewModel.isDirty,
                            cancelStage: "toolbar_cancel"
                        )
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }

#if !os(iOS)
                ToolbarItem(placement: saveButtonPlacement) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                                    journeyID: NavigationJourney.goalCreateEdit,
                                    result: "saved"
                                )
                                dismiss()
                            } catch {
                                DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                                    journeyID: NavigationJourney.goalCreateEdit,
                                    recoveryPath: "save_error",
                                    success: false
                                )
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(viewModel.canSave ? .semibold : .regular)
                    .foregroundColor(viewModel.canSave ? .blue : .gray)
                }
#endif
                }
#if os(iOS)
                .safeAreaInset(edge: .bottom) {
                    GoalFormBottomActionBar(
                        validationIssues: shouldShowValidationFeedback ? viewModel.validationErrors : [],
                        saveErrorMessage: saveErrorMessage,
                        isSaving: viewModel.isSaving,
                        primaryButtonTitle: saveErrorMessage == nil ? "Save Changes" : "Retry Save",
                        primaryButtonIdentifier: "saveGoalChangesButton",
                        focusedFieldIdentifier: focusedFieldIdentifier,
                        onRetry: saveErrorMessage == nil ? nil : { Task { await attemptSave(using: scrollProxy) } },
                        onPrimaryAction: { Task { await attemptSave(using: scrollProxy) } }
                    )
                }
#endif
            }
        }
        .overlay(alignment: .topLeading) {
            GoalFormUITestHooks(focusedFieldIdentifier: focusedFieldIdentifier)
        }
        .interactiveDismissDisabled(viewModel.isDirty)
        .onAppear {
            validateWritableContext()
            guard !hasStartedTelemetryFlow else { return }
            hasStartedTelemetryFlow = true
            DIContainer.shared.navigationTelemetryTracker.flowStarted(
                journeyID: NavigationJourney.goalCreateEdit,
                entryPoint: "edit_goal_sheet"
            )
        }
        // NAV-MOD: MOD-02
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                DIContainer.shared.navigationTelemetryTracker.discardConfirmed(
                    journeyID: NavigationJourney.goalCreateEdit,
                    formType: "goal_edit"
                )
                viewModel.cancel()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Unsaved goal changes will be lost.")
        }
        // NAV-MOD: MOD-04
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
    }

    private func validateWritableContext() {
        do {
            try DIContainer.shared.familyShareAccessGuard.assertOwnerWritable(goal: viewModel.goal)
        } catch {
            accessErrorMessage = error.localizedDescription
        }
    }

    private func handleFormChange() {
        saveErrorMessage = nil
        viewModel.triggerChangeDetection()
    }

    @MainActor
    private func attemptSave(using scrollProxy: ScrollViewProxy) async {
        hasAttemptedSubmit = true
        saveErrorMessage = nil
        viewModel.validate()

        if viewModel.hasValidationErrors {
            focusFirstInvalidField(using: scrollProxy)
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "validation_error",
                success: false
            )
            return
        }

        if !viewModel.isDirty {
            dismiss()
            return
        }

        do {
            try await viewModel.save()
            DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                result: "saved"
            )
            dismiss()
        } catch GoalEditError.validationFailed {
            focusFirstInvalidField(using: scrollProxy)
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "validation_error",
                success: false
            )
        } catch {
            saveErrorMessage = "Unable to save this goal right now. Please try again."
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "save_error",
                success: false
            )
        }
    }

    private func focusFirstInvalidField(using scrollProxy: ScrollViewProxy) {
        guard let firstInvalidField = viewModel.firstInvalidField else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo(firstInvalidField, anchor: .center)
        }

        switch firstInvalidField {
        case .name:
            focusedField = .name
        case .targetAmount:
            focusedField = .targetAmount
        case .deadline, .startDate:
            focusedField = nil
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
