//
//  CSVExportShareView.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct CSVExportShareView: View {
    let fileURLs: [URL]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your export contains 3 CSV files:")
                    .font(.headline)
                    .accessibilityIdentifier("csvExportHeader")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fileURLs, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.plaintext")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.body)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("csvFileName-\(url.lastPathComponent)")
                        }
                    }
                }

                ShareLink(items: fileURLs) {
                    Label("Share CSV Files", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("shareCSVFilesButton")
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Export Data")
        }
        .accessibilityIdentifier("csvExportShareView")
    }
}

#Preview {
    CSVExportShareView(fileURLs: [
        URL(fileURLWithPath: "/tmp/goals.csv"),
        URL(fileURLWithPath: "/tmp/assets.csv"),
        URL(fileURLWithPath: "/tmp/value_changes.csv")
    ])
}
