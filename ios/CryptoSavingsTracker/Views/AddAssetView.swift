    //
    //  AddAssetView.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import SwiftData

struct AddAssetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyViewModel = CurrencyViewModel()
    private let tatumService = TatumService(client: TatumClient.shared, chainService: ChainService.shared)
    
    let goal: Goal
    
    @State private var currency = ""
    @State private var address = ""
    @State private var chainId: String? = nil
    @State private var predictedChain: TatumChain?
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showingHelp = false
    @State private var showingCurrencyPicker = false
    @State private var currencySearchText = ""
    
    // Form validation state
    @State private var hasAttemptedSubmit = false
    @State private var currencyFieldTouched = false
    @State private var addressFieldTouched = false

    private var isUITestFlow: Bool {
        UITestFlags.isEnabled
    }
    
    // Computed validation properties
    private var showCurrencyError: Bool {
        (hasAttemptedSubmit || currencyFieldTouched) && currency.isEmpty
    }
    
    private var showChainError: Bool {
        (hasAttemptedSubmit || addressFieldTouched) && !address.isEmpty && predictedChain == nil && chainId == nil
    }
    
    private var isFormValid: Bool {
        !currency.isEmpty && (address.isEmpty || predictedChain != nil || chainId != nil)
    }
    
    private var filteredCurrencies: [CoinInfo] {
        if currencySearchText.isEmpty {
            return currencyViewModel.coinInfos
        }
        
        let searchLower = currencySearchText.lowercased()
        let filtered = currencyViewModel.coinInfos.filter { coin in
            coin.symbol.lowercased().contains(searchLower) ||
            coin.name.lowercased().contains(searchLower)
        }
        
        // Sort with exact matches first
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
    
    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 16) {
                Text("New Asset")
                    .font(.title2)
                    .padding(.top)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // MARK: Error banner
                        if let errorMessage = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.accessibleStreak)
                                Text(errorMessage)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Dismiss") { self.errorMessage = nil }
                                    .font(.caption)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .padding(12)
                            .background(AccessibleColors.streakBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                        }

                        // MARK: Currency picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Currency:")
                                Text("*").foregroundColor(.red)
                                Spacer()
                                Button(action: { showingHelp = true }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Show help about asset tracking types")
                                Button(action: { 
                                    currencyFieldTouched = true
                                    showingCurrencyPicker = true 
                                }) {
                                    HStack {
                                        Text(currency.isEmpty ? "Select Currency" : currency)
                                            .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(.plain)
                            }
                            if showCurrencyError {
                                Text("Please select a currency")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // MARK: On-chain tracking
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Address:")
                            HStack {
                                TextField(
                                    addressPlaceholder,
                                    text: $address
                                )
                                .textFieldStyle(.roundedBorder)
                                .disableAutocorrection(true)
                                .frame(maxWidth: 300)
                                .onTapGesture {
                                    addressFieldTouched = true
                                }
                                .onChange(of: address) { _, _ in
                                    addressFieldTouched = true
                                }
                            }

                            if !address.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Chain:")
                                    Picker("Chain", selection: Binding(
                                        get: { predictedChain?.id ?? chainId ?? "" },
                                        set: { newValue in
                                            if newValue.isEmpty {
                                                chainId = nil
                                            } else {
                                                chainId = newValue
                                                predictedChain = nil
                                            }
                                        }
                                    )) {
                                        Text("Select Chain").tag("")
                                        ForEach(tatumService.supportedChains) { chain in
                                            Text("\(chain.name) (\(chain.nativeCurrencySymbol))")
                                                .tag(chain.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(minWidth: 200)

                                    if showChainError {
                                        Text("Please select a blockchain network")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }

                        // MARK: Footer note
                        Text("This asset will be tracked against your goal of \(goal.targetAmount, specifier: "%.2f") \(goal.currency).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 8)

                Divider()

                // MARK: Action buttons
                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        Task { await saveAsset() }
                    } label: {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValidInput || isLoading)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .frame(minWidth: 500, minHeight: 450)
            .popover(isPresented: $showingCurrencyPicker) {
                VStack(spacing: 0) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search currencies...", text: $currencySearchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(12)
                    
                    Divider()
                    
                    // Currency list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredCurrencies, id: \.id) { coin in
                                Button(action: {
                                    currency = coin.symbol.uppercased()
                                    showingCurrencyPicker = false
                                    currencySearchText = ""
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(coin.symbol.uppercased())
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.primary)
                                            Text(coin.name)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if coin.symbol.uppercased() == currency {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accessiblePrimary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(coin.symbol.uppercased() == currency ? AccessibleColors.primaryInteractiveBackground : Color.clear)
                                
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
                .frame(width: 350, height: 450)
            }
#else
            NavigationView {
                Form {
                    // Error Message Section
                    if let errorMessage = errorMessage {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.accessibleStreak)
                                VStack(alignment: .leading) {
                                    Text(errorMessage)
                                        .foregroundColor(.primary)
                                    Button("Dismiss") {
                                        self.errorMessage = nil
                                    }
                                    .font(.caption)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(AccessibleColors.streakBackground)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    Section(header: HStack {
                        Text("Asset Details")
                        Spacer()
                        Button(action: { showingHelp = true }) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Show help about asset tracking types")
                    }) {
                        HStack {
                            Text("Currency:")
                                .accessibilityLabel("Currency selection")
                            Text("*")
                                .foregroundColor(.red)
                                .accessibilityHidden(true)
                            Spacer()
                            Button(action: { 
                                currencyFieldTouched = true
                                showingCurrencyPicker = true 
                            }) {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityIdentifier("assetCurrencyButton")
                            .accessibilityLabel(currency.isEmpty ? "Select currency required" : "Selected currency \(currency)")
                            .accessibilityHint("Tap to choose a cryptocurrency")
                        }
                        .padding(.vertical, 4)

                        #if os(iOS)
                        if isUITestFlow {
                            TextField("Currency (Test)", text: $currency)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .accessibilityIdentifier("assetCurrencyOverrideField")
                                .padding(.vertical, 4)
                        }
                        #endif

                        if showCurrencyError {
                            Text("Please select a currency")
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityLabel("Validation error: Please select a currency")
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    Section(header: HStack {
                        Text("On-Chain Tracking")
                        Text("(Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }, footer: VStack(alignment: .leading, spacing: 4) {
                        Text("Add a blockchain address to automatically track balance and transactions.")
                        if !address.isEmpty {
                            Text("Format: \(addressFormatHint)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }) {
                        HStack {
                            Text("Address:")
                                .accessibilityLabel("Blockchain address")
                            Spacer()
                            TextField(addressPlaceholder, text: $address)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .frame(maxWidth: 200)
                                .accessibilityIdentifier("assetAddressField")
                                .accessibilityLabel("Blockchain address input")
                                .accessibilityHint("Enter your blockchain address for automatic tracking, or leave empty for manual tracking only")
                                .onTapGesture {
                                    addressFieldTouched = true
                                }
                                .onChange(of: address) { _, _ in
                                    addressFieldTouched = true
                                }
                        }
                        .padding(.vertical, 4)
                        
                        if !address.isEmpty {
                            HStack {
                                Text("Chain:")
                                    .accessibilityLabel("Blockchain network")
                                Spacer()
                                
                                Picker("Chain", selection: Binding(
                                    get: { predictedChain?.id ?? chainId ?? "" },
                                    set: { newValue in
                                        if newValue.isEmpty {
                                            chainId = nil
                                        } else {
                                            chainId = newValue
                                            predictedChain = nil
                                        }
                                    }
                                )) {
                                    Text("Select Chain").tag("")
                                    ForEach(tatumService.supportedChains.filter { $0.chainType == .evm }) { chain in
                                        Text("\(chain.name) (\(chain.nativeCurrencySymbol))").tag(chain.id)
                                    }
                                    ForEach(tatumService.supportedChains.filter { $0.chainType == .utxo }) { chain in
                                        Text("\(chain.name) (\(chain.nativeCurrencySymbol))").tag(chain.id)
                                    }
                                    ForEach(tatumService.supportedChains.filter { $0.chainType == .other }) { chain in
                                        Text("\(chain.name) (\(chain.nativeCurrencySymbol))").tag(chain.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(minWidth: 150)
                                .accessibilityLabel(chainId == nil ? "Select blockchain network required" : "Selected blockchain network")
                                .accessibilityHint("Choose which blockchain network this address belongs to")
                            }
                            .padding(.vertical, 4)
                            
                            if showChainError {
                                Text("Please select a blockchain network")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityLabel("Validation error: Please select a blockchain network")
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    Section(footer: Text("This asset will be tracked against your goal of \(goal.targetAmount, specifier: "%.2f") \(goal.currency).")) {
                        EmptyView()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 8)
                .navigationTitle("New Asset")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task { await saveAsset() }
                        }) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(!isValidInput || isLoading)
                        .accessibilityIdentifier("saveAssetButton")
                        .accessibilityLabel(isValidInput ? "Save asset" : "Save disabled: \(validationMessage)")
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { isUITestFlow && showingCurrencyPicker },
                set: { newValue in
                    if isUITestFlow {
                        showingCurrencyPicker = newValue
                    }
                }
            )) {
                SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
            }
            .sheet(isPresented: Binding(
                get: { !isUITestFlow && showingCurrencyPicker },
                set: { newValue in
                    if !isUITestFlow {
                        showingCurrencyPicker = newValue
                    }
                }
            )) {
                SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .crypto)
            }
#endif
        }
        .task {
            if currencyViewModel.coinInfos.isEmpty {
                await currencyViewModel.fetchCoins()
            }
        }
        .onChange(of: currency) { _, newValue in
            if !newValue.isEmpty {
                predictChainForCurrency()
            } else {
                predictedChain = nil
                chainId = nil
            }
        }
        .alert("Asset Tracking Help", isPresented: $showingHelp) {
            Button("Got it") { }
        } message: {
            Text("Manual tracking: Add transactions yourself for assets you hold offline or in wallets.\n\nOn-chain tracking: Automatically monitor blockchain addresses for balance and transaction updates.\n\nYou can use both methods for the same asset.")
        }
    }
    
    private var isValidInput: Bool {
        isFormValid
    }
    
    private var validationMessage: String {
        if currency.isEmpty {
            return "Please select a cryptocurrency"
        }
        if !address.isEmpty && predictedChain == nil && chainId == nil {
            return "Please select a blockchain network for the address"
        }
        return ""
    }
    
    private var addressPlaceholder: String {
        guard let predicted = predictedChain else {
            return "Enter blockchain address"
        }
        
        switch predicted.chainType {
        case .evm:
            return "0x1234...abcd (40 characters)"
        case .utxo:
            if predicted.id == "bitcoin-mainnet" {
                return "bc1... or 1... or 3... format"
            } else {
                return "Legacy or segwit format"
            }
        case .other:
            if predicted.id == "tron-mainnet" {
                return "T... (34 characters)"
            } else if predicted.id == "solana-mainnet" {
                return "Base58 encoded (32-44 chars)"
            } else {
                return "Network-specific format"
            }
        }
    }
    
    private var addressFormatHint: String {
        guard let predicted = predictedChain else { return "Varies by network" }
        
        switch predicted.chainType {
        case .evm:
            return "Ethereum-style addresses (0x...)"
        case .utxo:
            return predicted.id == "bitcoin-mainnet" ? "Bitcoin address formats" : "UTXO-based address"
        case .other:
            return "\(predicted.name) native format"
        }
    }
    
    private func saveAsset() async {
        await MainActor.run {
            hasAttemptedSubmit = true
            isLoading = true
            errorMessage = nil
        }
        
        // Early validation check
        guard isFormValid else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        print("💾 AddAssetView.saveAsset() called")
        print("   Goal: \(goal.name)")
        print("   Currency: \(currency.uppercased())")
        print("   Address: \(address)")
        print("   ChainId: \(predictedChain?.id ?? chainId ?? "none")")
        
        let finalAddress = address.isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalChainId = predictedChain?.id ?? chainId
        
        // Validate address format if provided
        if let addr = finalAddress, let chainId = finalChainId {
            if !isValidAddress(addr, for: chainId) {
                await MainActor.run {
                    errorMessage = "Invalid address format for selected blockchain network. Please check the address and try again."
                    isLoading = false
                }
                return
            }
        }
        
        do {
            let newAsset = Asset(
                currency: currency.uppercased(),
                address: finalAddress,
                chainId: finalChainId
            )
            
            modelContext.insert(newAsset)
            
            // Create a dedicated allocation record for this asset to the goal.
            // Start at current balance (typically 0) and auto-expand on deposits while fully allocated.
            let allocation = AssetAllocation(asset: newAsset, goal: goal, amount: newAsset.currentAmount)
            modelContext.insert(allocation)

            // Ensure relationship collections update immediately (SwiftData may not back-propagate without explicit inverse).
            if !goal.allocations.contains(where: { $0.id == allocation.id }) {
                goal.allocations.append(allocation)
            }
            if !newAsset.allocations.contains(where: { $0.id == allocation.id }) {
                newAsset.allocations.append(allocation)
            }

            // Record initial allocation state for execution tracking.
            modelContext.insert(AllocationHistory(asset: newAsset, goal: goal, amount: allocation.amountValue))
            
            try modelContext.save()
            
            print("✅ Asset saved successfully with 100% allocation to goal")
            print("   Goal allocations count after save: \(goal.allocations.count)")
            
            await MainActor.run {
                isLoading = false
            }
            
            dismiss()
        } catch {
            print("❌ Asset saving failed: \(error)")
            
            await MainActor.run {
                errorMessage = "Unable to save your asset right now. Please check your connection and try again."
                isLoading = false
            }
        }
    }
    
    private func isValidAddress(_ address: String, for chainId: String) -> Bool {
        // Basic validation - in a real app, you'd want more sophisticated validation
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get chain info
        guard let chain = tatumService.supportedChains.first(where: { $0.id == chainId }) else {
            return false
        }
        
        switch chain.chainType {
        case .evm:
            // Ethereum-style addresses start with 0x and are 42 characters total
            return trimmedAddress.hasPrefix("0x") && trimmedAddress.count == 42
        case .utxo:
            if chainId == "bitcoin-mainnet" {
                // Bitcoin addresses can be legacy (1...), script (3...), or bech32 (bc1...)
                return trimmedAddress.hasPrefix("1") || trimmedAddress.hasPrefix("3") || trimmedAddress.hasPrefix("bc1")
            }
            return trimmedAddress.count > 20 // Basic length check for other UTXO chains
        case .other:
            if chainId == "tron-mainnet" {
                // Tron addresses start with T and are 34 characters
                return trimmedAddress.hasPrefix("T") && trimmedAddress.count == 34
            } else if chainId == "solana-mainnet" {
                // Solana addresses are base58 encoded, typically 32-44 characters
                return trimmedAddress.count >= 32 && trimmedAddress.count <= 44
            }
            return trimmedAddress.count > 10 // Basic validation for other chains
        }
    }
    
    private func predictChainForCurrency() {
        let predicted = tatumService.predictChain(for: currency)
        if predicted != nil {
            predictedChain = predicted
            chainId = nil
        } else {
            predictedChain = nil
        }
    }
}


#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    container.mainContext.insert(goal)
    
    return AddAssetView(goal: goal)
        .modelContainer(container)
}
