//
//  PersistenceMutationServices.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 16/03/2026.
//

import Foundation
import SwiftData

@MainActor
final class GoalMutationService: GoalMutationServiceProtocol {
    private let modelContext: ModelContext
    private let notificationManager: NotificationManager
    private let accessGuard: FamilyShareAccessChecking

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManager? = nil,
        accessGuard: FamilyShareAccessChecking
    ) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager ?? .shared
        self.accessGuard = accessGuard
    }

    func createGoal(_ goal: Goal) async throws {
        try await persist(goal, insertIfNeeded: true)
        if goal.reminderFrequency != nil {
            await notificationManager.scheduleReminders(for: goal)
        }
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func saveGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        try await persist(goal, insertIfNeeded: true)
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func archiveGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        await notificationManager.cancelNotifications(for: goal)
        goal.archive()
        try saveContext(operation: "Unable to archive goal")
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func restoreGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        goal.restore()
        try saveContext(operation: "Unable to restore goal")
        if goal.reminderFrequency != nil {
            await notificationManager.scheduleReminders(for: goal)
        }
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func resumeGoal(_ goal: Goal) throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        goal.restoreToActive()
        try saveContext(operation: "Unable to resume goal")
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    private func postSharedGoalDataDidChange(goalIDs: [UUID]) {
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": goalIDs,
                "reason": "goalMutation"
            ]
        )
    }

    private func persist(_ goal: Goal, insertIfNeeded: Bool) async throws {
        let shouldInsert = insertIfNeeded && goal.modelContext == nil
        if shouldInsert {
            modelContext.insert(goal)
        }

        do {
            try modelContext.save()
        } catch {
            if shouldInsert {
                modelContext.delete(goal)
            }
            throw PersistenceMutationError.saveFailed("Unable to save goal", underlying: error)
        }
    }

    private func saveContext(operation: String) throws {
        do {
            try modelContext.save()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }
}

@MainActor
final class AssetMutationService: AssetMutationServiceProtocol {
    private let modelContext: ModelContext
    private let allocationService: AllocationService
    private let accessGuard: FamilyShareAccessChecking

    init(modelContext: ModelContext, accessGuard: FamilyShareAccessChecking) {
        self.modelContext = modelContext
        self.allocationService = AllocationService(modelContext: modelContext)
        self.accessGuard = accessGuard
    }

    @discardableResult
    func createAsset(
        currency: String,
        address: String?,
        chainId: String?,
        goal: Goal
    ) async throws -> Asset {
        try accessGuard.assertOwnerWritable(goal: goal)
        let newAsset = Asset(
            currency: currency,
            address: address,
            chainId: chainId
        )
        let allocation = AssetAllocation(asset: newAsset, goal: goal, amount: newAsset.currentAmount)
        let history = AllocationHistory(asset: newAsset, goal: goal, amount: allocation.amountValue)

        modelContext.insert(newAsset)
        modelContext.insert(allocation)
        modelContext.insert(history)

        if !(goal.allocations ?? []).contains(where: { $0.id == allocation.id }) {
            goal.allocations = (goal.allocations ?? []) + [allocation]
        }
        if !(newAsset.allocations ?? []).contains(where: { $0.id == allocation.id }) {
            newAsset.allocations = (newAsset.allocations ?? []) + [allocation]
        }

        do {
            try modelContext.save()
            postAssetSharedGoalDataDidChange(asset: newAsset, goalIDs: [goal.id])
            return newAsset
        } catch {
            modelContext.delete(history)
            modelContext.delete(allocation)
            modelContext.delete(newAsset)
            throw PersistenceMutationError.saveFailed("Unable to save asset", underlying: error)
        }
    }

    func allocateAllUnallocated(of asset: Asset, to goal: Goal, bestKnownBalance: Double) throws {
        try accessGuard.assertOwnerWritable(asset: asset)
        try accessGuard.assertOwnerWritable(goal: goal)
        let remaining = max(0, bestKnownBalance - asset.totalAllocatedAmount)
        guard remaining > 0.0000001 else { return }

        var newAllocations: [(goal: Goal, amount: Double)] = []
        newAllocations.reserveCapacity((asset.allocations ?? []).count + 1)

        var goalHandled = false
        for allocation in (asset.allocations ?? []) {
            guard let existingGoal = allocation.goal else { continue }
            if existingGoal.id == goal.id {
                newAllocations.append((goal: goal, amount: allocation.amountValue + remaining))
                goalHandled = true
            } else {
                newAllocations.append((goal: existingGoal, amount: allocation.amountValue))
            }
        }

        if !goalHandled {
            newAllocations.append((goal: goal, amount: remaining))
        }

        do {
            try allocationService.updateAllocations(for: asset, newAllocations: newAllocations)
        } catch {
            throw PersistenceMutationError.saveFailed("Unable to update asset allocations", underlying: error)
        }
    }

    func deleteAsset(_ asset: Asset) throws {
        try accessGuard.assertOwnerWritable(asset: asset)
        let goalIDs = (asset.allocations ?? []).compactMap { $0.goal?.id }
        modelContext.delete(asset)
        try saveContext(operation: "Unable to delete asset")
        postAssetSharedGoalDataDidChange(asset: asset, goalIDs: goalIDs)
    }

    func deleteAssets(_ assets: [Asset]) throws {
        for asset in assets {
            try accessGuard.assertOwnerWritable(asset: asset)
        }
        let goalIDs = assets.flatMap { ($0.allocations ?? []).compactMap { $0.goal?.id } }
        for asset in assets {
            modelContext.delete(asset)
        }
        try saveContext(operation: "Unable to delete assets")
        if !goalIDs.isEmpty {
            NotificationCenter.default.post(
                name: .sharedGoalDataDidChange,
                object: nil,
                userInfo: [
                    "affectedGoalIDs": goalIDs,
                    "reason": "assetMutation"
                ]
            )
        }
    }

    private func postAssetSharedGoalDataDidChange(asset: Asset, goalIDs: [UUID]) {
        let ids = goalIDs.isEmpty
            ? (asset.allocations ?? []).compactMap { $0.goal?.id }
            : goalIDs
        guard !ids.isEmpty else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": ids,
                "reason": "assetMutation"
            ]
        )
    }

    private func saveContext(operation: String) throws {
        do {
            try modelContext.save()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }
}

@MainActor
final class TransactionMutationService: TransactionMutationServiceProtocol {
    private let modelContext: ModelContext
    private let accessGuard: FamilyShareAccessChecking

    init(modelContext: ModelContext, accessGuard: FamilyShareAccessChecking) {
        self.modelContext = modelContext
        self.accessGuard = accessGuard
    }

    @discardableResult
    func createTransaction(
        for asset: Asset,
        amount: Double,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        try accessGuard.assertOwnerWritable(asset: asset)
        if let autoAllocateGoalId {
            try accessGuard.assertOwnerWritable(goalID: autoAllocateGoalId)
        }
        let epsilon = 0.0000001
        let preBalance = asset.currentAmount
        let preIsFullyAllocated = asset.isFullyAllocated
        let preWasDedicatedToSingleGoal = (asset.allocations ?? []).count == 1
        let singleAllocation = (asset.allocations ?? []).first

        let newTransaction = Transaction(amount: amount, asset: asset, comment: comment)
        asset.transactions = (asset.transactions ?? []) + [newTransaction]
        modelContext.insert(newTransaction)

        if let autoAllocateGoalId {
            try applyContributionAllocation(
                goalId: autoAllocateGoalId,
                asset: asset,
                depositAmount: amount,
                timestamp: newTransaction.date
            )
        } else if preIsFullyAllocated,
                  preWasDedicatedToSingleGoal,
                  let allocation = singleAllocation,
                  let goal = allocation.goal {
            let newTarget = max(0, preBalance + amount)
            if abs(newTarget - allocation.amountValue) > epsilon {
                allocation.updateAmount(newTarget)
                modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newTarget, timestamp: newTransaction.date))
            }
        }

        do {
            try modelContext.save()
        } catch {
            asset.transactions = (asset.transactions ?? []).filter { $0.id != newTransaction.id }
            modelContext.delete(newTransaction)
            throw PersistenceMutationError.saveFailed("Unable to save transaction", underlying: error)
        }

        let affectedGoalIDs = (asset.allocations ?? []).compactMap { $0.goal?.id }

        NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalIds": affectedGoalIDs
            ]
        )
        if !affectedGoalIDs.isEmpty {
            NotificationCenter.default.post(
                name: .sharedGoalDataDidChange,
                object: nil,
                userInfo: [
                    "affectedGoalIDs": affectedGoalIDs,
                    "reason": "transactionMutation"
                ]
            )
        }

        return newTransaction
    }

    func deleteTransaction(_ transaction: Transaction) throws {
        try accessGuard.assertOwnerWritable(transaction: transaction)
        let asset = transaction.asset
        let affectedGoalIDs = (asset?.allocations ?? []).compactMap { $0.goal?.id }
        modelContext.delete(transaction)
        try saveContext(operation: "Unable to delete transaction")

        NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
        if !affectedGoalIDs.isEmpty {
            NotificationCenter.default.post(
                name: .sharedGoalDataDidChange,
                object: nil,
                userInfo: [
                    "affectedGoalIDs": affectedGoalIDs,
                    "reason": "transactionMutation"
                ]
            )
        }
        if let asset {
            NotificationCenter.default.post(
                name: .monthlyPlanningAssetUpdated,
                object: asset,
                userInfo: [
                    "assetId": asset.id,
                    "goalIds": (asset.allocations ?? []).compactMap { $0.goal?.id }
                ]
            )
        }
    }

    private func applyContributionAllocation(
        goalId: UUID,
        asset: Asset,
        depositAmount: Double,
        timestamp: Date
    ) throws {
        try accessGuard.assertOwnerWritable(asset: asset)
        try accessGuard.assertOwnerWritable(goalID: goalId)
        guard depositAmount > 0.0000001 else { return }

        if let allocation = (asset.allocations ?? []).first(where: { $0.goal?.id == goalId }),
           let goal = allocation.goal {
            let newTarget = max(0, allocation.amountValue + depositAmount)
            allocation.updateAmount(newTarget)
            modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newTarget, timestamp: timestamp))
            return
        }

        let predicate = #Predicate<Goal> { goal in
            goal.id == goalId
        }
        guard let goal = try modelContext.fetch(FetchDescriptor<Goal>(predicate: predicate)).first else {
            throw PersistenceMutationError.objectNotFound("Goal for contribution allocation was not found.")
        }

        let allocation = AssetAllocation(asset: asset, goal: goal, amount: depositAmount)
        modelContext.insert(allocation)
        modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: depositAmount, timestamp: timestamp))
    }

    private func saveContext(operation: String) throws {
        do {
            try modelContext.save()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }
}

@MainActor
final class PlanningMutationService: PlanningMutationServiceProtocol {
    private let modelContext: ModelContext
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let accessGuard: FamilyShareAccessChecking

    init(modelContext: ModelContext, exchangeRateService: ExchangeRateServiceProtocol, accessGuard: FamilyShareAccessChecking) {
        self.modelContext = modelContext
        self.exchangeRateService = exchangeRateService
        self.accessGuard = accessGuard
    }

    func markPlanCompleted(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        plan.state = .completed
        plan.isSkipped = false
        try saveContext(operation: "Unable to mark plan completed")
    }

    func markPlanSkipped(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        plan.isSkipped = true
        plan.state = .completed
        try saveContext(operation: "Unable to skip plan")
    }

    func deletePlan(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        modelContext.delete(plan)
        try saveContext(operation: "Unable to delete plan")
    }

    func preparePlansForExecution(_ plans: [MonthlyPlan]) throws {
        try accessGuard.assertOwnerWritable(plans: plans)
        var didChange = false
        for plan in plans where plan.state != .draft {
            plan.state = .draft
            didChange = true
        }

        for plan in plans where !plan.isSkipped && plan.effectiveAmount <= 0 {
            plan.isSkipped = true
            didChange = true
        }

        if didChange {
            try saveContext(operation: "Unable to prepare plans for execution")
        }
    }

    func resetPlansToDraft(_ plans: [MonthlyPlan]) throws {
        try accessGuard.assertOwnerWritable(plans: plans)
        var didChange = false
        for plan in plans where plan.state != .draft {
            plan.state = .draft
            didChange = true
        }

        if didChange {
            try saveContext(operation: "Unable to reset plans to draft")
        }
    }

    func applyFeasibilitySuggestion(_ suggestion: FeasibilitySuggestion, goals: [Goal]) throws -> Bool {
        try accessGuard.assertOwnerWritable(goals: goals)
        var affectedGoalIDs: Set<UUID> = []
        switch suggestion {
        case .increaseBudget, .editGoal:
            return false
        case .extendDeadline(let goalId, _, let months):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            guard let updated = Calendar.current.date(byAdding: .month, value: months, to: goal.deadline) else {
                return false
            }
            goal.deadline = updated
            affectedGoalIDs.insert(goal.id)
        case .reduceTarget(let goalId, _, let to, _):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            goal.targetAmount = to
            affectedGoalIDs.insert(goal.id)
        }

        try saveContext(operation: "Unable to apply feasibility suggestion")
        postSharedGoalDataDidChange(goalIDs: affectedGoalIDs, reason: "goalMutation")
        return true
    }

    func applyBudgetPlan(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan],
        budgetCurrency: String
    ) async throws {
        try accessGuard.assertOwnerWritable(plans: currentPlans)
        var affectedGoalIDs: Set<UUID> = []
        let contributionMap = Dictionary(
            uniqueKeysWithValues: (plan.schedule.first?.contributions ?? []).map { ($0.goalId, $0.amount) }
        )

        for monthlyPlan in currentPlans {
            guard !monthlyPlan.isSkipped else { continue }
            let plannedAmount = contributionMap[monthlyPlan.goalId] ?? 0
            var converted = plannedAmount

            if plannedAmount > 0, monthlyPlan.currency != budgetCurrency {
                guard let rate = try? await exchangeRateService.fetchRate(from: budgetCurrency, to: monthlyPlan.currency) else {
                    throw PersistenceMutationError.validationFailed("Missing exchange rates for some goals.")
                }
                converted = plannedAmount * rate
            }

            monthlyPlan.setCustomAmount(plannedAmount > 0 ? converted : 0)
            affectedGoalIDs.insert(monthlyPlan.goalId)
        }

        try saveContext(operation: "Unable to apply budget to plans")
        postSharedGoalDataDidChange(goalIDs: affectedGoalIDs, reason: "goalMutation")
    }

    private func saveContext(operation: String) throws {
        do {
            try modelContext.save()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }

    private func postSharedGoalDataDidChange(goalIDs: Set<UUID>, reason: String) {
        guard goalIDs.isEmpty == false else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": Array(goalIDs),
                "reason": reason
            ]
        )
    }
}

@MainActor
final class OnboardingMutationService: OnboardingMutationServiceProtocol {
    private let modelContext: ModelContext
    private let notificationManager: NotificationManager

    init(modelContext: ModelContext, notificationManager: NotificationManager? = nil) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager ?? .shared
    }

    func createGoalFromTemplate(_ template: GoalTemplate, userProfile: UserProfile) async throws {
        if await MainActor.run(body: { UITestFlags.consumeSimulatedGoalSaveFailureIfNeeded() }) {
            throw PersistenceMutationError.saveFailed(
                "Unable to create onboarding goal",
                underlying: NSError(
                    domain: "UITestFlags",
                    code: 599,
                    userInfo: [NSLocalizedDescriptionKey: "Simulated onboarding save failure"]
                )
            )
        }

        let goalData = template.createGoal()
        let goal = Goal(
            name: goalData.name,
            currency: goalData.currency,
            targetAmount: goalData.targetAmount,
            deadline: goalData.deadline,
            startDate: Date()
        )

        if userProfile.experienceLevel != .beginner {
            goal.reminderFrequency = ReminderFrequency.weekly.rawValue
            goal.reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
        }

        modelContext.insert(goal)

        for recommendation in template.generateAssets().prefix(3) {
            let asset = Asset(currency: recommendation.currency)
            modelContext.insert(asset)
            modelContext.insert(AssetAllocation(asset: asset, goal: goal, amount: asset.currentAmount))
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(goal)
            throw PersistenceMutationError.saveFailed("Unable to create onboarding goal", underlying: error)
        }

        if goal.reminderFrequency != nil {
            await notificationManager.scheduleReminders(for: goal)
        }

        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [goal.id],
                "reason": "goalMutation"
            ]
        )
    }
}
