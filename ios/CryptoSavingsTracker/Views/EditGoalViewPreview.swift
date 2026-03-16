// Extracted preview-only declarations for NAV003 policy compliance.
// Source: EditGoalView.swift

import SwiftUI
import SwiftData
import Foundation

private func makeEditGoalPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return (try? ModelContainer(for: Goal.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer
}

private func makeEditGoalPreviewGoal(in container: ModelContainer) -> Goal {
    let goal = Goal(
        name: "Emergency Fund",
        currency: "USD",
        targetAmount: 5000.0,
        deadline: Date().addingTimeInterval(86400 * 180)
    )
    goal.reminderFrequency = ReminderFrequency.weekly.rawValue
    goal.reminderTime = Date()
    container.mainContext.insert(goal)
    return goal
}

#Preview("Edit Goal Default") {
    let container = makeEditGoalPreviewContainer()
    let goal = makeEditGoalPreviewGoal(in: container)

    return EditGoalView(goal: goal, modelContext: container.mainContext)
}

#Preview("Edit Goal Invalid") {
    let container = makeEditGoalPreviewContainer()
    let goal = makeEditGoalPreviewGoal(in: container)

    return EditGoalView(
        goal: goal,
        modelContext: container.mainContext,
        previewState: .init(
            goalName: "",
            targetAmount: 0,
            hasAttemptedSubmit: true
        )
    )
}

#Preview("Edit Goal Save Error") {
    let container = makeEditGoalPreviewContainer()
    let goal = makeEditGoalPreviewGoal(in: container)

    return EditGoalView(
        goal: goal,
        modelContext: container.mainContext,
        previewState: .init(
            saveErrorMessage: "Unable to save this goal right now. Please try again."
        )
    )
}

// MARK: - Customization Section
struct CustomizationSection: View {
    @ObservedObject var viewModel: GoalEditViewModel
    
    var body: some View {
        FormSection(
            title: "Customization",
            icon: "paintbrush"
        ) {
            // Emoji Picker
            FormField(label: "Goal Icon") {
                EmojiPickerField(viewModel: viewModel)
            }
            // NAV-MOD: MOD-01
            .popover(isPresented: $viewModel.showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $viewModel.goal.emoji)
                    .frame(width: 320, height: 400)
                    .onChange(of: viewModel.goal.emoji) { _, _ in
                        viewModel.triggerChangeDetection()
                    }
            }
            
            // Description Field
            FormField(label: "Description (Optional)") {
                DescriptionField(viewModel: viewModel)
            }
            
            // Link Field
            FormField(label: "Link (Optional)") {
                LinkField(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Emoji Picker Field
struct EmojiPickerField: View {
    @ObservedObject var viewModel: GoalEditViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Current emoji or placeholder
            Button(action: {
                viewModel.showingEmojiPicker.toggle()
            }) {
                if let emoji = viewModel.goal.emoji {
                    Text(emoji)
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                } else {
                    Image(systemName: "face.smiling")
                        .font(.largeTitle)
                        .foregroundColor(.accessibleSecondary)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap to select emoji")
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
                
                if let suggestion = Goal.suggestEmoji(for: viewModel.goal.name) {
                    Button(action: {
                        viewModel.goal.emoji = suggestion
                        viewModel.triggerChangeDetection()
                    }) {
                        HStack(spacing: 4) {
                            Text("Suggestion:")
                                .font(.caption2)
                            Text(suggestion)
                                .font(.body)
                        }
                        .foregroundColor(.accessiblePrimary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            if viewModel.goal.emoji != nil {
                Button(action: {
                    viewModel.goal.emoji = nil
                    viewModel.triggerChangeDetection()
                }) {
                    Text("Clear")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Description Field
struct DescriptionField: View {
    @ObservedObject var viewModel: GoalEditViewModel
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: Binding(
                get: { viewModel.goal.goalDescription ?? "" },
                set: { viewModel.goal.goalDescription = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 60, maxHeight: 120)
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: viewModel.goal.goalDescription ?? "") { _, newValue in
                if newValue.count > 140 {
                    viewModel.goal.goalDescription = String(newValue.prefix(140))
                }
                viewModel.triggerChangeDetection()
            }
            
            Text("\((viewModel.goal.goalDescription ?? "").count)/140")
                .font(.caption2)
                .foregroundColor(.accessibleSecondary)
        }
    }
}

// MARK: - Link Field
struct LinkField: View {
    @ObservedObject var viewModel: GoalEditViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.accessibleSecondary)
                
                TextField("https://example.com", text: Binding(
                    get: { viewModel.goal.link ?? "" },
                    set: { viewModel.goal.link = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
#if os(iOS)
                .autocapitalization(.none)
#endif
                .disableAutocorrection(true)
                .onChange(of: viewModel.goal.link ?? "") { _, _ in
                    viewModel.triggerChangeDetection()
                }
            }
            
            if let link = viewModel.goal.link, !link.isEmpty {
                URLValidationView(link: link, isValid: viewModel.isValidURL(link))
            }
            
            Text("Add a link to the product or service you're saving for")
                .font(.caption2)
                .foregroundColor(.accessibleSecondary)
        }
    }
}

// MARK: - URL Validation View
struct URLValidationView: View {
    let link: String
    let isValid: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isValid ? AccessibleColors.success : AccessibleColors.warning)
                .font(.caption)
            Text(isValid ? "Valid URL" : "Please enter a valid URL")
                .font(.caption)
                .foregroundColor(isValid ? AccessibleColors.success : AccessibleColors.warning)
            Spacer()
        }
    }
}
