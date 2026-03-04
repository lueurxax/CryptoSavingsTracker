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
    @State private var exportResult: CSVExportResult?
    @State private var exportErrorMessage: String?
    @State private var showingExportError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    Button {
                        do {
                            let urls = try CSVExportService.exportCSVFiles(using: modelContext)
                            exportResult = CSVExportResult(fileURLs: urls)
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

                Section("Monthly Planning") {
                    SettingsSectionRow(
                        title: "Display Currency",
                        systemImage: "dollarsign.circle",
                        value: monthlySettings.displayCurrency,
                        accessibilityIdentifier: "settings.section_row"
                    )

                    SettingsSectionRow(
                        title: "Payment Day",
                        systemImage: "calendar",
                        value: "\(monthlySettings.paymentDay)\(monthlySettings.paymentDay.ordinalSuffix) of month",
                        accessibilityIdentifier: "settings.section_row.payment_day"
                    )

                    SettingsSectionRow(
                        title: "Next Payment",
                        systemImage: "clock",
                        value: "\(monthlySettings.daysUntilPayment) days",
                        accessibilityIdentifier: "settings.section_row.next_payment"
                    )
                    
                    Button("Configure Monthly Planning") {
                        showingMonthlyPlanningSettings = true
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
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingMonthlyPlanningSettings) {
            MonthlyPlanningSettingsView(goals: [])
        }
        // NAV-MOD: MOD-01
        .sheet(item: $exportResult) { result in
            CSVExportShareView(fileURLs: result.fileURLs)
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
    }
}

private struct SettingsSectionRow: View {
    let title: String
    let systemImage: String
    let value: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius)
                .fill(VisualComponentTokens.settingsRowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius)
                .stroke(VisualComponentTokens.financeSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius))
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(accessibilityIdentifier)
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

// MARK: - CSV Export Result

/// Wrapper for sheet(item:) presentation to ensure URLs are passed correctly
struct CSVExportResult: Identifiable {
    let id = UUID()
    let fileURLs: [URL]
}
