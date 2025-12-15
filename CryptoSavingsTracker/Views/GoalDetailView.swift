    //
    //  GoalDetailView.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import SwiftData
import Foundation

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    
    @Query private var allAssets: [Asset]
    @Query private var allTransactions: [Transaction]
    @State private var showingAddAsset = false
    @State private var expandedAssets: Set<UUID> = []
    @State private var goalViewModel: GoalViewModel
    @StateObject private var dashboardViewModel = DIContainer.shared.makeDashboardViewModel()
    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    @State private var showingCharts = false
    @State private var editingGoal: Goal?
    @State private var showingDeleteConfirmation = false
    
    init(goal: Goal) {
        self.goal = goal
        let goalId = goal.id
        self._allAssets = Query(filter: #Predicate<Asset> { asset in
            asset.allocations.contains { allocation in
                allocation.goal?.id == goalId
            }
        }, sort: \Asset.currency)
        
        self._goalViewModel = State(initialValue: GoalViewModel(goal: goal))
    }
    
    private var goalAssets: [Asset] {
        allAssets.filter { asset in
            asset.allocations.contains { allocation in
                allocation.goal?.id == goal.id
            }
        }
    }
    
    // MARK: - Sub Views
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deadline: \(goal.deadline, format: .dateTime.day().month().year()) (\(goal.daysRemaining) days remaining)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target: \(String(format: "%.2f", goal.targetAmount)) \(goal.currency)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Current: \(String(format: "%.2f", goalViewModel.currentTotal)) \(goal.currency)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                refreshButton
            }
            
            if let nextReminder = goal.nextReminder {
                HStack {
                    Text("Next reminder: \(nextReminder, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            HStack {
                Text("Suggested deposit: \(String(format: "%.2f", goalViewModel.suggestedDeposit)) \(goal.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            descriptionSection
            linkSection
        }
        .padding()
    }
    
    @ViewBuilder
    private var refreshButton: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: {
                Task { await refreshBalances() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: goalViewModel.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                    Text("Refresh").font(.caption)
                }
                .foregroundColor(goalViewModel.isLoading ? .accessibleSecondary : .accessiblePrimary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(goalViewModel.isLoading)
            .buttonStyle(PlainButtonStyle())
            
            if let lastRefresh = lastRefresh {
                Text("Updated: \(lastRefresh, format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var descriptionSection: some View {
        if let description = goal.goalDescription, !description.isEmpty {
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text").foregroundColor(.accessibleSecondary)
                    Text("Description").font(.caption).fontWeight(.medium).foregroundColor(.accessibleSecondary)
                    Spacer()
                }
                Text(description).font(.callout).foregroundColor(.primary)
            }
        }
    }
    
    @ViewBuilder
    private var linkSection: some View {
        if let linkString = goal.link, !linkString.isEmpty, let url = URL(string: linkString.contains("://") ? linkString : "https://\(linkString)") {
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "link").foregroundColor(.accessibleSecondary)
                    Text("Link").font(.caption).fontWeight(.medium).foregroundColor(.accessibleSecondary)
                    Spacer()
                }
                Link(destination: url) {
                    HStack {
                        Text(url.host ?? linkString)
                            .font(.callout)
                            .foregroundColor(.accessiblePrimary)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundColor(.accessiblePrimary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var chartsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) { showingCharts.toggle() }
                }) {
                    HStack(spacing: 4) {
                        Text(showingCharts ? "Hide Details" : "Show Details")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: showingCharts ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.accessiblePrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accessiblePrimaryBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            
            progressRingSection
            
            if showingCharts && !dashboardViewModel.assetComposition.isEmpty {
                CompactAssetCompositionView(
                    assetCompositions: dashboardViewModel.assetComposition,
                    size: 100
                )
                .padding(12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
            }
        }
    }
    
    @ViewBuilder
    private var progressRingSection: some View {
        ZStack {
            if goalViewModel.isLoading {
                // Show loading indicator while data is being fetched
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 180)
            } else {
                ProgressRingView(
                    progress: goalViewModel.progress,
                    current: goalViewModel.currentTotal,
                    target: goal.targetAmount,
                    currency: goal.currency,
                    lineWidth: 15,
                    showLabels: true
                )
                .frame(height: 180)
                .animation(.easeInOut(duration: 0.6), value: goalViewModel.progress)
            }
        }
        .task(id: goal.id) { await goalViewModel.refreshValues() }
        .onChange(of: goal.allocations) { _, _ in
            Task { await goalViewModel.refreshValues() }
        }
    }
    
    // Balance history views removed per request.
    
    @ViewBuilder
    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assets")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 8)
            if goalAssets.isEmpty {
                EmptyStateView(
                    icon: "bitcoinsign.circle",
                    title: "No Assets Added",
                    description: "Add cryptocurrency assets to start tracking your progress toward this goal",
                    primaryAction: EmptyStateAction(
                        title: "Add First Asset",
                        accessibilityIdentifier: "addAssetButton"
                    ) { showingAddAsset = true }
                )
                .frame(height: 200)
                .padding(.vertical, 8)
            } else {
                ForEach(goalAssets) { asset in
                    AssetRowView(
                        asset: asset,
                        goal: goal,
                        isExpanded: expandedAssets.contains(asset.id),
                        onToggleExpanded: {
                            withAnimation(.default) {
                                if expandedAssets.contains(asset.id) { 
                                    expandedAssets.remove(asset.id) 
                                } else { 
                                    expandedAssets.insert(asset.id) 
                                }
                            }
                        },
                        onDelete: {
                            withAnimation(.default) {
                                expandedAssets.remove(asset.id)
                                modelContext.delete(asset)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("Failed to delete asset: \(error)")
                                }
                            }
                        }
                    )
                }
                .onDelete(perform: deleteAssets)
                .animation(.default, value: goalAssets.count)
                
                Button(action: { showingAddAsset = true }) {
                    HStack { Image(systemName: "plus.circle.fill"); Text("Add Asset") }
                        .foregroundColor(.accessiblePrimary)
                }
                .accessibilityIdentifier("addAssetButton")
            }
        }
    }
    
    private var scrollViewContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header + Charts card
                VStack(spacing: 20) {
                    headerSection
                    chartsSection
                }
                .padding(16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)

                // Assets Section
                assetsSection
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
        .safeAreaPadding(.top)
        .navigationTitle(goal.name)
    }

    var body: some View {
        scrollViewContent
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        editingGoal = goal
                    } label: {
                        Label("Edit Goal", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Goal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Goal actions")
                .accessibilityHint("Tap to edit or delete this goal")
            }
#else
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        editingGoal = goal
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
#endif
        }
        .confirmationDialog(
            "Delete Goal?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                deleteGoal()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete '\(goal.name)' and all associated assets and transactions. This action cannot be undone.")
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: modelContext)
#if os(macOS)
                .presentationDetents([.large])
#else
                .presentationDetents([.large])
#endif
        }
        .task(id: goal.id) {
            goalViewModel.setModelContext(modelContext)
            await goalViewModel.refreshValues()
            await dashboardViewModel.loadData(for: goal, modelContext: modelContext)
        }
        .onChange(of: goal.id) { _, _ in
                // Create new goalViewModel for the new goal
            goalViewModel = GoalViewModel(goal: goal)
            goalViewModel.setModelContext(modelContext)
            Task {
                await goalViewModel.refreshValues()
            }
        }
        .onChange(of: goalAssets.count) { oldValue, newValue in
            Task {
                    // Add a small delay to let SwiftData process the changes
                try? await Task.sleep(for: .milliseconds(100))
                await goalViewModel.refreshValues()
            }
        }
        .onChange(of: allAssets.count) { oldValue, newValue in
            Task {
                await goalViewModel.refreshValues()
            }
        }
        .onChange(of: allTransactions.count) { oldValue, newValue in
            Task {
                    // Add a small delay to let SwiftData process the changes
                try? await Task.sleep(for: .milliseconds(100))
                await goalViewModel.refreshValues()
            }
        }
#if os(macOS)
        .popover(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
                .frame(minWidth: 400, minHeight: 300)
        }
#else
        .sheet(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
                .presentationDetents([.large])
        }
#endif
    } // End of body
    
    private func refreshBalances() async {
        // Clear cache to force refresh
        BalanceCacheManager.shared.clearCache()
        
        // Refresh goal values
        await goalViewModel.refreshValues()
        
        // Also refresh dashboard data (for charts)
        await dashboardViewModel.loadData(for: goal, modelContext: modelContext)
        
        await MainActor.run {
            lastRefresh = Date()
            // Post notification to refresh all goal progress views
            NotificationCenter.default.post(name: .goalProgressRefreshed, object: goal)
        }
    }
    
    private func deleteAssets(offsets: IndexSet) {
        withAnimation(.default) {
                // Get the assets to delete before modifying anything
            let assetsToDelete = offsets.map { goalAssets[$0] }
            
                // Remove from expanded assets set to prevent UI issues
            for asset in assetsToDelete {
                expandedAssets.remove(asset.id)
            }
            
                // Delete the assets from the model context
            for asset in assetsToDelete {
                modelContext.delete(asset)
            }
            
                // Save the context
            do {
                try modelContext.save()
            } catch {
                    // Asset deletion failed - consider showing user feedback
            }
        }
    }
    
    private func deleteGoal() {
        withAnimation {
            Task {
                await NotificationManager.shared.cancelNotifications(for: goal)
            }
            modelContext.delete(goal)
            try? modelContext.save()
            
            NotificationCenter.default.post(name: .goalDeleted, object: goal)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    container.mainContext.insert(goal)
    
    return NavigationView {
        GoalDetailView(goal: goal)
    }
    .modelContainer(container)
}
