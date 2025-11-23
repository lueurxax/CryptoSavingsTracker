//
//  TransactionHistoryView.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftUI
import SwiftData

struct TransactionHistoryView: View {
    let asset: Asset
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var filterType: FilterType = .all
    
    enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case amountDescending = "Largest First"
        case amountAscending = "Smallest First"
    }
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case deposits = "Deposits"
        case withdrawals = "Withdrawals"
    }
    
    private var filteredTransactions: [Transaction] {
        var transactions = asset.transactions
        
        // Apply filter
        switch filterType {
        case .deposits:
            transactions = transactions.filter { $0.amount > 0 }
        case .withdrawals:
            transactions = transactions.filter { $0.amount < 0 }
        case .all:
            break
        }
        
        // Apply search
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                if let comment = transaction.comment {
                    return comment.localizedCaseInsensitiveContains(searchText)
                }
                return String(format: "%.6f", transaction.amount).contains(searchText)
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .dateDescending:
            transactions.sort { $0.date > $1.date }
        case .dateAscending:
            transactions.sort { $0.date < $1.date }
        case .amountDescending:
            transactions.sort { abs($0.amount) > abs($1.amount) }
        case .amountAscending:
            transactions.sort { abs($0.amount) < abs($1.amount) }
        }
        
        return transactions
    }
    
    private var totalBalance: Double {
        asset.transactions.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            summaryHeader
            
            // Filters
            filterSection
            
            // Transaction List
            if filteredTransactions.isEmpty {
                emptyState
            } else {
                transactionList
            }
        }
        .navigationTitle("Transaction History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    coordinator.goalCoordinator.showAddTransaction(to: asset)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private var summaryHeader: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Total Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.6f", totalBalance))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(asset.currency)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Deposits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.4f", asset.transactions.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }))
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 4) {
                    Text("Withdrawals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.4f", abs(asset.transactions.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount })))
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 4) {
                    Text("Count")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(asset.transactions.count)")
                        .font(.callout)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemGray6))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
    }
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $filterType) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Text("Sort by:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                
                Spacer()
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
    
    private var transactionList: some View {
        List {
            ForEach(filteredTransactions) { transaction in
                TransactionRow(transaction: transaction, currency: asset.currency)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTransaction(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No transactions found")
                .font(.headline)
            
            Text("Try adjusting your filters or search terms")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            ContributionBridge.removeLinkedContributions(for: transaction, in: modelContext)
            modelContext.delete(transaction)
            try? modelContext.save()
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let currency: String
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: transaction.amount > 0 ? "arrow.down.circle" : "arrow.up.circle")
                        .foregroundColor(transaction.amount > 0 ? .green : .red)
                        .font(.caption)
                    
                    Text(String(format: "%.6f", abs(transaction.amount)))
                        .font(.callout)
                        .fontWeight(.medium)
                    
                    Text(currency)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(dateFormatter.string(from: transaction.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let comment = transaction.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Text(transaction.amount > 0 ? "+" : "")
                .foregroundColor(transaction.amount > 0 ? .green : .red) +
            Text(String(format: "%.4f", transaction.amount))
                .foregroundColor(transaction.amount > 0 ? .green : .red)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}
