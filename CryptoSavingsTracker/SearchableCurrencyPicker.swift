    //
    //  SearchableCurrencyPicker.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI

struct SearchableCurrencyPicker: View {
    @StateObject private var coinService = CoinGeckoService.shared
    @Binding var selectedCurrency: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var visibleCount: Int = 100
    
    private var filteredAll: [String] {
        if searchText.isEmpty {
            return coinService.coins
        } else {
            return coinService.coins.filter { coin in
                coin.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var filteredCoins: [String] {
        Array(filteredAll.prefix(visibleCount))
    }
    
    private func loadMore() {
        guard visibleCount < filteredAll.count else { return }
        visibleCount = min(visibleCount + 100, filteredAll.count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Header
            HStack {
                Text("Select Currency")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color.clear)
            
            Divider()
            
                // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search currencies...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            
#if os(macOS)
            ScrollView {
                VStack(spacing: 0) {
                        // Current Selection section
                    if !selectedCurrency.isEmpty {
                        Text("Current Selection")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        if coinService.coins.contains(where: { $0.uppercased() == selectedCurrency.uppercased() }) {
                            Button {
                                // Already selected, just dismiss
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(selectedCurrency.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                        // Available Currencies section
                    Text("Available Currencies")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCoins, id: \.self) { coin in
                            Button {
                                selectedCurrency = coin.uppercased()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(coin.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                    if coin.uppercased() == selectedCurrency.uppercased() {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        if visibleCount < filteredAll.count {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .onAppear(perform: loadMore)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
#else
                // Content
            List {
                if !selectedCurrency.isEmpty {
                    Section("Current Selection") {
                        if coinService.coins.contains(where: { $0.uppercased() == selectedCurrency.uppercased() }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(selectedCurrency.uppercased())
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                Section("Available Currencies") {
                    if coinService.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading currencies...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if filteredCoins.isEmpty && !searchText.isEmpty {
                        Text("No currencies found for '\(searchText)'")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredCoins, id: \.self) { coin in
                            Button {
                                selectedCurrency = coin.uppercased()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(coin.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                    if coin.uppercased() == selectedCurrency.uppercased() {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if visibleCount < filteredAll.count {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .onAppear(perform: loadMore)
                                Spacer()
                            }
                        }
                    }
                }
            }
#endif
        }
        .task {
            if coinService.coins.isEmpty {
                await coinService.fetchCoins()
            }
        }
    }
}

#Preview {
    SearchableCurrencyPicker(selectedCurrency: .constant("BTC"))
}
