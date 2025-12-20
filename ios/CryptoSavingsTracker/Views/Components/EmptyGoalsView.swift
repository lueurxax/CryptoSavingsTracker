//
//  EmptyGoalsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

struct EmptyGoalsView: View {
    let onCreateGoal: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            // Text content
            VStack(spacing: 8) {
                Text("No Savings Goals Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Create your first cryptocurrency savings goal to start tracking your progress")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Action button
            Button(action: onCreateGoal) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Your First Goal")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.blue)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyGoalsView(onCreateGoal: {})
}