//
//  EmptyDetailView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

/// Empty state view for when no goal is selected in detail pane
struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "sidebar.left")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            // Text content
            VStack(spacing: 8) {
                Text("Select a Goal")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose a goal from the sidebar to view its details and progress")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyDetailView()
}