//
//  EmptyDetailView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData
import Foundation

/// Empty state view for when no goal is selected in detail pane
struct EmptyDetailView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Empty state content
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
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

                    VStack(spacing: 8) {
                        Text("Dashboard is now the main portfolio surface")
                            .font(.headline)
                        Text("Open Dashboard to review overall progress, then select a goal to manage assets and contributions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
