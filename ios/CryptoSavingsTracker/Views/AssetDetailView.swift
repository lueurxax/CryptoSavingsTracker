//
//  AssetDetailView.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftUI
import SwiftData
import Foundation

struct AssetDetailView: View {
    private static let isoFiatCurrencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier).map { $0.uppercased() })

    let asset: Asset
    
    @State private var currentBalance: Double = 0
    @State private var isLoadingBalance = false
    @State private var balanceError: String?
    @State private var showingAddTransaction = false
    @State private var showingAllocationView = false
    @State private var showingTransactionHistory = false

    private var hasOnChainTracking: Bool {
        if let address = asset.address, let chainId = asset.chainId {
            return !address.isEmpty && !chainId.isEmpty
        }
        return false
    }

    private var publicCryptoTrackingStatus: BalanceState.CryptoTrackingStatus? {
        guard hasOnChainTracking else { return nil }
        let balanceState: BalanceState
        if isLoadingBalance {
            balanceState = .loading
        } else if let balanceError {
            balanceState = .error(
                message: balanceError,
                cachedBalance: asset.cachedOnChainBalance > 0 ? asset.cachedOnChainBalance : nil,
                lastUpdated: nil
            )
        } else {
            let onChainPortion = max(currentBalance - asset.manualBalance, 0)
            balanceState = .loaded(
                balance: onChainPortion,
                isCached: false,
                lastUpdated: Date()
            )
        }

        return balanceState.publicCryptoTrackingStatus(
            isRefreshing: isLoadingBalance,
            hasRetainedValue: asset.cachedOnChainBalance > 0 || currentBalance > asset.manualBalance
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                // Balance Section
                balanceSection
                
                // Asset Information
                assetInfoSection
                
                // Recent Transactions
                recentTransactionsSection
                
                // Actions
                actionButtons
            }
            .padding()
        }
        .navigationTitle(asset.currency)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationDestination(isPresented: $showingTransactionHistory) {
            TransactionHistoryView(asset: asset)
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(asset: asset)
        }
        .task {
            await loadBalance()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(asset.currency)
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(asset.currency)
                    .font(.title2)
                    .foregroundStyle(AccessibleColors.secondaryText)
            }
            
            if let address = asset.address {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(AccessibleColors.surfaceSubtle)
        .cornerRadius(12)
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Balance")
                .font(.headline)
                .foregroundStyle(AccessibleColors.secondaryText)

            if let publicCryptoTrackingStatus {
                Label(publicCryptoTrackingStatus.title, systemImage: publicCryptoTrackingStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.secondaryText)
            }
            
            if isLoadingBalance {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = balanceError {
                Text(error)
                    .foregroundStyle(AccessibleColors.error)
                    .font(.caption)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.6f", currentBalance))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text(asset.currency)
                        .font(.title3)
                        .foregroundStyle(AccessibleColors.secondaryText)
                }
            }
        }
        .padding()
        .background(AccessibleColors.surfaceBase)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asset Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                AdaptiveSummaryRow(label: "Type", value: assetTypeLabel)
                AdaptiveSummaryRow(label: "Currency", value: asset.currency)
                
                if asset.address != nil && asset.chainId != nil {
                    if let chainId = asset.chainId {
                        AdaptiveSummaryRow(label: "Chain", value: chainId)
                    }
                    if let address = asset.address {
                        AdaptiveSummaryRow(
                            label: "Address",
                            value: address,
                            valueLineLimit: 1,
                            valueTruncationMode: .middle
                        )
                    }
                } else {
                    AdaptiveSummaryRow(label: "Manual Balance", value: String(format: "%.6f", asset.manualBalance))
                }
            }
        }
        .padding()
        .background(AccessibleColors.surfaceSubtle)
        .cornerRadius(12)
    }

    private var assetTypeLabel: String {
        if let address = asset.address,
           let chainId = asset.chainId,
           !address.isEmpty,
           !chainId.isEmpty {
            return "On-Chain"
        }
        let isFiat = Self.isoFiatCurrencyCodes.contains(asset.currency.uppercased())
        return isFiat ? "Fiat (Manual)" : "Manual"
    }
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                
                Spacer()
                
                Button("View All") {
                    showingTransactionHistory = true
                }
                .font(.caption)
            }
            
            if (asset.transactions ?? []).isEmpty {
                Text("No transactions yet")
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach((asset.transactions ?? []).prefix(3)) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(String(format: "%.6f %@", transaction.amount, asset.currency))
                                    .font(.callout)
                                    .foregroundStyle(transaction.amount >= 0 ? AccessibleColors.success : AccessibleColors.error)
                                
                                Text(transaction.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            if let comment = transaction.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption)
                                    .foregroundStyle(AccessibleColors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if transaction != (asset.transactions ?? []).prefix(3).last {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(AccessibleColors.surfaceSubtle)
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                showingAddTransaction = true
            }) {
                Label("Add Transaction", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                showingAllocationView = true
            }) {
                Label("Manage Allocations", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AccessibleColors.secondaryInteractive)
        }
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingAllocationView) {
            AssetSharingView(asset: asset)
        }
    }
    
    private func loadBalance() async {
        guard asset.address != nil && asset.chainId != nil,
              let chainId = asset.chainId,
              let address = asset.address else {
            currentBalance = asset.manualBalance
            return
        }
        
        isLoadingBalance = true
        balanceError = nil
        
        do {
            let tatumService = TatumService(client: TatumClient.shared, chainService: ChainService.shared)
            let balance = try await tatumService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency
            )
            
            await MainActor.run {
                currentBalance = balance
                isLoadingBalance = false
            }
        } catch {
            await MainActor.run {
                balanceError = error.localizedDescription
                currentBalance = max(asset.currentAmount, asset.manualBalance)
                isLoadingBalance = false
            }
        }
    }
}
