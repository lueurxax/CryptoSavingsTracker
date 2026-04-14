import SwiftUI
import SwiftData
import Foundation

private enum AppStoreScreenshotFrame {
    static let iPhone65 = CGSize(width: 414, height: 896)
    static let iPad13 = CGSize(width: 1032, height: 1376)
}

private struct AppStorePreviewScenario {
    let container: ModelContainer
    let primaryGoal: Goal
    let secondaryGoal: Goal
    let spendingAsset: Asset
}

private enum AppStoreScreenshotSeed {
    static func makeScenario() -> AppStorePreviewScenario {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = (try? ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            AssetAllocation.self,
            configurations: config
        )) ?? CryptoSavingsTrackerApp.previewModelContainer

        let calendar = Calendar.current
        let primaryGoal = Goal(
            name: "Emergency Fund",
            currency: "USD",
            targetAmount: 15000,
            deadline: calendar.date(byAdding: .month, value: 8, to: Date()) ?? Date().addingTimeInterval(86400 * 240),
            emoji: "🛟",
            description: "Build a stable cash reserve for the unexpected."
        )
        let secondaryGoal = Goal(
            name: "Summer Trip",
            currency: "USD",
            targetAmount: 4500,
            deadline: calendar.date(byAdding: .month, value: 4, to: Date()) ?? Date().addingTimeInterval(86400 * 120),
            emoji: "✈️",
            description: "Save for flights, hotel, and spending money."
        )

        let usdAsset = Asset(currency: "USD")
        let btcAsset = Asset(currency: "BTC")

        let salaryDeposit = Transaction(
            amount: 5400,
            asset: usdAsset,
            date: calendar.date(byAdding: .day, value: -12, to: Date()) ?? Date(),
            comment: "Savings transfer"
        )
        let bonusDeposit = Transaction(
            amount: 1800,
            asset: usdAsset,
            date: calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            comment: "Monthly top-up"
        )
        let btcTopUp = Transaction(
            amount: 0.18,
            asset: btcAsset,
            date: calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date(),
            comment: "BTC allocation"
        )

        let primaryAllocation = AssetAllocation(asset: usdAsset, goal: primaryGoal, amount: 7200)
        let secondaryAllocation = AssetAllocation(asset: btcAsset, goal: secondaryGoal, amount: 0.18)

        container.mainContext.insert(primaryGoal)
        container.mainContext.insert(secondaryGoal)
        container.mainContext.insert(usdAsset)
        container.mainContext.insert(btcAsset)
        container.mainContext.insert(salaryDeposit)
        container.mainContext.insert(bonusDeposit)
        container.mainContext.insert(btcTopUp)
        container.mainContext.insert(primaryAllocation)
        container.mainContext.insert(secondaryAllocation)

        return AppStorePreviewScenario(
            container: container,
            primaryGoal: primaryGoal,
            secondaryGoal: secondaryGoal,
            spendingAsset: usdAsset
        )
    }
}

private func makeGoalsListPreview() -> some View {
    let scenario = AppStoreScreenshotSeed.makeScenario()
    return NavigationStack {
        GoalsListView()
    }
    .modelContainer(scenario.container)
    .preferredColorScheme(.light)
}

private func makeDashboardPreview() -> some View {
    let scenario = AppStoreScreenshotSeed.makeScenario()
    return NavigationStack {
        DashboardView()
    }
    .modelContainer(scenario.container)
    .preferredColorScheme(.light)
}

private func makeGoalDetailPreview() -> some View {
    let scenario = AppStoreScreenshotSeed.makeScenario()
    return NavigationStack {
        GoalDetailView(goal: scenario.primaryGoal)
    }
    .modelContainer(scenario.container)
    .preferredColorScheme(.light)
}

private func makeAddGoalPreview() -> some View {
    AddGoalView(
        previewState: .init(
            name: "Home Office Upgrade",
            currency: "USD",
            targetAmount: "3200"
        )
    )
    .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
    .preferredColorScheme(.light)
}

private func makeSettingsPreview() -> some View {
    SettingsView()
        .preferredColorScheme(.light)
}

private extension View {
    func appStoreScreenshotFrame(_ size: CGSize) -> some View {
        self
            .frame(width: size.width, height: size.height)
            .background(Color(.systemGroupedBackground))
            .clipped()
    }
}

#Preview("iPhone 6.5 Goals") {
    makeGoalsListPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPhone65)
}

#Preview("iPhone 6.5 Dashboard") {
    makeDashboardPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPhone65)
}

#Preview("iPhone 6.5 Goal Detail") {
    makeGoalDetailPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPhone65)
}

#Preview("iPhone 6.5 Add Goal") {
    makeAddGoalPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPhone65)
}

#Preview("iPhone 6.5 Settings") {
    makeSettingsPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPhone65)
}

#Preview("iPad 13 Goals") {
    makeGoalsListPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPad13)
}

#Preview("iPad 13 Dashboard") {
    makeDashboardPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPad13)
}

#Preview("iPad 13 Goal Detail") {
    makeGoalDetailPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPad13)
}

#Preview("iPad 13 Add Goal") {
    makeAddGoalPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPad13)
}

#Preview("iPad 13 Settings") {
    makeSettingsPreview()
        .appStoreScreenshotFrame(AppStoreScreenshotFrame.iPad13)
}
