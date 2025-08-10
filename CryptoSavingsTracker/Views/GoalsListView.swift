//
//  GoalsListView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData
import Foundation

struct GoalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Goal.deadline)]) private var goals: [Goal]
    @State private var refreshTrigger = UUID()
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var showingOnboarding = false
    @State private var monthlyPlanningViewModel: MonthlyPlanningViewModel?
    
    var body: some View {
        Group {
                if goals.isEmpty {
                    EmptyStateView.noGoals(
                        onCreateGoal: {
                            showingAddGoal = true
                        },
                        onStartOnboarding: {
                            showingOnboarding = true
                        }
                    )
                } else {
                    List {
                        // Portfolio-wide Monthly Planning Widget
                        Section {
                            if let viewModel = monthlyPlanningViewModel {
                                MonthlyPlanningWidget(viewModel: viewModel)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        
                        // Individual Goals
                        Section("Your Goals") {
                            ForEach(goals) { goal in
                                NavigationLink(destination: GoalDetailView(goal: goal)) {
                                    GoalRowView(goal: goal, refreshTrigger: refreshTrigger)
                                        .id("\(goal.id)-\(refreshTrigger)") // Force refresh when goal changes or when triggered
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.regularMaterial)
                                        .padding(.vertical, 2)
                                )
                                .contextMenu {
                                    Button {
                                        editingGoal = goal
                                    } label: {
                                        HStack {
                                            Text("Edit Goal")
                                            Image(systemName: "pencil")
                                        }
                                    }
                                    
                                    Button {
                                        Task {
                                            await NotificationManager.shared.cancelNotifications(for: goal)
                                        }
                                        modelContext.delete(goal)
                                        try? modelContext.save()
                                    } label: {
                                        HStack {
                                            Text("Delete Goal")
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                            }
                            .onDelete(perform: deleteGoals)
                            .animation(.default, value: goals.count)
                        }
                    }
                }
            }
            .navigationTitle("Crypto Goals")
            .onAppear {
                // Create the monthly planning view model with model context
                if monthlyPlanningViewModel == nil {
                    monthlyPlanningViewModel = MonthlyPlanningViewModel(modelContext: modelContext)
                }
                
                // Debug log all loaded goals
                AppLog.debug("📋 GoalsListView loaded \(goals.count) goals:", category: .goalList)
                for goal in goals {
                    AppLog.debug("  - '\(goal.name)': emoji='\(String(describing: goal.emoji))', progress=\(goal.progress), description='\(String(describing: goal.goalDescription))', link='\(String(describing: goal.link))'", category: .goalList)
                }
            }
            .onChange(of: editingGoal) { oldValue, newValue in
                // When edit dialog closes, force refresh goal data
                if oldValue != nil && newValue == nil {
                    AppLog.debug("🔄 Edit dialog closed, refreshing goal data", category: .goalList)
                    
                    // Force SwiftData to refresh by calling processPendingChanges
                    modelContext.processPendingChanges()
                    
                    // Force view refresh by updating refresh trigger
                    refreshTrigger = UUID()
                    
                    // Log updated goal data
                    for goal in goals {
                        AppLog.debug("  - Post-edit '\(goal.name)': emoji='\(String(describing: goal.emoji))', description='\(String(describing: goal.goalDescription))', link='\(String(describing: goal.link))'", category: .goalList)
                    }
                }
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
#else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
#endif
            }
#if os(macOS)
            .popover(isPresented: $showingAddGoal) {
                AddGoalView()
                    .frame(minWidth: 450, minHeight: 350)
            }
            .sheet(isPresented: .constant(editingGoal != nil)) {
                if let goal = editingGoal {
                    EditGoalView(goal: goal, modelContext: modelContext)
                        .frame(minWidth: 600, minHeight: 700)
                        .onDisappear {
                            editingGoal = nil
                        }
                }
            }
#else
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView()
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingFlowView()
            }
            .sheet(isPresented: .constant(editingGoal != nil)) {
                if let goal = editingGoal {
                    EditGoalView(goal: goal, modelContext: modelContext)
                        .presentationDetents([.large])
                        .onDisappear {
                            editingGoal = nil
                        }
                }
            }
#endif
    }
    
    private func deleteGoals(offsets: IndexSet) {
        withAnimation(.default) {
            for index in offsets {
                let goal = goals[index]
                Task {
                    await NotificationManager.shared.cancelNotifications(for: goal)
                }
                modelContext.delete(goal)
            }
            try? modelContext.save()
        }
    }
}

struct GoalRowView: View {
    let goal: Goal
    let refreshTrigger: UUID
    @State private var progressAnimation: Double = 0
    @State private var displayEmoji: String? = nil
    @State private var asyncProgress: Double = 0
    @State private var asyncCurrentTotal: Double = 0
    
    private var statusBadge: (text: String, color: Color, icon: String) {
        let progress = asyncProgress
        if progress >= 1.0 {
            return ("Achieved", AccessibleColors.success, "checkmark.circle.fill")
        } else if progress >= 0.75 {
            return ("On Track", AccessibleColors.success, "circle.fill")
        } else if goal.daysRemaining < 30 {
            return ("Behind", AccessibleColors.error, "exclamationmark.circle.fill")
        } else {
            return ("In Progress", AccessibleColors.warning, "clock.fill")
        }
    }
    
    private var progressBarColor: Color {
        let progress = asyncProgress
        if progress >= 0.75 {
            return AccessibleColors.success
        } else if progress >= 0.5 {
            return AccessibleColors.warning
        } else {
            return AccessibleColors.error
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            GoalRowIconView(goal: goal, displayEmoji: displayEmoji)
            GoalRowContentView(
                goal: goal,
                asyncProgress: asyncProgress,
                asyncCurrentTotal: asyncCurrentTotal,
                progressAnimation: progressAnimation,
                progressBarColor: progressBarColor,
                statusBadge: statusBadge
            )
            GoalRowChevronView()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onAppear {
            displayEmoji = goal.emoji
            Task {
                await loadAsyncProgress()
            }
        }
        .task {
            await loadAsyncProgress()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await loadAsyncProgress()
            }
        }
        .onChange(of: goal.assets.count) { _, _ in
            Task {
                await loadAsyncProgress()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.emoji ?? "") \(goal.name)")
        .accessibilityValue("Progress: \(Int(asyncProgress * 100))%, \(goal.daysRemaining) days remaining")
        .accessibilityHint(goal.goalDescription ?? "Tap to view goal details")
    }
    
    private func loadAsyncProgress() async {
        // Use the proper service that does currency conversion
        let newProgress = await GoalCalculationService.getProgress(for: goal)
        let newTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        
        await MainActor.run {
            // Only update if values actually changed to prevent unnecessary animations
            if abs(asyncProgress - newProgress) > 0.01 || abs(asyncCurrentTotal - newTotal) > 0.01 {
                asyncProgress = newProgress
                asyncCurrentTotal = newTotal
                
                withAnimation(.easeOut(duration: 0.8)) {
                    progressAnimation = newProgress
                }
            }
        }
    }
}

// MARK: - Goal Row Sub-Components
struct GoalRowIconView: View {
    let goal: Goal
    let displayEmoji: String?
    
    var body: some View {
        if let emoji = displayEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.title2)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "target")
                .font(.title2)
                .foregroundColor(.accessibleSecondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }
}

struct GoalRowContentView: View {
    let goal: Goal
    let asyncProgress: Double
    let asyncCurrentTotal: Double
    let progressAnimation: Double
    let progressBarColor: Color
    let statusBadge: (text: String, color: Color, icon: String)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Primary row: Name and Status Badge
            HStack {
                Text(goal.name)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: statusBadge.icon)
                        .font(.caption2)
                        .foregroundColor(statusBadge.color)
                    
                    Text(statusBadge.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusBadge.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusBadge.color.opacity(0.1))
                .cornerRadius(8)
            }
            
            GoalRowDetailsView(
                goal: goal,
                asyncProgress: asyncProgress,
                asyncCurrentTotal: asyncCurrentTotal
            )
            
            GoalRowProgressView(
                progressAnimation: progressAnimation,
                progressBarColor: progressBarColor
            )
            
            // Description preview (if exists)
            if let description = goal.goalDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }
}

struct GoalRowDetailsView: View {
    let goal: Goal
    let asyncProgress: Double
    let asyncCurrentTotal: Double
    
    var body: some View {
        HStack(spacing: 16) {
            // Days remaining with urgency
            HStack(spacing: 4) {
                Image(systemName: goal.daysRemaining < 30 ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.caption2)
                    .foregroundColor(goal.daysRemaining < 30 ? AccessibleColors.error : .accessibleSecondary)
                
                Text("\(goal.daysRemaining) days left")
                    .font(.subheadline)
                    .foregroundColor(goal.daysRemaining < 30 ? AccessibleColors.error : .accessibleSecondary)
            }
            
            Spacer()
            
            // Target amount with current progress
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(String(format: "%.0f", asyncCurrentTotal)) / \(String(format: "%.0f", goal.targetAmount)) \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Text("\(Int(asyncProgress * 100))% complete")
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
            }
        }
    }
}

struct GoalRowProgressView: View {
    let progressAnimation: Double
    let progressBarColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                
                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(progressBarColor)
                    .frame(width: geometry.size.width * progressAnimation, height: 4)
                    .animation(.easeInOut(duration: 0.6), value: progressAnimation)
            }
        }
        .frame(height: 4)
    }
}

struct GoalRowChevronView: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.accessibleSecondary)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    return GoalsListView()
        .modelContainer(container)
}