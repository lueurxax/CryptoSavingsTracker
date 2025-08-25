//
//  AllocationPromptBanner.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct AllocationPromptBanner: View {
    let asset: Asset
    let onManageAllocations: () -> Void
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asset Added Successfully")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text("You can share \(asset.currency) with other goals")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: onManageAllocations) {
                        Text("Manage")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { 
                        withAnimation(.easeOut(duration: 0.3)) {
                            isVisible = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .imageScale(.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .shadow(radius: 2)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}