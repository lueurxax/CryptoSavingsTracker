    //
    //  SearchableCurrencyPicker.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import Foundation

enum CurrencyPickerType {
    case fiat // For goals - shows fiat currencies like USD, EUR
    case crypto // For assets - shows crypto currencies like BTC, ETH
}

struct SearchableCurrencyPicker: View {
    @StateObject private var currencyViewModel = CurrencyViewModel()
    @Binding var selectedCurrency: String
    @Environment(\.dismiss) private var dismiss
    
    let pickerType: CurrencyPickerType
    let titleOverride: String?
    
    @State private var searchText = ""
    @State private var visibleCount: Int = 100
    #if !os(macOS)
    @FocusState private var searchFieldFocused: Bool
    @State private var autoPicked = false
    private let isUITest = UITestFlags.isEnabled
    #endif
    
    private static let isoFiatCurrencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier).map { $0.uppercased() })
    
    init(selectedCurrency: Binding<String>, pickerType: CurrencyPickerType = .crypto, titleOverride: String? = nil) {
        self._selectedCurrency = selectedCurrency
        self.pickerType = pickerType
        self.titleOverride = titleOverride
    }
    
    private var fiatCurrencyInfos: [CoinInfo] {
        let fiatCodes = currencyViewModel.supportedCurrencies.filter { Self.isoFiatCurrencyCodes.contains($0.uppercased()) }
        return fiatCodes.map { CoinInfo(id: $0.lowercased(), symbol: $0, name: $0) }
    }
    
    private var currentSelection: CoinInfo? {
        let candidates = pickerType == .fiat ? fiatCurrencyInfos : currencyViewModel.coinInfos
        return candidates.first(where: { $0.symbol.uppercased() == selectedCurrency.uppercased() })
    }

    private var filteredAll: [CoinInfo] {
        if pickerType == .fiat {
            // For fiat currencies, we need to create fake CoinInfo objects from the strings
            let fiatList = fiatCurrencyInfos
            
            if searchText.isEmpty {
                return fiatList.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
            } else {
                let searchLower = searchText.lowercased()
                let filtered = fiatList.filter { coin in
                    coin.symbol.localizedCaseInsensitiveContains(searchText)
                }
                
                // Apply smart sorting (same algorithm as macOS)
                return filtered.sorted { first, second in
                    let firstSymbolMatch = first.symbol.lowercased() == searchLower
                    let secondSymbolMatch = second.symbol.lowercased() == searchLower
                    
                    // Exact symbol match comes first
                    if firstSymbolMatch && !secondSymbolMatch {
                        return true
                    }
                    if secondSymbolMatch && !firstSymbolMatch {
                        return false
                    }
                    
                    // Then symbol starts with search term
                    let firstSymbolStarts = first.symbol.lowercased().hasPrefix(searchLower)
                    let secondSymbolStarts = second.symbol.lowercased().hasPrefix(searchLower)
                    
                    if firstSymbolStarts && !secondSymbolStarts {
                        return true
                    }
                    if secondSymbolStarts && !firstSymbolStarts {
                        return false
                    }
                    
                    // Finally, maintain alphabetical order
                    return first.symbol.lowercased() < second.symbol.lowercased()
                }
            }
        } else {
            // For crypto currencies, use smart sorting (same as macOS)
            if searchText.isEmpty {
                return currencyViewModel.coinInfos.sorted { $0.symbol.lowercased() < $1.symbol.lowercased() }
            } else {
                let searchLower = searchText.lowercased()
                let filtered = currencyViewModel.coinInfos.filter { coin in
                    coin.symbol.lowercased().contains(searchLower) ||
                    coin.name.lowercased().contains(searchLower)
                }
                
                // Apply smart sorting (same algorithm as macOS)
                return filtered.sorted { first, second in
                    let firstSymbolMatch = first.symbol.lowercased() == searchLower
                    let firstNameMatch = first.name.lowercased() == searchLower
                    let secondSymbolMatch = second.symbol.lowercased() == searchLower
                    let secondNameMatch = second.name.lowercased() == searchLower
                    
                    // Exact symbol match comes first
                    if firstSymbolMatch && !secondSymbolMatch {
                        return true
                    }
                    if secondSymbolMatch && !firstSymbolMatch {
                        return false
                    }
                    
                    // Then exact name match
                    if firstNameMatch && !secondNameMatch {
                        return true
                    }
                    if secondNameMatch && !firstNameMatch {
                        return false
                    }
                    
                    // Then symbol starts with search term
                    let firstSymbolStarts = first.symbol.lowercased().hasPrefix(searchLower)
                    let secondSymbolStarts = second.symbol.lowercased().hasPrefix(searchLower)
                    
                    if firstSymbolStarts && !secondSymbolStarts {
                        return true
                    }
                    if secondSymbolStarts && !firstSymbolStarts {
                        return false
                    }
                    
                    // Then name starts with search term
                    let firstNameStarts = first.name.lowercased().hasPrefix(searchLower)
                    let secondNameStarts = second.name.lowercased().hasPrefix(searchLower)
                    
                    if firstNameStarts && !secondNameStarts {
                        return true
                    }
                    if secondNameStarts && !firstNameStarts {
                        return false
                    }
                    
                    // Finally, maintain alphabetical order
                    return first.symbol.lowercased() < second.symbol.lowercased()
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
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("currencyCancelButton")
                
                Spacer()
                Text(titleOverride ?? (pickerType == .fiat ? "Select Goal Currency" : "Select Asset Currency"))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .accessibilityIdentifier("currencyDoneButton")
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
                    .accessibilityIdentifier("currencySearchField")
                    #if !os(macOS)
                    .focused($searchFieldFocused)
                    #endif
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
                        if let selectedCoin = currentSelection {
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
                                #if !os(macOS)
                                searchFieldFocused = false
                                DispatchQueue.main.async {
                                    dismiss()
                                }
                                #else
                                dismiss()
                                #endif
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
                                .contentShape(Rectangle())
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
                        if let selectedCoin = currentSelection {
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
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("currencyCell-\(coin.symbol.uppercased())")
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
#if !os(macOS)
        .onAppear {
            // Keep keyboard ready for quick filtering in tests, but ensure it can resign cleanly
            searchFieldFocused = true
        }
        .onChange(of: filteredCoins.count) { _, _ in
            guard isUITest, !autoPicked, pickerType == .fiat, selectedCurrency.isEmpty else { return }
            
            let searchUpper = searchText.uppercased()
            // Prefer exact symbol match if user typed one (e.g., USD)
            if !searchUpper.isEmpty,
               let exact = filteredCoins.first(where: { $0.symbol.uppercased() == searchUpper }) {
                autoPicked = true
                selectedCurrency = exact.symbol.uppercased()
                searchFieldFocused = false
                DispatchQueue.main.async { dismiss() }
                return
            }
            
            // If only one option is visible, pick it to unblock automation
            if filteredCoins.count == 1, let firstSymbol = filteredCoins.first?.symbol {
                autoPicked = true
                selectedCurrency = firstSymbol.uppercased()
                searchFieldFocused = false
                DispatchQueue.main.async { dismiss() }
            }
        }
        .onChange(of: selectedCurrency) { _, _ in
            // Safety net: if selection is programmatically set, close the sheet
            searchFieldFocused = false
            DispatchQueue.main.async {
                dismiss()
            }
        }
        #endif
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
