//
//  AddTransactionView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let asset: Asset
    
    @State private var amount = ""
    @State private var comment = ""
    
    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            Text("New Transaction")
                .font(.title2)
                .padding()
            
            Form {
                Section(header: Text("Transaction Details")) {
                    HStack {
                        Text("Asset:")
                        Spacer()
                        Text(asset.currency)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    TextField("Deposit Amount", text: $amount)
                        .padding(.vertical, 4)
                    
                    TextField("Comment (optional)", text: $comment)
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 4)
                
                Section(footer: Text("Enter the amount you're depositing and optionally add a comment for reference.")) {
                    EmptyView()
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    Task { await saveTransaction() }
                }
                .disabled(!isValidInput)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 250)
#else
        NavigationView {
            Form {
                Section(header: Text("Transaction Details")) {
                    HStack {
                        Text("Asset:")
                        Spacer()
                        Text(asset.currency)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    TextField("Deposit Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .padding(.vertical, 4)
                    
                    TextField("Comment (optional)", text: $comment)
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 4)
                
                Section(footer: Text("Enter the amount you're depositing and optionally add a comment for reference.")) {
                    EmptyView()
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            .navigationTitle("New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveTransaction() }
                    }
                    .disabled(!isValidInput)
                }
            }
        }
#endif
    }
    
    private var isValidInput: Bool {
        guard let value = Double(amount) else { return false }
        return value > 0
    }
    
    private func saveTransaction() async {
        guard let depositAmount = Double(amount) else { return }
        
        print("💾 Saving new transaction:")
        print("   Amount: \(depositAmount)")
        print("   Asset: \(asset.currency)")
        print("   Comment: \(comment.isEmpty ? "none" : comment)")
        print("   Asset ID: \(asset.id)")
        print("   Current transaction count for asset: \(asset.transactions.count)")
        
        let newTransaction = Transaction(amount: depositAmount, asset: asset, comment: comment.isEmpty ? nil : comment)
        
        // Explicitly establish the relationship on both sides
        asset.transactions.append(newTransaction)
        
        modelContext.insert(newTransaction)
        
        do {
            // SwiftData will automatically trigger UI updates through @Query
            try modelContext.save()
            print("✅ Transaction saved successfully")
            print("   New transaction count for asset: \(asset.transactions.count)")

            // If there's an active execution record for this goal/month, also create a Contribution
            try await linkTransactionToCurrentExecution(transaction: newTransaction)
            
        } catch {
            print("❌ Failed to save transaction: \(error)")
            // Show user-friendly error message
            // TODO: Add error state display to UI
        }
        
        Task {
            // Schedule reminders for all goals this asset is allocated to
            for allocation in asset.allocations {
                if let goal = allocation.goal {
                    await NotificationManager.shared.scheduleReminders(for: goal)
                }
            }
        }
        dismiss()
    }

    /// Bridge manual transaction into a Contribution when a current execution record exists
    @MainActor
    private func linkTransactionToCurrentExecution(transaction: Transaction) async throws {
        // Use only allocations that actually have a share to avoid creating zero-amount contributions
        let activeAllocations = asset.allocations.filter { $0.percentage > 0.0001 }
        guard !activeAllocations.isEmpty else {
            AppLog.debug("Transaction has no active goal allocations; skipping contribution bridge", category: .executionTracking)
            return
        }

        // Find the goal associated with this asset via allocations
        guard let allocation = activeAllocations.first,
              let goal = allocation.goal else {
            AppLog.debug("Transaction not linked to a goal; skipping contribution bridge", category: .executionTracking)
            return
        }

        let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        let exchangeRateService = DIContainer.shared.exchangeRateService

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let allocatedGoals = activeAllocations.compactMap { $0.goal }
        let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: allocatedGoals)

        // Get existing record or create one if needed (cover all allocated goals)
        let record: MonthlyExecutionRecord
        if let existing = try executionService.getRecord(for: monthLabel) {
            record = existing
        } else {
            record = try executionService.startTracking(for: monthLabel, from: plans, goals: allocatedGoals)
        }

        for allocation in activeAllocations {
            guard let goal = allocation.goal else { continue }
            guard let plan = plans.first(where: { $0.goalId == goal.id }) else { continue }

            let assetPortion = transaction.amount * allocation.percentage
            if assetPortion <= 0 {
                continue
            }

            let amountInGoalCurrency: Double
            if goal.currency == asset.currency {
                amountInGoalCurrency = assetPortion
            } else if let rate = try? await exchangeRateService.fetchRate(from: asset.currency, to: goal.currency) {
                amountInGoalCurrency = assetPortion * rate
            } else {
                AppLog.error("Exchange rate failed for contribution \(asset.currency) → \(goal.currency); skipping contribution to avoid incorrect amount.", category: .executionTracking)
                continue
            }

            let contribution = Contribution(
                amount: amountInGoalCurrency,
                goal: goal,
                asset: asset,
                source: .manualDeposit
            )
            contribution.assetAmount = assetPortion
            contribution.currencyCode = goal.currency
            contribution.assetSymbol = asset.currency
            contribution.date = transaction.date
            contribution.notes = transaction.comment
            contribution.monthLabel = monthLabel
            contribution.monthlyPlan = plan
            contribution.executionRecordId = record.id

            modelContext.insert(contribution)
            if plan.contributions == nil {
                plan.contributions = []
            }
            plan.contributions?.append(contribution)
            plan.totalContributed += contribution.amount

            // Notify listeners to refresh execution state
            NotificationCenter.default.post(name: .goalUpdated, object: goal)
        }

        try modelContext.save()
        AppLog.info("Bridged transaction into contributions for \(allocatedGoals.count) goal(s) in \(monthLabel)", category: .executionTracking)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    let asset = Asset(currency: "BTC")
    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    
    return AddTransactionView(asset: asset)
        .modelContainer(container)
}
