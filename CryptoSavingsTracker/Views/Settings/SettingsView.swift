//
//  SettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

struct SettingsView: View {
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
    }
}

#Preview {
    SettingsView()
}