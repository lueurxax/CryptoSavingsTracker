// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalsSidebarView.swift

import SwiftUI
import SwiftData

private struct GoalsSidebarPreviewHost: View {
    private let container: ModelContainer
    private let goals: [Goal]
    @State private var selectedGoal: Goal?

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let previewContainer =
            (try? ModelContainer(
                for: Goal.self,
                Asset.self,
                Transaction.self,
                configurations: config
            )) ?? CryptoSavingsTrackerApp.previewModelContainer
        let firstGoal = Goal(
            name: "Bitcoin Savings",
            currency: "USD",
            targetAmount: 50_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let secondGoal = Goal(
            name: "Ethereum Fund",
            currency: "USD",
            targetAmount: 25_000,
            deadline: Date().addingTimeInterval(86_400 * 60)
        )
        previewContainer.mainContext.insert(firstGoal)
        previewContainer.mainContext.insert(secondGoal)
        container = previewContainer
        goals = [firstGoal, secondGoal]
        _selectedGoal = State(initialValue: firstGoal)
    }

    var body: some View {
        GoalsSidebarView(
            goals: goals,
            selectedGoal: $selectedGoal
        )
        .modelContainer(container)
    }
}

#Preview {
    GoalsSidebarPreviewHost()
}
