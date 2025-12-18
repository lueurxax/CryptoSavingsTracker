//
//  SettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var monthlySettings = MonthlyPlanningSettings.shared
    @State private var showingMonthlyPlanningSettings = false
    @State private var showingExportShare = false
    @State private var exportFileURLs: [URL] = []
    @State private var exportErrorMessage: String?
    @State private var showingExportError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    Button {
                        do {
                            exportFileURLs = try CSVExportService.exportCSVFiles(using: modelContext)
                            showingExportShare = true
                        } catch {
                            exportErrorMessage = error.localizedDescription
                            showingExportError = true
                        }
                    } label: {
                        Text("Export Data (CSV)")
                            .accessibilityIdentifier("exportCSVButton")
                    }
                    .accessibilityIdentifier("exportCSVButton")
                    
                    Button("Import Data") {
                        // Import functionality
                    }
                }
                
                Section("General") {
                    Toggle("Show progress notifications", isOn: .constant(true))
                    Toggle("Auto-refresh exchange rates", isOn: .constant(true))
                }
                
                Section("Monthly Planning") {
                    HStack {
                        Label("Display Currency", systemImage: "dollarsign.circle")
                        Spacer()
                        Text(monthlySettings.displayCurrency)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Payment Day", systemImage: "calendar")
                        Spacer()
                        Text("\(monthlySettings.paymentDay)\(monthlySettings.paymentDay.ordinalSuffix) of month")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Next Payment", systemImage: "clock")
                        Spacer()
                        Text("\(monthlySettings.daysUntilPayment) days")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Configure Monthly Planning") {
                        showingMonthlyPlanningSettings = true
                    }
                }
                
                Section("Display") {
                    Picker("Currency Format", selection: .constant("Symbol")) {
                        Text("Symbol ($)").tag("Symbol")
                        Text("Code (USD)").tag("Code")
                    }
                    
                    Picker("Number Format", selection: .constant("Default")) {
                        Text("1,234.56").tag("Default")
                        Text("1.234,56").tag("European")
                    }
                }
            }
            .accessibilityIdentifier("settingsForm")
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("dismissSettingsButton")
                }
            }
            #endif
        }
        #if os(macOS)
        .platformPadding()
        .frame(width: 500, height: 400)
        #endif
        .sheet(isPresented: $showingMonthlyPlanningSettings) {
            MonthlyPlanningSettingsView(goals: [])
        }
        .sheet(isPresented: $showingExportShare) {
            CSVExportShareView(fileURLs: exportFileURLs)
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Extensions

private extension Int {
    var ordinalSuffix: String {
        switch self % 100 {
        case 11...13:
            return "th"
        default:
            switch self % 10 {
            case 1: return "st"
            case 2: return "nd"  
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}

#Preview {
    SettingsView()
}
