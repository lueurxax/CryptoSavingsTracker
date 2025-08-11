//
//  SettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var monthlySettings = MonthlyPlanningSettings.shared
    @State private var showingMonthlyPlanningSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
            
            Form {
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
                
                Section("Data") {
                    Button("Export Data") {
                        // Export functionality
                    }
                    
                    Button("Import Data") {
                        // Import functionality
                    }
                }
            }
            .formStyle(.grouped)
        }
        .platformPadding()
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showingMonthlyPlanningSettings) {
            MonthlyPlanningSettingsView(goals: [])
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