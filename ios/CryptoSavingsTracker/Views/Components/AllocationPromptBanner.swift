//
//  AllocationPromptBanner.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct AllocationPromptBanner: View {
    let asset: Asset
    @Binding var isVisible: Bool
    @State private var showingAllocationView = false
    
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
                    
                    Button(action: {
                        showingAllocationView = true
                    }) {
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
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: isVisible)
            .onAppear {
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
            .sheet(isPresented: $showingAllocationView) {
                AssetSharingView(asset: asset)
            }
        }
    }
}