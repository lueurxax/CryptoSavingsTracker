//
//  MonthlyPlanMigrationService.swift
//  CryptoSavingsTracker
//
//  Created for v2.2 - Unified Monthly Planning Architecture
//  Migrates existing MonthlyPlan and Contribution data to new schema
//

import SwiftData
import Foundation

@MainActor
final class MonthlyPlanMigrationService {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Migration Entry Point

    /// Execute complete migration to Schema V2
    func migrateToSchemaV2() async throws {
        AppLog.info("Starting MonthlyPlan Schema V2 migration", category: .monthlyPlanning)

        // Step 1: Add monthLabel to existing plans
        try await addMonthLabelToExistingPlans()

        // Step 2: Link existing execution records to plans
        try await linkExecutionRecordsToPlans()

        // Step 3: Backfill contribution→plan relationships (returns auto-created plans)
        let autoCreatedPlans = try await backfillContributionPlanLinks()

        // Step 4.5: Recalculate auto-created plans with proper targets
        try await recalculateAutoCreatedPlans(autoCreatedPlans)

        // Step 4: Set plan states based on execution status
        try await setInitialPlanStates()

        // Step 5: Clean up orphaned plans
        try await cleanupOrphanedPlans()

        // Step 6: Validate unique constraint
        try await validateUniqueConstraint()

        AppLog.info("Schema V2 migration completed successfully", category: .monthlyPlanning)
    }

    // MARK: - Step 1: Add monthLabel to Existing Plans with Robust Fallback Chain

    private func addMonthLabelToExistingPlans() async throws {
        AppLog.debug("Step 1: Adding monthLabel to existing plans with fallback chain", category: .monthlyPlanning)

        let descriptor = FetchDescriptor<MonthlyPlan>()
        let allPlans = try modelContext.fetch(descriptor)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        var updatedCount = 0
        var needsReviewCount = 0

        for plan in allPlans {
            // If monthLabel is already set, skip
            if !plan.monthLabel.isEmpty {
                continue
            }

            // FALLBACK CHAIN:
            // 1. Try executionRecord.monthLabel
            if let record = plan.executionRecord {
                plan.monthLabel = record.monthLabel
                AppLog.debug("Set monthLabel from execution record: \(record.monthLabel)", category: .monthlyPlanning)
                updatedCount += 1
                continue
            }

            // 2. Try contributions (if any linked to this plan)
            if let contributions = plan.contributions, !contributions.isEmpty {
                // Use earliest contribution date
                if let earliestDate = contributions.map({ $0.date }).min() {
                    plan.monthLabel = formatter.string(from: earliestDate)
                    AppLog.debug("Set monthLabel from earliest contribution: \(plan.monthLabel)", category: .monthlyPlanning)
                    updatedCount += 1
                    continue
                }
            }

            // 3. Try createdDate (if it looks reasonable - not default 1970-01-01)
            if plan.createdDate > oneYearAgo && plan.createdDate < Date() {
                // createdDate looks reasonable
                plan.monthLabel = formatter.string(from: plan.createdDate)
                AppLog.debug("Set monthLabel from createdDate: \(plan.monthLabel)", category: .monthlyPlanning)
                updatedCount += 1
                continue
            }

            // 4. LAST RESORT: Use current month and flag for manual review
            plan.monthLabel = formatter.string(from: Date())
            plan.needsReview = true  // Flag for manual review
            AppLog.warning("Plan \(plan.id) has no valid date sources, defaulting to current month with needsReview flag", category: .monthlyPlanning)
            updatedCount += 1
            needsReviewCount += 1
        }

        try modelContext.save()
        AppLog.info("Step 1 complete: Updated \(updatedCount) plans with monthLabel (\(needsReviewCount) flagged for review)", category: .monthlyPlanning)
    }

    // MARK: - Step 2: Link Execution Records to Plans

    private func linkExecutionRecordsToPlans() async throws {
        AppLog.debug("Step 2: Linking execution records to plans", category: .monthlyPlanning)

        let recordDescriptor = FetchDescriptor<MonthlyExecutionRecord>()
        let allRecords = try modelContext.fetch(recordDescriptor)

        var linkedCount = 0

        for record in allRecords {
            // Find plans matching this record's month and goals
            // Note: We need to check each plan individually against goalIds
            let monthLabel = record.monthLabel  // Capture value for predicate
            let predicate = #Predicate<MonthlyPlan> { plan in
                plan.monthLabel == monthLabel
            }

            let descriptor = FetchDescriptor<MonthlyPlan>(predicate: predicate)
            let allMatchingPlans = try modelContext.fetch(descriptor)

            // Filter plans that match the record's goalIds
            let matchingPlans = allMatchingPlans.filter { plan in
                record.goalIds.contains(plan.goalId)
            }

            // Link each plan to execution record
            for plan in matchingPlans {
                plan.executionRecord = record
                linkedCount += 1
            }
        }

        try modelContext.save()
        AppLog.info("Step 2 complete: Linked \(linkedCount) plans to execution records", category: .monthlyPlanning)
    }

    // MARK: - Step 3: Backfill Contribution→Plan Links

    private func backfillContributionPlanLinks() async throws -> [MonthlyPlan] {
        AppLog.debug("Step 3: Backfilling contribution→plan links", category: .monthlyPlanning)

        let descriptor = FetchDescriptor<Contribution>()
        let allContributions = try modelContext.fetch(descriptor)

        var linkedCount = 0
        var orphanedCount = 0
        var autoCreatedPlans: [MonthlyPlan] = []

        for contribution in allContributions {
            // Skip if already linked
            if contribution.monthlyPlan != nil {
                continue
            }

            // Ensure contribution has monthLabel
            if contribution.monthLabel.isEmpty {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM"
                contribution.monthLabel = formatter.string(from: contribution.date)
            }

            // Find matching plan by goalId and monthLabel
            guard let goalId = contribution.goal?.id else {
                AppLog.warning("Contribution \(contribution.id) has no goal, marking as orphaned", category: .monthlyPlanning)
                orphanedCount += 1
                continue
            }

            // STRATEGY 1: Try exact match
            let contributionMonthLabel = contribution.monthLabel  // Capture value for predicate
            let predicate = #Predicate<MonthlyPlan> { plan in
                plan.monthLabel == contributionMonthLabel
            }

            let planDescriptor = FetchDescriptor<MonthlyPlan>(predicate: predicate)
            let plans = try modelContext.fetch(planDescriptor)
            if let matchingPlan = plans.first(where: { $0.goalId == goalId }) {
                contribution.monthlyPlan = matchingPlan
                linkedCount += 1
                continue
            }

            // STRATEGY 2: Try nearby month (±1 month)
            let nearbyMonths = [
                addMonths(to: contribution.monthLabel, delta: -1),
                addMonths(to: contribution.monthLabel, delta: 1)
            ]

            var found = false
            for nearbyMonth in nearbyMonths {
                let nearbyPredicate = #Predicate<MonthlyPlan> { plan in
                    plan.monthLabel == nearbyMonth
                }
                let nearbyDescriptor = FetchDescriptor<MonthlyPlan>(predicate: nearbyPredicate)
                let nearbyPlans = try modelContext.fetch(nearbyDescriptor)

                if let nearbyPlan = nearbyPlans.first(where: { $0.goalId == goalId }) {
                    contribution.monthlyPlan = nearbyPlan
                    linkedCount += 1
                    AppLog.debug("Linked contribution via nearby month: \(contribution.monthLabel) → \(nearbyMonth)", category: .monthlyPlanning)
                    found = true
                    break
                }
            }

            if found { continue }

            // STRATEGY 3: Create missing plan (will be recalculated in step 4.5)
            AppLog.info("Creating missing plan for contribution: goal \(goalId), month \(contribution.monthLabel)", category: .monthlyPlanning)

            let newPlan = MonthlyPlan(
                goalId: goalId,
                monthLabel: contribution.monthLabel,
                requiredMonthly: 0,  // Placeholder - will be recalculated
                remainingAmount: 0,
                monthsRemaining: 0,
                currency: contribution.currencyCode ?? "USD",
                status: .onTrack,
                state: .completed  // Old month
            )
            modelContext.insert(newPlan)
            contribution.monthlyPlan = newPlan
            autoCreatedPlans.append(newPlan)  // Track for recalculation
            linkedCount += 1
        }

        try modelContext.save()
        AppLog.info("Step 3 complete: Linked \(linkedCount) contributions, \(orphanedCount) orphaned, \(autoCreatedPlans.count) auto-created", category: .monthlyPlanning)

        return autoCreatedPlans
    }

    // MARK: - Step 4.5: Recalculate Auto-Created Plans

    private func recalculateAutoCreatedPlans(_ plans: [MonthlyPlan]) async throws {
        guard !plans.isEmpty else {
            AppLog.debug("Step 4.5: No auto-created plans to recalculate", category: .monthlyPlanning)
            return
        }

        AppLog.debug("Step 4.5: Recalculating \(plans.count) auto-created plans", category: .monthlyPlanning)

        // Fetch goals
        let goalIds = Set(plans.map { $0.goalId })
        let goalDescriptor = FetchDescriptor<Goal>()
        let allGoals = try modelContext.fetch(goalDescriptor)
        let goalDict = Dictionary(uniqueKeysWithValues: allGoals.map { ($0.id, $0) })

        var recalculatedCount = 0
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        for plan in plans {
            guard let goal = goalDict[plan.goalId] else {
                AppLog.warning("Cannot recalculate plan - goal \(plan.goalId) not found", category: .monthlyPlanning)
                continue
            }

            // Calculate what the requirement WOULD have been at that time
            // Use monthLabel to determine historical deadline
            guard let planDate = formatter.date(from: plan.monthLabel) else { continue }

            let monthsToDeadline = max(1, Calendar.current.dateComponents(
                [.month],
                from: planDate,
                to: goal.deadline
            ).month ?? 1)

            // Estimate "remaining amount" at that time
            // (We can't know actual asset value back then, so use contribution total as proxy)
            let contributedAmount = plan.contributions?.reduce(0) { $0 + $1.amount } ?? 0
            let estimatedRemaining = max(0, goal.targetAmount - contributedAmount)
            let estimatedMonthly = estimatedRemaining / Double(monthsToDeadline)

            plan.requiredMonthly = estimatedMonthly
            plan.remainingAmount = estimatedRemaining
            plan.monthsRemaining = monthsToDeadline
            plan.status = .onTrack  // Historical - can't determine actual status

            recalculatedCount += 1
            AppLog.debug("Recalculated auto-created plan: \(plan.monthLabel), requiredMonthly=\(estimatedMonthly)", category: .monthlyPlanning)
        }

        try modelContext.save()
        AppLog.info("Step 4.5 complete: Recalculated \(recalculatedCount) auto-created plans", category: .monthlyPlanning)
    }

    // Helper method for month manipulation
    private func addMonths(to monthLabel: String, delta: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthLabel) else { return monthLabel }
        guard let newDate = Calendar.current.date(byAdding: .month, value: delta, to: date) else { return monthLabel }
        return formatter.string(from: newDate)
    }

    // MARK: - Step 4: Set Initial Plan States

    private func setInitialPlanStates() async throws {
        AppLog.debug("Step 4: Setting initial plan states", category: .monthlyPlanning)

        let descriptor = FetchDescriptor<MonthlyPlan>()
        let allPlans = try modelContext.fetch(descriptor)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())

        for plan in allPlans {
            // If state is already set (not draft), skip
            if plan.stateRawValue != "draft" {
                continue
            }

            if let executionRecord = plan.executionRecord {
                // Respect execution record status
                switch executionRecord.status {
                case .executing:
                    plan.stateRawValue = "executing"
                case .closed:
                    plan.stateRawValue = "completed"
                case .draft:
                    plan.stateRawValue = "draft"
                }
            } else {
                // No execution record - determine by month
                if plan.monthLabel < currentMonth {
                    // Past month without execution record → completed
                    plan.stateRawValue = "completed"
                } else if plan.monthLabel > currentMonth {
                    // Future month → draft
                    plan.stateRawValue = "draft"
                } else {
                    // Current month without execution record → draft
                    plan.stateRawValue = "draft"
                }
            }
        }

        try modelContext.save()
        AppLog.info("Step 4 complete: Set initial states for \(allPlans.count) plans", category: .monthlyPlanning)
    }

    // MARK: - Step 5: Cleanup Orphaned Plans

    private func cleanupOrphanedPlans() async throws {
        AppLog.debug("Step 5: Cleaning up orphaned plans", category: .monthlyPlanning)

        // Fetch all plans
        let descriptor = FetchDescriptor<MonthlyPlan>()
        let allPlans = try modelContext.fetch(descriptor)

        // Fetch all active goal IDs
        let goalDescriptor = FetchDescriptor<Goal>()
        let allGoals = try modelContext.fetch(goalDescriptor)
        let activeGoalIds = Set(allGoals.map { $0.id })

        // Find orphaned plans (goalId no longer exists)
        var orphanedCount = 0
        for plan in allPlans {
            if !activeGoalIds.contains(plan.goalId) {
                // Check if this plan has contributions
                // Note: We need to fetch all contributions and filter in memory
                let contribDescriptor = FetchDescriptor<Contribution>()
                let allContributions = try modelContext.fetch(contribDescriptor)
                let contributions = allContributions.filter { contribution in
                    contribution.monthlyPlan?.id == plan.id
                }

                if contributions.isEmpty {
                    // No contributions, safe to delete
                    modelContext.delete(plan)
                    orphanedCount += 1
                } else {
                    // Has contributions, keep but mark as completed
                    plan.stateRawValue = "completed"
                    AppLog.warning("Kept orphaned plan \(plan.id) with \(contributions.count) contributions", category: .monthlyPlanning)
                }
            }
        }

        try modelContext.save()
        AppLog.info("Step 5 complete: Removed \(orphanedCount) orphaned plans", category: .monthlyPlanning)
    }

    // MARK: - Step 6: Validate Unique Constraint

    private func validateUniqueConstraint() async throws {
        AppLog.debug("Step 6: Validating unique constraint (goalId, monthLabel)", category: .monthlyPlanning)

        let descriptor = FetchDescriptor<MonthlyPlan>()
        let allPlans = try modelContext.fetch(descriptor)

        // Group by (goalId, monthLabel) using a string key
        let grouped = Dictionary(grouping: allPlans) { plan in
            "\(plan.goalId)_\(plan.monthLabel)"
        }

        var duplicateGroups = 0
        var duplicatePlansRemoved = 0

        for (_, plans) in grouped where plans.count > 1 {
            duplicateGroups += 1
            if let firstPlan = plans.first {
                AppLog.warning("Found \(plans.count) duplicate plans for goal \(firstPlan.goalId) in \(firstPlan.monthLabel)", category: .monthlyPlanning)
            }

            // Keep the plan with execution record, or the oldest one
            let sortedPlans = plans.sorted { p1, p2 in
                if p1.executionRecord != nil && p2.executionRecord == nil {
                    return true // p1 comes first
                } else if p1.executionRecord == nil && p2.executionRecord != nil {
                    return false // p2 comes first
                } else {
                    return p1.createdDate < p2.createdDate // older first
                }
            }

            let planToKeep = sortedPlans[0]
            let plansToDelete = Array(sortedPlans.dropFirst())

            // Reassign contributions to the kept plan
            for deletedPlan in plansToDelete {
                // Fetch all contributions and filter in memory
                let contribDescriptor = FetchDescriptor<Contribution>()
                let allContributions = try modelContext.fetch(contribDescriptor)
                let contributions = allContributions.filter { contribution in
                    contribution.monthlyPlan?.id == deletedPlan.id
                }

                for contribution in contributions {
                    contribution.monthlyPlan = planToKeep
                }

                modelContext.delete(deletedPlan)
                duplicatePlansRemoved += 1
            }
        }

        try modelContext.save()

        if duplicateGroups > 0 {
            AppLog.warning("Step 6 complete: Found \(duplicateGroups) duplicate groups, removed \(duplicatePlansRemoved) plans", category: .monthlyPlanning)
        } else {
            AppLog.info("Step 6 complete: No duplicate plans found", category: .monthlyPlanning)
        }
    }

    // MARK: - Verification Queries

    /// Verify migration completed successfully
    func verifyMigration() async throws -> MigrationVerification {
        let planDescriptor = FetchDescriptor<MonthlyPlan>()
        let allPlans = try modelContext.fetch(planDescriptor)

        let plansWithoutMonthLabel = allPlans.filter { $0.monthLabel.isEmpty }

        let contributionDescriptor = FetchDescriptor<Contribution>()
        let allContributions = try modelContext.fetch(contributionDescriptor)
        let unlinkedContributions = allContributions.filter { $0.monthlyPlan == nil }

        // Check for duplicates using string key
        let grouped = Dictionary(grouping: allPlans) { plan in
            "\(plan.goalId)_\(plan.monthLabel)"
        }
        let duplicates = grouped.filter { $0.value.count > 1 }

        return MigrationVerification(
            totalPlans: allPlans.count,
            plansWithoutMonthLabel: plansWithoutMonthLabel.count,
            totalContributions: allContributions.count,
            unlinkedContributions: unlinkedContributions.count,
            duplicatePlanGroups: duplicates.count
        )
    }
}

// MARK: - Verification Result

struct MigrationVerification {
    let totalPlans: Int
    let plansWithoutMonthLabel: Int
    let totalContributions: Int
    let unlinkedContributions: Int
    let duplicatePlanGroups: Int

    var isSuccessful: Bool {
        return plansWithoutMonthLabel == 0 &&
               unlinkedContributions == 0 &&
               duplicatePlanGroups == 0
    }

    var description: String {
        """
        Migration Verification:
        - Total plans: \(totalPlans)
        - Plans without monthLabel: \(plansWithoutMonthLabel)
        - Total contributions: \(totalContributions)
        - Unlinked contributions: \(unlinkedContributions)
        - Duplicate plan groups: \(duplicatePlanGroups)
        - Status: \(isSuccessful ? "✅ SUCCESS" : "❌ FAILED")
        """
    }
}
