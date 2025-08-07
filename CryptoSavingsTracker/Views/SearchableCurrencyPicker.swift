    //
    //  SearchableCurrencyPicker.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI

enum CurrencyPickerType {
    case fiat // For goals - shows fiat currencies like USD, EUR
    case crypto // For assets - shows crypto currencies like BTC, ETH
}

struct SearchableCurrencyPicker: View {
    @StateObject private var currencyViewModel = CurrencyViewModel()
    @Binding var selectedCurrency: String
    @Environment(\.dismiss) private var dismiss
    
    let pickerType: CurrencyPickerType
    
    @State private var searchText = ""
    @State private var visibleCount: Int = 100
    
    init(selectedCurrency: Binding<String>, pickerType: CurrencyPickerType = .crypto) {
        self._selectedCurrency = selectedCurrency
        self.pickerType = pickerType
    }
    
    private var filteredAll: [CoinInfo] {
        if pickerType == .fiat {
            // For fiat currencies, we need to create fake CoinInfo objects from the strings
            let fiatList = currencyViewModel.supportedCurrencies.map { currency in
                CoinInfo(id: currency.lowercased(), symbol: currency, name: currency)
            }
            
            if searchText.isEmpty {
                return fiatList
            } else {
                return fiatList.filter { coin in
                    coin.symbol.localizedCaseInsensitiveContains(searchText)
                }
            }
        } else {
            // For crypto currencies, use the existing logic
            if searchText.isEmpty {
                return currencyViewModel.coinInfos
            } else {
                return currencyViewModel.coinInfos.filter { coin in
                    coin.symbol.localizedCaseInsensitiveContains(searchText) ||
                    coin.name.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    private var filteredCoins: [CoinInfo] {
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
                Text(pickerType == .fiat ? "Select Goal Currency" : "Select Asset Currency")
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
                TextField(pickerType == .fiat ? "Search fiat currencies..." : "Search cryptocurrencies...", text: $searchText)
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
                        if let selectedCoin = currencyViewModel.coinInfos.first(where: { $0.symbol.uppercased() == selectedCurrency.uppercased() }) {
                            Button {
                                // Already selected, just dismiss
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(selectedCoin.symbol.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(selectedCoin.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
                    Text(pickerType == .fiat ? "Available Fiat Currencies" : "Available Cryptocurrencies")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCoins, id: \.id) { coin in
                            Button {
                                selectedCurrency = coin.symbol.uppercased()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(coin.symbol.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(coin.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if coin.symbol.uppercased() == selectedCurrency.uppercased() {
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
                        if let selectedCoin = currencyViewModel.coinInfos.first(where: { $0.symbol.uppercased() == selectedCurrency.uppercased() }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(selectedCoin.symbol.uppercased())
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(selectedCoin.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                Section(pickerType == .fiat ? "Available Fiat Currencies" : "Available Cryptocurrencies") {
                    if currencyViewModel.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading currencies...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if filteredCoins.isEmpty && !searchText.isEmpty {
                        EmptyStateView.noSearchResults(query: searchText, onClearSearch: {
                            searchText = ""
                        })
                        .frame(height: 200)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(filteredCoins, id: \.id) { coin in
                            Button {
                                selectedCurrency = coin.symbol.uppercased()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(coin.symbol.uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(coin.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if coin.symbol.uppercased() == selectedCurrency.uppercased() {
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
            if pickerType == .fiat {
                if currencyViewModel.supportedCurrencies.isEmpty {
                    await currencyViewModel.fetchSupportedCurrencies()
                }
            } else {
                if currencyViewModel.coinInfos.isEmpty {
                    await currencyViewModel.fetchCoins()
                }
            }
        }
    }
}

#Preview {
    SearchableCurrencyPicker(selectedCurrency: .constant("BTC"))
}
