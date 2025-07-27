    //
    //  AddGoalView.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import SwiftData

struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coinService = CoinGeckoService.shared
    
    @State private var name = ""
    @State private var currency = ""
    @State private var targetAmount = ""
    @State private var deadline = Date().addingTimeInterval(86400 * 30)
    @State private var showingCurrencyPicker = false
    
    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 0) {
                Text("New Goal")
                    .font(.title2)
                    .padding()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Goal Name", text: $name)
                            .padding(.vertical, 4)
                        
                        HStack {
                            Text("Currency:")
                            Spacer()
                            Button {
                                showingCurrencyPicker = true
                            } label: {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        
                        TextField("Target Amount", text: $targetAmount)
                            .padding(.vertical, 4)
                        
                        DatePicker("", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 24)
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
                        saveGoal()
                    }
                    .disabled(!isValidInput)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(minWidth: 450, minHeight: 350)
#else
            NavigationView {
                Form {
                    Section(header: Text("Goal Details")) {
                        TextField("Goal Name", text: $name)
                            .padding(.vertical, 4)
                        
                        HStack {
                            Text("Currency:")
                            Spacer()
                            Button {
                                showingCurrencyPicker = true
                            } label: {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        
                        TextField("Target Amount", text: $targetAmount)
                            .keyboardType(.decimalPad)
                            .padding(.vertical, 4)
                        
                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 8)
                .navigationTitle("New Goal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveGoal()
                        }
                        .disabled(!isValidInput)
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
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(selectedCurrency: $currency)
        }
    }
    
    private var isValidInput: Bool {
        !name.isEmpty && !currency.isEmpty && Double(targetAmount) != nil && Double(targetAmount)! > 0
    }
    
    private func saveGoal() {
        guard let amount = Double(targetAmount) else { return }
        
        let newGoal = Goal(name: name, currency: currency.uppercased(), targetAmount: amount, deadline: deadline)
        modelContext.insert(newGoal)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save goal: \(error)")
        }
        
        NotificationManager.shared.scheduleNotifications(for: newGoal)
        dismiss()
    }
}

#Preview {
    AddGoalView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
