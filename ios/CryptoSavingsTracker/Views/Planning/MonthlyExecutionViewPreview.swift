import SwiftUI
import SwiftData

private struct MonthlyExecutionPreviewHost: View {
    let container: ModelContainer

    var body: some View {
        NavigationStack {
            MonthlyPlanningContainer()
        }
        .modelContainer(container)
    }
}

private func makeMonthlyExecutionPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        MonthlyPlan.self,
        MonthlyExecutionRecord.self,
        ExecutionSnapshot.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.previewModelContainer

    let context = container.mainContext
    let currentMonth = MonthlyExecutionRecord.monthLabel(from: Date())

    let piano = Goal(
        name: "Piano for daughter",
        currency: "USD",
        targetAmount: 500,
        deadline: Calendar.current.date(byAdding: .day, value: 29, to: Date()) ?? Date()
    )
    let birthday = Goal(
        name: "Afina's birthday party",
        currency: "USD",
        targetAmount: 1000,
        deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    )

    let pianoPlan = MonthlyPlan(
        goalId: piano.id,
        monthLabel: currentMonth,
        requiredMonthly: 280,
        remainingAmount: 500,
        monthsRemaining: 2,
        currency: "USD",
        status: .onTrack,
        flexState: .flexible,
        state: .executing
    )
    let birthdayPlan = MonthlyPlan(
        goalId: birthday.id,
        monthLabel: currentMonth,
        requiredMonthly: 500,
        remainingAmount: 1000,
        monthsRemaining: 2,
        currency: "USD",
        status: .onTrack,
        flexState: .flexible,
        state: .executing
    )

    let record = MonthlyExecutionRecord(monthLabel: currentMonth, goalIds: [piano.id, birthday.id])
    record.startTracking()
    let snapshot = ExecutionSnapshot.create(from: [pianoPlan, birthdayPlan], goals: [piano, birthday])
    snapshot.executionRecord = record
    record.snapshot = snapshot
    pianoPlan.executionRecord = record
    birthdayPlan.executionRecord = record

    context.insert(piano)
    context.insert(birthday)
    context.insert(pianoPlan)
    context.insert(birthdayPlan)
    context.insert(record)
    context.insert(snapshot)
    try? context.save()

    return container
}

#Preview("Monthly Execution Light") {
    MonthlyExecutionPreviewHost(container: makeMonthlyExecutionPreviewContainer())
}

#Preview("Monthly Execution Dark") {
    MonthlyExecutionPreviewHost(container: makeMonthlyExecutionPreviewContainer())
        .preferredColorScheme(.dark)
}
