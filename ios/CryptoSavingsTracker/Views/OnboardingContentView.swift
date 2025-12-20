//
//  OnboardingContentView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
import SwiftData

/// Main coordinator that decides whether to show onboarding or the main app
struct OnboardingContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingFlowView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
            } else {
                ContentView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.1)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: shouldShowOnboarding)
        .onAppear {
            checkOnboardingStatus()
        }
        .onChange(of: onboardingManager.hasCompletedOnboarding) { oldValue, newValue in
            if newValue && shouldShowOnboarding {
                // Add small delay for smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showOnboarding = false
                    }
                }
            }
        }
    }
    
    private var shouldShowOnboarding: Bool {
        return showOnboarding && !onboardingManager.hasCompletedOnboarding
    }
    
    private func checkOnboardingStatus() {
        // Show onboarding if:
        // 1. User hasn't completed onboarding AND
        // 2. No goals exist (first time user)
        let shouldShow = !onboardingManager.hasCompletedOnboarding && goals.isEmpty
        
        if shouldShow != showOnboarding {
            withAnimation(.easeInOut(duration: 0.4)) {
                showOnboarding = shouldShow
            }
        }
    }
}

#Preview {
    OnboardingContentView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}